import { chromium } from 'playwright-core';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const root = resolve('.');
const artifacts = resolve(root, 'tests/artifacts');
mkdirSync(artifacts, { recursive: true });
if (!existsSync(edge)) throw new Error('Edge executable not found');
const usbFixture = readFileSync(resolve(root, 'tests/fixtures/usb_frame.bin'));

const browser = await chromium.launch({ executablePath: edge, headless: true, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
page.on('console', (message) => {
  if (message.type() === 'error') errors.push(`console: ${message.text()}`);
});

await page.addInitScript(() => {
  class FakePort extends EventTarget {
    constructor() {
      super();
      this.readable = null;
      this.writable = null;
    }
    async open() {
      this.readable = new ReadableStream({
        start(controller) {
          window.__fakePush = (bytes) => controller.enqueue(Uint8Array.from(bytes));
          window.__fakeClose = () => controller.close();
        },
      });
      this.writable = new WritableStream();
    }
    async close() {
      this.readable = null;
      this.writable = null;
      try { window.__fakeClose?.(); } catch {}
    }
  }
  const fakePort = new FakePort();
  const fakeSerial = new EventTarget();
  fakeSerial.requestPort = async () => fakePort;
  fakeSerial.getPorts = async () => [fakePort];
  Object.defineProperty(Navigator.prototype, 'serial', { configurable: true, get: () => fakeSerial });
});

const waitState = (state) => page.waitForFunction(
  (wanted) => document.querySelector('#statusPill')?.dataset.state === wanted,
  state,
);

await page.goto('http://127.0.0.1:5173/', { waitUntil: 'networkidle' });
await page.waitForTimeout(400);
await page.locator('#connectButton').click();
await waitState('waiting');
const waiting = await page.evaluate(() => document.querySelector('#statusPill')?.dataset.state);

const justFrames = [];
for (let index = 0; index < 512; index += 1) {
  const sample = Math.sin(index / 12) * 15000;
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setFloat32(0, sample, true);
  bytes.set([0, 0, 0x80, 0x7f], 4);
  justFrames.push(...bytes);
}
await page.evaluate((bytes) => window.__fakePush?.(bytes), justFrames);
await waitState('receiving');
await page.waitForTimeout(180);
await page.screenshot({ path: resolve(artifacts, 'serial-justfloat.png'), fullPage: true });
const just = await page.evaluate(() => ({
  status: document.querySelector('#statusText')?.textContent,
  format: document.querySelector('#formatValue')?.textContent,
  rate: document.querySelector('#rateValue')?.textContent,
  frames: document.querySelector('#framesValue')?.textContent,
  spectrum: document.querySelector('#diagSpectrum')?.textContent,
  bytes: document.querySelector('#bytesValue')?.textContent,
}));

await page.waitForTimeout(1900);
const interrupted = await page.evaluate(() => ({
  state: document.querySelector('#statusPill')?.dataset.state,
  status: document.querySelector('#statusText')?.textContent,
}));

await page.locator('#disconnectButton').click();
await page.waitForTimeout(300);
await page.locator('#connectButton').click();
await waitState('waiting');

await page.evaluate((bytes) => window.__fakePush?.(bytes), Array.from(usbFixture.subarray(0, 275)));
await page.waitForTimeout(120);
const beforeComplete = await page.evaluate(() => ({
  frames: document.querySelector('#framesValue')?.textContent,
  state: document.querySelector('#statusPill')?.dataset.state,
}));
await page.evaluate((bytes) => window.__fakePush?.(bytes), Array.from(usbFixture.subarray(275)));
await waitState('receiving');
await page.waitForTimeout(350);
await page.screenshot({ path: resolve(artifacts, 'serial-minmax.png'), fullPage: true });
const framedUi = await page.evaluate(() => ({
  status: document.querySelector('#statusText')?.textContent,
  format: document.querySelector('#formatValue')?.textContent,
  rate: document.querySelector('#rateValue')?.textContent,
  frames: document.querySelector('#framesValue')?.textContent,
  spectrum: document.querySelector('#diagSpectrum')?.textContent,
  protocol: document.querySelector('#diagProtocol')?.textContent,
  source: document.querySelector('#sourcePill')?.textContent,
  rawMeta: document.querySelector('#rawMeta')?.textContent,
  rawPreview: document.querySelector('#rawPreview')?.textContent?.slice(0, 160),
}));

await page.locator('#diagnostics').evaluate((element) => { element.open = true; });
await page.locator('.control-panel').evaluate((element) => { element.scrollTop = element.scrollHeight; });
await page.waitForTimeout(180);
await page.screenshot({ path: resolve(artifacts, 'serial-diagnostics.png'), fullPage: true });

const broken = Uint8Array.from(usbFixture);
broken[548] ^= 0x01;
await page.evaluate((bytes) => window.__fakePush?.(bytes), Array.from(broken));
await page.waitForTimeout(400);
const errorUi = await page.evaluate(() => ({
  code: document.querySelector('#parseErrorCode')?.textContent,
  detail: document.querySelector('#parseErrorDetail')?.textContent,
  frames: document.querySelector('#framesValue')?.textContent,
  errors: document.querySelector('#errorsValue')?.textContent,
  rawPreview: document.querySelector('#rawPreview')?.textContent?.slice(0, 160),
}));

console.log(JSON.stringify({ waiting, just, interrupted, beforeComplete, framedUi, errorUi, errors }, null, 2));
await browser.close();
if (errors.length) process.exitCode = 2;
