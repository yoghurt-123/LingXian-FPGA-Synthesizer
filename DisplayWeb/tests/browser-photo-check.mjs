import { chromium } from 'playwright-core';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const root = resolve('.');
const artifacts = resolve(root, 'tests/artifacts');
mkdirSync(artifacts, { recursive: true });
if (!existsSync(edge)) throw new Error('Edge executable not found');

const expected = Array.from({ length: 8 }, (_, index) =>
  `default-20261031-${String(index + 1).padStart(2, '0')}.jpg`,
);
const expectedSet = new Set(expected);

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

const stageHash = async () =>
  createHash('sha256').update(await page.locator('#stage').screenshot()).digest('hex');

const waitForPhotos = async () => {
  await page.waitForFunction(
    () => document.querySelector('#photoCount')?.textContent?.includes('8 '),
  );
  await page.waitForTimeout(700);
};

const loadedPhotoNames = async () =>
  page.evaluate(() =>
    performance
      .getEntriesByType('resource')
      .map((entry) => entry.name)
      .filter((name) => name.includes('/photos/'))
      .map((name) => name.split('/').pop() ?? ''),
  );

await page.goto('http://127.0.0.1:5173/', { waitUntil: 'networkidle' });
await waitForPhotos();
const initialNames = await loadedPhotoNames();
const initialCount = await page.locator('#photoCount').textContent();
const oldPhotoStatus = await page.request.get('http://127.0.0.1:5173/photos/photo-01.jpg');
if (oldPhotoStatus.status() !== 404) {
  errors.push(`old default photo still served: ${oldPhotoStatus.status()}`);
}

await page.locator('#intervalRange').evaluate((element) => {
  element.value = '4';
  element.dispatchEvent(new Event('input', { bubbles: true }));
});
await page.waitForTimeout(200);
const normalBefore = await stageHash();
await page.screenshot({ path: resolve(artifacts, 'photos-normal.png'), fullPage: true });
await page.waitForTimeout(5200);
const normalAfter = await stageHash();
if (normalBefore === normalAfter) errors.push('normal carousel did not change the stage');

await page.locator('#fullscreenButton').click();
await page.waitForTimeout(900);
const fullscreenState = await page.evaluate(() => ({
  fullscreen: document.fullscreenElement !== null,
  bodyFullscreen: document.body.classList.contains('is-fullscreen'),
  panelDisplay: getComputedStyle(document.querySelector('.control-panel')).display,
  photoCount: document.querySelector('#photoCount')?.textContent,
}));
const fullscreenBefore = await stageHash();
await page.screenshot({ path: resolve(artifacts, 'photos-fullscreen.png'), fullPage: true });
await page.waitForTimeout(5200);
const fullscreenAfter = await stageHash();
if (fullscreenBefore === fullscreenAfter) errors.push('fullscreen carousel did not change the stage');
if (!fullscreenState.fullscreen || !fullscreenState.bodyFullscreen) errors.push('fullscreen state did not activate');
if (fullscreenState.panelDisplay !== 'none') errors.push('control panel is visible in fullscreen: ' + fullscreenState.panelDisplay);
await page.locator('#exitFullscreenButton').click();
await page.waitForTimeout(500);

await page.reload({ waitUntil: 'networkidle' });
await waitForPhotos();
const reloadCount = await page.locator('#photoCount').textContent();
const reloadNames = await loadedPhotoNames();
if (!reloadNames.some((name) => expectedSet.has(name))) errors.push('no new default photo loaded after reload');

await page.evaluate(() => {
  localStorage.setItem('instrument-display-default-photo-set', 'old-set');
  localStorage.setItem('instrument-display-interval', '25');
  localStorage.setItem('instrument-display-settings', JSON.stringify({ photoOffset: 0.8, spectrumColumns: 96 }));
});
await page.reload({ waitUntil: 'networkidle' });
await waitForPhotos();
const migrated = await page.evaluate(() => ({
  interval: Number(document.querySelector('#intervalRange')?.value),
  photoOffset: Number(document.querySelector('#photoOffsetRange')?.value),
  settings: localStorage.getItem('instrument-display-settings'),
  marker: localStorage.getItem('instrument-display-default-photo-set'),
}));
if (migrated.interval !== 10) errors.push(`legacy interval was not reset: ${migrated.interval}`);
if (migrated.photoOffset !== 0) errors.push(`legacy composition was not reset: ${migrated.photoOffset}`);
if (!migrated.marker) errors.push('photo-set migration marker missing');

const finalNames = await loadedPhotoNames();
const missing = expected.filter((name) => !finalNames.includes(name));
const unexpected = finalNames.filter((name) => !expectedSet.has(name));
const sourcePathLeaks = finalNames.filter((name) => /GowinProjects|text4|picture/i.test(name));

console.log(JSON.stringify({
  initialCount,
  expected,
  initialNames,
  reloadCount,
  reloadNames,
  fullscreenState,
  normalCarouselChanged: normalBefore !== normalAfter,
  fullscreenCarouselChanged: fullscreenBefore !== fullscreenAfter,
  migrated,
  missing,
  unexpected,
  sourcePathLeaks,
  errors,
}, null, 2));

await browser.close();
if (errors.length || missing.length || unexpected.length || sourcePathLeaks.length) {
  process.exitCode = 2;
}
