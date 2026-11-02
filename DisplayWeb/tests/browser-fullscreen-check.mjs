import { chromium } from 'playwright-core';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const root = resolve('.');
const artifacts = resolve(root, 'tests/artifacts');
mkdirSync(artifacts, { recursive: true });
if (!existsSync(edge)) throw new Error('Edge executable not found');
const usbFrame = readFileSync(resolve(root, 'tests/fixtures/usb_frame.bin'));

const browser = await chromium.launch({ executablePath: edge, headless: true, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
page.on('console', (message) => { if (message.type() === 'error') errors.push(`console: ${message.text()}`); });

await page.addInitScript(() => {
  class FakePort extends EventTarget {
    constructor() { super(); this.readable = null; this.writable = null; }
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
  const port = new FakePort();
  const serial = new EventTarget();
  serial.requestPort = async () => port;
  serial.getPorts = async () => [port];
  Object.defineProperty(Navigator.prototype, 'serial', { configurable: true, get: () => serial });
});

const waitState = (state) => page.waitForFunction(
  (wanted) => document.querySelector('#statusPill')?.dataset.state === wanted,
  state,
);

const measure = () => page.evaluate(() => {
  const canvas = document.querySelector('#stage');
  const rect = canvas?.getBoundingClientRect();
  return {
    viewport: [innerWidth, innerHeight],
    canvasCss: rect ? [Math.round(rect.width), Math.round(rect.height)] : null,
    canvasBuffer: canvas ? [canvas.width, canvas.height] : null,
    dpr: devicePixelRatio,
    fullscreenElement: document.fullscreenElement !== null,
    bodyFullscreen: document.body.classList.contains('is-fullscreen'),
    hudHidden: document.querySelector('#fullscreenHud')?.hidden,
    panelDisplay: getComputedStyle(document.querySelector('.control-panel')).display,
    status: document.querySelector('#statusText')?.textContent,
    source: document.querySelector('#sourcePill')?.textContent,
    spectrum: document.querySelector('#diagSpectrum')?.textContent,
  };
});

await page.goto('http://127.0.0.1:5173/', { waitUntil: 'networkidle' });
await page.waitForTimeout(300);
await page.locator('#connectButton').click();
await waitState('waiting');
await page.evaluate((bytes) => {
  window.__stream = setInterval(() => window.__fakePush?.(bytes), 50);
}, Array.from(usbFrame));
await waitState('receiving');
await page.waitForTimeout(900);
await page.screenshot({ path: resolve(artifacts, 'layout-normal.png'), fullPage: true });
const normal = await measure();

await page.selectOption('#spectrumBars', '96');
await page.waitForTimeout(150);
const columns96 = await page.locator('#diagSpectrum').textContent();
await page.selectOption('#spectrumBars', '32');
await page.waitForTimeout(150);
const columns32 = await page.locator('#diagSpectrum').textContent();
await page.selectOption('#spectrumBars', '64');
await page.waitForTimeout(150);

await page.locator('#fullscreenButton').click();
await page.waitForTimeout(900);
const fullscreen = await measure();
await page.screenshot({ path: resolve(artifacts, 'layout-fullscreen.png'), fullPage: true });

await page.setViewportSize({ width: 1920, height: 1080 });
await page.waitForTimeout(700);
const fullscreenResized = await measure();
await page.screenshot({ path: resolve(artifacts, 'layout-fullscreen-1920.png'), fullPage: true });

await page.locator('#exitFullscreenButton').click();
await page.waitForTimeout(500);
const exited = await measure();

await page.setViewportSize({ width: 1600, height: 900 });
await page.waitForTimeout(600);
const normalResized = await measure();

await page.locator('#fullscreenButton').click();
await page.waitForTimeout(700);
const fullscreenReentered = await measure();
await page.locator('#exitFullscreenButton').click();
await page.waitForTimeout(300);
await page.evaluate(() => clearInterval(window.__stream));

await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(300);
await page.locator('#fullscreenButton').click();
await page.waitForTimeout(500);
await page.locator('#fsConnectButton').click();
await waitState('waiting');
await page.evaluate((bytes) => window.__fakePush?.(bytes), Array.from(usbFrame));
await waitState('receiving');
await page.waitForTimeout(500);
const fullscreenFirst = await measure();
await page.locator('#fsDisconnectButton').click();
await page.waitForTimeout(300);
await page.locator('#exitFullscreenButton').click();

console.log(JSON.stringify({ normal, columns96, columns32, fullscreen, fullscreenResized, exited, normalResized, fullscreenReentered, fullscreenFirst, errors }, null, 2));
await browser.close();
if (errors.length) process.exitCode = 2;
