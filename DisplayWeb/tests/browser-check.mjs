import { chromium } from 'playwright-core';
import { existsSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const root = resolve('.');
const artifacts = resolve(root, 'tests/artifacts');
mkdirSync(artifacts, { recursive: true });
if (!existsSync(edge)) throw new Error('Edge executable not found');

const browser = await chromium.launch({
  executablePath: edge,
  headless: true,
  args: ['--no-sandbox', '--disable-gpu'],
});
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
page.on('console', (message) => {
  if (message.type() === 'error') errors.push(`console: ${message.text()}`);
});

await page.goto('http://127.0.0.1:5173/', { waitUntil: 'networkidle' });
await page.waitForTimeout(800);
await page.screenshot({ path: resolve(artifacts, 'initial.png'), fullPage: true });

const initial = await page.evaluate(() => ({
  title: document.title,
  status: document.querySelector('#statusText')?.textContent,
  format: document.querySelector('#formatValue')?.textContent,
  serial: 'serial' in navigator,
  secure: window.isSecureContext,
  canvas: (() => {
    const canvas = document.querySelector('#stage');
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return null;
    const pixels = ctx.getImageData(0, 0, Math.min(canvas.width, 80), Math.min(canvas.height, 80)).data;
    let sum = 0;
    for (let i = 0; i < pixels.length; i += 4) sum += pixels[i] + pixels[i + 1] + pixels[i + 2];
    return { width: canvas.width, height: canvas.height, nonBlack: sum > 0 };
  })(),
}));

await page.locator('#demoToggle').evaluate((element) => {
  const input = element;
  input.checked = true;
  input.dispatchEvent(new Event('change', { bubbles: true }));
});
await page.waitForTimeout(1200);
await page.screenshot({ path: resolve(artifacts, 'demo.png'), fullPage: true });
const demo = await page.evaluate(() => ({
  status: document.querySelector('#statusText')?.textContent,
  bannerHidden: document.querySelector('#demoBanner')?.hidden,
  format: document.querySelector('#formatValue')?.textContent,
  rate: document.querySelector('#rateValue')?.textContent,
  canvas: (() => {
    const canvas = document.querySelector('#stage');
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return null;
    const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    let sum = 0;
    for (let i = 0; i < pixels.length; i += 4) sum += pixels[i] + pixels[i + 1] + pixels[i + 2];
    return { width: canvas.width, height: canvas.height, nonBlack: sum > 0 };
  })(),
}));

await page.locator('#photoInput').setInputFiles(resolve(root, 'public/photos/default-20261031-01.jpg'));
await page.waitForTimeout(300);
const photos = await page.locator('#photoCount').textContent();

await page.locator('#diagnostics').evaluate((element) => { element.open = true; });
await page.screenshot({ path: resolve(artifacts, 'diagnostics.png'), fullPage: true });

console.log(JSON.stringify({ initial, demo, photos, errors }, null, 2));
await browser.close();
if (errors.length) process.exitCode = 2;
