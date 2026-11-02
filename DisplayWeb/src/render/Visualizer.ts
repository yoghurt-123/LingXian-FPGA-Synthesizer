import { WaveHistory } from '../audio/WaveHistory';
import type { ParserMode } from '../types';
import { PhotoDeck } from './PhotoDeck';
import { SpectrumDisplay, type SpectrumColumnCount } from './SpectrumDisplay';

export type DataState = 'none' | 'waiting' | 'receiving' | 'interrupted' | 'adc';

export interface VisualSettings {
  spectrumColor: string;
  waveColor: string;
  intensity: number;
  spectrumColumns: SpectrumColumnCount;
  spectrumGain: number;
  photoOffset: number;
}

interface DataMeta {
  sampleRate: number;
  mode: ParserMode;
  source: 'justfloat' | 'framed' | 'adc' | 'demo' | 'none';
  detail: string;
}

const FONT_MONO = '"Cascadia Mono", Consolas, monospace';
const FONT_SANS = 'Inter, "Segoe UI", "Microsoft YaHei UI", system-ui, sans-serif';

export class Visualizer {
  private readonly ctx: CanvasRenderingContext2D;
  private readonly history = new WaveHistory(8192);
  private readonly photoDeck: PhotoDeck;
  private width = 0;
  private height = 0;
  private dpr = 1;
  private settings: VisualSettings = {
    spectrumColor: '#46d7e8',
    waveColor: '#9bffef',
    intensity: 0.78,
    spectrumColumns: 64,
    spectrumGain: 1.4,
    photoOffset: 0,
  };
  private readonly spectrumDisplay = new SpectrumDisplay();
  private fullscreen = false;
  private spectrum: Uint8Array | null = null;
  private spectrumAt = 0;
  private spectrumAlpha = 0;
  private waveAt = 0;
  private waveAlpha = 0;
  private dataState: DataState = 'none';
  private mode: ParserMode = 'unknown';
  private source: DataMeta['source'] = 'none';
  private sampleRate = 0;
  private detail = '等待串口数据';
  private demo = false;
  private adcValues: number[] | null = null;
  private envelope: { mins: Float32Array; maxs: Float32Array; groupSize: number } | null = null;
  private animation = 0;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    photoDeck: PhotoDeck,
  ) {
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Canvas 2D 不可用');
    this.ctx = context;
    this.photoDeck = photoDeck;

    this.spectrumDisplay.setSettings({
      columns: this.settings.spectrumColumns,
      gain: this.settings.spectrumGain,
      intensity: this.settings.intensity,
    });
    new ResizeObserver(() => this.resize()).observe(canvas);
    window.addEventListener('resize', () => this.resize());
    this.resize();
    this.loop();
  }

  setSettings(settings: Partial<VisualSettings>): void {
    this.settings = { ...this.settings, ...settings };
    this.spectrumDisplay.setSettings({
      columns: this.settings.spectrumColumns,
      gain: this.settings.spectrumGain,
      intensity: this.settings.intensity,
    });
  }

  setFullscreen(active: boolean): void {
    this.fullscreen = active;
    this.resize();
  }

  refreshSize(): void {
    this.resize();
  }

  setMeta(meta: Partial<DataMeta>): void {
    if (meta.sampleRate !== undefined) this.sampleRate = meta.sampleRate;
    if (meta.mode !== undefined) this.mode = meta.mode;
    if (meta.source !== undefined) this.source = meta.source;
    if (meta.detail !== undefined) this.detail = meta.detail;
  }

  setDataState(state: DataState): void {
    this.dataState = state;
    if (state === 'none') {
      this.spectrum = null;
      this.spectrumAt = 0;
      this.spectrumAlpha = 0;
      this.waveAlpha = 0;
      this.envelope = null;
      this.history.clear();
      this.spectrumDisplay.reset();
    }
  }

  setDemo(demo: boolean): void {
    this.demo = demo;
    if (demo) {
      this.envelope = null;
      this.source = 'demo';
      this.sampleRate = 48_000;
      this.mode = 'framed';
      this.detail = 'DEMO / 本地生成';
    }
  }

  setAdc(values: number[] | null): void {
    this.adcValues = values;
  }

  pushWave(samples: Float32Array, sampleRate: number): void {
    this.envelope = null;
    this.history.append(samples);
    this.waveAt = performance.now();
    this.sampleRate = sampleRate;
    this.waveAlpha = 1;
  }

  pushEnvelope(mins: Float32Array, maxs: Float32Array, sampleRate: number, groupSize = 4): void {
    if (mins.length !== maxs.length || mins.length === 0) return;
    this.envelope = { mins, maxs, groupSize };
    this.waveAt = performance.now();
    this.sampleRate = sampleRate;
    this.waveAlpha = 1;
  }

  pushSpectrum(values: Uint8Array, sampleRate: number): void {
    this.spectrum = values.slice();
    this.spectrumAt = performance.now();
    this.sampleRate = sampleRate;
    this.spectrumDisplay.setValues(values);
  }

  clearWave(): void {
    this.history.clear();
    this.envelope = null;
    this.waveAlpha = 0;
    this.adcValues = null;
  }

  clearSpectrum(): void {
    this.spectrum = null;
    this.spectrumAt = 0;
    this.spectrumAlpha = 0;
    this.spectrumDisplay.reset();
  }

  private resize(): void {
    const rect = this.canvas.getBoundingClientRect();
    this.dpr = Math.min(2, window.devicePixelRatio || 1);
    this.width = Math.max(1, rect.width);
    this.height = Math.max(1, rect.height);
    this.canvas.width = Math.round(this.width * this.dpr);
    this.canvas.height = Math.round(this.height * this.dpr);
    this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
  }

  private loop = (): void => {
    this.animation = requestAnimationFrame(this.loop);
    this.render(performance.now());
  };

  private render(now: number): void {
    const ctx = this.ctx;
    const W = this.width;
    const H = this.height;
    if (W <= 1 || H <= 1) return;

    const receiving = this.dataState === 'receiving' || this.demo;
    const stale = now - Math.max(this.waveAt, this.spectrumAt);
    const staleAlpha = receiving
      ? 1
      : this.dataState === 'waiting'
        ? 0.35
        : this.dataState === 'interrupted'
          ? Math.max(0, 1 - stale / 1800)
          : this.dataState === 'adc'
            ? 0.35
            : 0;
    this.waveAlpha += (staleAlpha - this.waveAlpha) * 0.08;
    const spectrumTarget = receiving && this.spectrum ? 1 : staleAlpha * (this.spectrum ? 1 : 0);
    this.spectrumAlpha += (spectrumTarget - this.spectrumAlpha) * 0.08;

    this.drawBackground(ctx, W, H);

    const margin = this.fullscreen ? 0 : Math.max(18, Math.min(30, W * 0.022));
    const photo = { x: 0, y: 0, w: W, h: H };
    this.drawPhotoStage(ctx, photo, now);

    const spectrumRect = {
      x: Math.max(26, margin + 18),
      y: H * 0.615,
      w: W - Math.max(52, margin * 2 + 36),
      h: Math.max(160, H * 0.31),
    };
    this.drawSpectrum(ctx, spectrumRect, now);

    const waveRect = {
      x: Math.max(36, W * 0.10),
      y: H * 0.335,
      w: Math.min(W - 72, W * 0.80),
      h: Math.max(115, H * 0.205),
    };
    this.drawWavePanel(ctx, waveRect, now);

    if (this.demo) this.drawDemoMark(ctx, photo);
  }

  private drawBackground(ctx: CanvasRenderingContext2D, W: number, H: number): void {
    ctx.clearRect(0, 0, W, H);
    const backdrop = ctx.createLinearGradient(0, 0, W, H);
    backdrop.addColorStop(0, '#0a0f16');
    backdrop.addColorStop(0.54, '#080c12');
    backdrop.addColorStop(1, '#06090e');
    ctx.fillStyle = backdrop;
    ctx.fillRect(0, 0, W, H);

    ctx.save();
    ctx.strokeStyle = 'rgba(177, 224, 236, 0.035)';
    ctx.lineWidth = 1;
    const grid = 64;
    for (let x = (W % grid) / 2; x < W; x += grid) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, H);
      ctx.stroke();
    }
    for (let y = (H % grid) / 2; y < H; y += grid) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(W, y);
      ctx.stroke();
    }
    ctx.restore();

    const glow = ctx.createRadialGradient(W * 0.42, H * 0.12, 10, W * 0.42, H * 0.12, W * 0.62);
    glow.addColorStop(0, 'rgba(70, 215, 232, 0.06)');
    glow.addColorStop(1, 'rgba(70, 215, 232, 0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, W, H);
  }

  private drawPhotoStage(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
    now: number,
  ): void {
    const frame = this.photoDeck.getFrame(now);
    const radius = this.fullscreen ? 0 : 17;
    ctx.save();
    roundedRect(ctx, rect.x, rect.y, rect.w, rect.h, radius);
    ctx.clip();
    ctx.fillStyle = '#0a1017';
    ctx.fillRect(rect.x, rect.y, rect.w, rect.h);

    if (frame.previous && frame.fade < 1) {
      drawImageCover(ctx, frame.previous.image, rect, this.settings.photoOffset);
    }
    if (frame.current) {
      ctx.globalAlpha = frame.previous ? frame.fade : 1;
      drawImageCover(ctx, frame.current.image, rect, this.settings.photoOffset);
      ctx.globalAlpha = 1;
    } else {
      this.drawPhotoPlaceholder(ctx, rect);
    }

    const lower = ctx.createLinearGradient(0, rect.y + rect.h * 0.36, 0, rect.y + rect.h);
    lower.addColorStop(0, 'rgba(3, 8, 13, 0)');
    lower.addColorStop(0.50, 'rgba(3, 8, 13, 0.30)');
    lower.addColorStop(1, 'rgba(3, 8, 13, 0.94)');
    ctx.fillStyle = lower;
    ctx.fillRect(rect.x, rect.y, rect.w, rect.h);

    const top = ctx.createLinearGradient(0, rect.y, 0, rect.y + rect.h * 0.28);
    top.addColorStop(0, 'rgba(3, 8, 13, 0.62)');
    top.addColorStop(1, 'rgba(3, 8, 13, 0)');
    ctx.fillStyle = top;
    ctx.fillRect(rect.x, rect.y, rect.w, rect.h);

    ctx.textAlign = 'left';
    ctx.font = `10px ${FONT_MONO}`;
    ctx.fillStyle = 'rgba(230, 238, 243, 0.62)';
    ctx.fillText(
      frame.count > 0 ? `PHOTO ${String(frame.index + 1).padStart(2, '0')} / ${String(frame.count).padStart(2, '0')}` : 'PHOTO STAGE',
      rect.x + 24,
      rect.y + 27,
    );
    ctx.fillStyle = 'rgba(230, 238, 243, 0.32)';
    ctx.fillText(frame.current?.name.toUpperCase() ?? 'NO LOCAL PHOTO', rect.x + 24, rect.y + 43);

    ctx.fillStyle = 'rgba(230, 238, 243, 0.12)';
    ctx.fillRect(rect.x + 24, rect.y + 58, Math.min(180, rect.w * 0.22), 1.5);
    ctx.fillStyle = withAlpha(this.settings.spectrumColor, 0.6);
    ctx.fillRect(rect.x + 24, rect.y + 58, Math.min(180, rect.w * 0.22) * frame.progress, 1.5);

    ctx.restore();

    ctx.save();
    roundedRect(ctx, rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1, radius);
    ctx.strokeStyle = 'rgba(177, 224, 236, 0.16)';
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.restore();
  }

  private drawPhotoPlaceholder(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
  ): void {
    const gradient = ctx.createLinearGradient(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h);
    gradient.addColorStop(0, '#101a24');
    gradient.addColorStop(0.55, '#0c141d');
    gradient.addColorStop(1, '#101820');
    ctx.fillStyle = gradient;
    ctx.fillRect(rect.x, rect.y, rect.w, rect.h);

    ctx.save();
    ctx.strokeStyle = 'rgba(177, 224, 236, 0.07)';
    ctx.lineWidth = 1;
    const step = Math.max(42, rect.w / 16);
    for (let x = rect.x; x < rect.x + rect.w; x += step) {
      ctx.beginPath();
      ctx.moveTo(x, rect.y);
      ctx.lineTo(x, rect.y + rect.h);
      ctx.stroke();
    }
    for (let y = rect.y; y < rect.y + rect.h; y += step) {
      ctx.beginPath();
      ctx.moveTo(rect.x, y);
      ctx.lineTo(rect.x + rect.w, y);
      ctx.stroke();
    }
    ctx.restore();

    ctx.textAlign = 'center';
    ctx.fillStyle = 'rgba(230, 238, 243, 0.22)';
    ctx.font = `600 13px ${FONT_MONO}`;
    ctx.fillText('IMPORT LOCAL PHOTOS', rect.x + rect.w / 2, rect.y + rect.h / 2);
    ctx.font = `10px ${FONT_MONO}`;
    ctx.fillStyle = 'rgba(230, 238, 243, 0.15)';
    ctx.fillText('JPG / PNG / WEBP · LOCAL ONLY', rect.x + rect.w / 2, rect.y + rect.h / 2 + 22);
  }

  private drawSpectrum(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
    now: number,
  ): void {
    const alpha = this.spectrumAlpha * (0.55 + this.settings.intensity * 0.65);
    if (!this.spectrum || alpha <= 0.01) {
      this.drawSpectrumPlaceholder(ctx, rect);
      return;
    }

    const backdrop = ctx.createLinearGradient(0, rect.y, 0, rect.y + rect.h);
    backdrop.addColorStop(0, 'rgba(3, 8, 13, 0)');
    backdrop.addColorStop(0.16, 'rgba(3, 8, 13, 0.42)');
    backdrop.addColorStop(1, 'rgba(3, 8, 13, 0.82)');
    ctx.fillStyle = backdrop;
    ctx.fillRect(rect.x - 8, rect.y - 4, rect.w + 16, rect.h + 4);

    const glow = ctx.createLinearGradient(0, rect.y, 0, rect.y + rect.h);
    glow.addColorStop(0, withAlpha(this.settings.spectrumColor, 0.04 * alpha));
    glow.addColorStop(1, withAlpha(this.settings.spectrumColor, 0.12 * alpha));
    ctx.fillStyle = glow;
    ctx.fillRect(rect.x - 8, rect.y, rect.w + 16, rect.h);

    ctx.save();
    ctx.globalAlpha = alpha;
    this.spectrumDisplay.draw(ctx, rect, now);
    ctx.restore();

    const realBands = this.spectrumDisplay.realBandCount || this.spectrum.length;
    const bars = this.spectrumDisplay.displayedColumnCount;
    ctx.fillStyle = 'rgba(3, 8, 13, 0.58)';
    ctx.fillRect(rect.x - 6, rect.y - 24, rect.w + 12, 19);
    ctx.textAlign = 'left';
    ctx.font = `9px ${FONT_MONO}`;
    ctx.fillStyle = withAlpha('#d8f8ff', 0.62 * alpha);
    ctx.fillText(
      `SPECTRUM / ${realBands} REAL BANDS · ${bars} DISPLAY COLUMNS`,
      rect.x,
      rect.y - 8,
    );
    ctx.textAlign = 'right';
    ctx.fillStyle = withAlpha('#d8f8ff', 0.36 * alpha);
    ctx.fillText(
      `${formatRate(this.sampleRate)} S/s · ${this.spectrumDisplay.realBandCount === 16 ? 'GOERTZEL 16' : 'FPGA'}`,
      rect.x + rect.w,
      rect.y - 8,
    );
  }

  private drawSpectrumPlaceholder(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
  ): void {
    const baseY = rect.y + rect.h;
    ctx.save();
    ctx.strokeStyle = 'rgba(230, 238, 243, 0.12)';
    ctx.setLineDash([4, 8]);
    ctx.beginPath();
    ctx.moveTo(rect.x, baseY);
    ctx.lineTo(rect.x + rect.w, baseY);
    ctx.stroke();
    ctx.restore();

    const label = this.source === 'justfloat'
      ? 'SPECTRUM / LEGACY PCM STREAM HAS NO FFT'
      : this.source === 'adc'
        ? 'SPECTRUM / NOT APPLICABLE TO ADC TELEMETRY'
        : this.dataState === 'interrupted'
          ? 'SPECTRUM / DATA INTERRUPTED'
          : 'SPECTRUM / WAITING FOR FPGA FRAME';
    ctx.textAlign = 'left';
    ctx.font = `9px ${FONT_MONO}`;
    ctx.fillStyle = 'rgba(230, 238, 243, 0.32)';
    ctx.fillText(label, rect.x, rect.y - 7);
  }

  private drawWavePanel(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
    now: number,
  ): void {
    ctx.save();
    roundedRect(ctx, rect.x, rect.y, rect.w, rect.h, 12);
    ctx.fillStyle = 'rgba(6, 11, 16, 0.66)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(177, 224, 236, 0.11)';
    ctx.stroke();
    ctx.clip();

    const inner = { x: rect.x + 18, y: rect.y + 35, w: rect.w - 36, h: rect.h - 54 };
    this.drawWaveGrid(ctx, inner);

    ctx.textAlign = 'left';
    ctx.font = `9px ${FONT_MONO}`;
    ctx.fillStyle = 'rgba(230, 238, 243, 0.5)';
    ctx.fillText(this.envelope ? 'TIME DOMAIN / MIN-MAX ENVELOPE' : 'TIME DOMAIN / PCM', rect.x + 18, rect.y + 23);
    ctx.textAlign = 'right';
    ctx.fillStyle = 'rgba(230, 238, 243, 0.35)';
    ctx.fillText(this.waveSubtitle(), rect.x + rect.w - 18, rect.y + 23);

    const hasWave = (this.envelope !== null || this.history.length > 1) && this.waveAlpha > 0.02;
    if (!hasWave) {
      ctx.save();
      ctx.strokeStyle = 'rgba(230, 238, 243, 0.13)';
      ctx.setLineDash([3, 7]);
      ctx.beginPath();
      ctx.moveTo(inner.x, inner.y + inner.h / 2);
      ctx.lineTo(inner.x + inner.w, inner.y + inner.h / 2);
      ctx.stroke();
      ctx.restore();
      ctx.textAlign = 'center';
      ctx.font = `10px ${FONT_MONO}`;
      ctx.fillStyle = 'rgba(230, 238, 243, 0.24)';
      ctx.fillText(this.emptyWaveText(), rect.x + rect.w / 2, inner.y + inner.h / 2 + 23);
    } else if (this.envelope) {
      this.drawEnvelope(ctx, this.envelope, inner);
    } else {
      const source = this.history.latest(2048);
      const display = this.selectTriggeredWindow(source, Math.min(640, Math.max(256, inner.w * 0.55)));
      this.drawWaveLine(ctx, display, inner, now);
    }

    ctx.restore();
  }

  private drawEnvelope(
    ctx: CanvasRenderingContext2D,
    envelope: { mins: Float32Array; maxs: Float32Array; groupSize: number },
    rect: { x: number; y: number; w: number; h: number },
  ): void {
    const count = envelope.mins.length;
    if (count < 2) return;

    let peak = 1;
    for (let index = 0; index < count; index += 1) {
      peak = Math.max(peak, Math.abs(envelope.mins[index]), Math.abs(envelope.maxs[index]));
    }

    const centerY = rect.y + rect.h / 2;
    const scale = (rect.h * 0.44) / Math.max(2200, peak);
    const step = rect.w / Math.max(1, count - 1);
    const color = this.settings.waveColor;
    const alpha = this.waveAlpha * (0.62 + this.settings.intensity * 0.5);

    ctx.save();
    ctx.fillStyle = withAlpha(color, 0.22 * alpha);
    ctx.strokeStyle = withAlpha(color, 0.9 * alpha);
    ctx.lineWidth = 1.5;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    for (let index = 0; index < count; index += 1) {
      const x = rect.x + index * step;
      const top = centerY - envelope.maxs[index] * scale;
      const bottom = centerY - envelope.mins[index] * scale;
      ctx.moveTo(x, top);
      ctx.lineTo(x, bottom);
    }
    ctx.stroke();

    ctx.beginPath();
    for (let index = 0; index < count; index += 1) {
      const x = rect.x + index * step;
      const y = centerY - envelope.maxs[index] * scale;
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    for (let index = count - 1; index >= 0; index -= 1) {
      const x = rect.x + index * step;
      const y = centerY - envelope.mins[index] * scale;
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fill();
    ctx.restore();

    ctx.textAlign = 'left';
    ctx.font = `9px ${FONT_MONO}`;
    ctx.fillStyle = withAlpha(color, 0.38 * alpha);
    ctx.fillText(`PEAK ${Math.round(peak)} · ${count} GROUPS · ${envelope.groupSize} SAMPLES/GROUP`, rect.x, rect.y + rect.h + 12);
  }

  private drawWaveGrid(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
  ): void {
    ctx.save();
    ctx.strokeStyle = 'rgba(177, 224, 236, 0.055)';
    ctx.lineWidth = 1;
    for (let index = 1; index < 8; index += 1) {
      const x = rect.x + (rect.w * index) / 8;
      ctx.beginPath();
      ctx.moveTo(x, rect.y);
      ctx.lineTo(x, rect.y + rect.h);
      ctx.stroke();
    }
    for (let index = 1; index < 4; index += 1) {
      const y = rect.y + (rect.h * index) / 4;
      ctx.beginPath();
      ctx.moveTo(rect.x, y);
      ctx.lineTo(rect.x + rect.w, y);
      ctx.stroke();
    }
    ctx.strokeStyle = 'rgba(177, 224, 236, 0.09)';
    ctx.beginPath();
    ctx.moveTo(rect.x, rect.y + rect.h / 2);
    ctx.lineTo(rect.x + rect.w, rect.y + rect.h / 2);
    ctx.stroke();
    ctx.restore();
  }

  private drawWaveLine(
    ctx: CanvasRenderingContext2D,
    samples: Float32Array,
    rect: { x: number; y: number; w: number; h: number },
    _now: number,
  ): void {
    if (samples.length < 2) return;

    let peak = 1;
    for (let index = 0; index < samples.length; index += 1) {
      peak = Math.max(peak, Math.abs(samples[index]));
    }

    const scale = (rect.h * 0.43) / Math.max(2200, peak);
    const step = rect.w / (samples.length - 1);
    const color = this.settings.waveColor;
    const alpha = this.waveAlpha * (0.62 + this.settings.intensity * 0.5);

    ctx.save();
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.shadowColor = withAlpha(color, 0.35 * alpha);
    ctx.shadowBlur = 8;
    ctx.strokeStyle = withAlpha(color, alpha);
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let index = 0; index < samples.length; index += 1) {
      const x = rect.x + index * step;
      const y = rect.y + rect.h / 2 - samples[index] * scale;
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.restore();

    ctx.textAlign = 'left';
    ctx.font = `9px ${FONT_MONO}`;
    ctx.fillStyle = withAlpha(color, 0.38 * alpha);
    ctx.fillText(`PEAK ${Math.round(peak)}`, rect.x, rect.y + rect.h + 12);
  }

  private selectTriggeredWindow(source: Float32Array, desired: number): Float32Array {
    const count = Math.min(desired, source.length);
    if (count < 32) return source.slice(-count);

    const searchStart = Math.max(0, source.length - count - Math.min(640, source.length - count));
    const threshold = Math.max(512, peakOf(source, searchStart, source.length) * 0.035);
    let trigger = -1;
    for (let index = searchStart + 1; index < source.length - 1; index += 1) {
      if (source[index - 1] < -threshold && source[index] >= threshold) {
        trigger = index - 1;
        if (trigger + count <= source.length) break;
      }
    }

    const start = trigger >= 0 && trigger + count <= source.length
      ? trigger
      : Math.max(0, source.length - count);
    return source.slice(start, start + count);
  }

  private waveSubtitle(): string {
    if (this.envelope) {
      return `FPGA MIN/MAX · ${this.envelope.mins.length} GROUPS / ${formatRate(this.sampleRate)} S/s`;
    }
    if (this.source === 'adc') return 'ADC TELEMETRY / NOT AUDIO';
    if (this.source === 'justfloat') return `LEGACY PCM / ${formatRate(this.sampleRate)} S/s / NO FFT`;
    if (this.source === 'framed') return `FPGA FRAME / ${formatRate(this.sampleRate)} S/s`;
    if (this.source === 'demo') return 'DEMO / LOCAL SYNTH';
    return 'NO VALID SOURCE';
  }

  private emptyWaveText(): string {
    if (this.source === 'adc') return 'ADC 遥测不绘制为音频波形';
    if (this.dataState === 'interrupted') return '数据中断 · 等待重新接收';
    if (this.dataState === 'waiting') return '已连接 · 等待 PCM 数据';
    return '等待真实波形数据';
  }

  private drawDemoMark(ctx: CanvasRenderingContext2D, photo: { x: number; y: number; w: number; h: number }): void {
    ctx.save();
    ctx.textAlign = 'right';
    ctx.font = `9px ${FONT_MONO}`;
    ctx.fillStyle = 'rgba(232, 184, 107, 0.72)';
    ctx.fillText('DEMO / NOT HARDWARE DATA', photo.x + photo.w - 24, photo.y + 27);
    ctx.restore();
  }
}

function drawImageCover(
  ctx: CanvasRenderingContext2D,
  image: HTMLImageElement,
  rect: { x: number; y: number; w: number; h: number },
  offset: number,
): void {
  const imageAspect = image.width / image.height;
  const rectAspect = rect.w / rect.h;
  let sx = 0;
  let sy = 0;
  let sw = image.width;
  let sh = image.height;

  if (imageAspect > rectAspect) {
    sw = image.height * rectAspect;
    sx = (image.width - sw) / 2;
  } else {
    sh = image.width / rectAspect;
    sy = (image.height - sh) / 2;
  }
  const maxPanX = Math.max(0, (image.width - sw) / 2);
  const maxPanY = Math.max(0, (image.height - sh) / 2);
  sx = Math.max(0, Math.min(image.width - sw, sx + Math.max(-1, Math.min(1, offset)) * maxPanX));
  sy = Math.max(0, Math.min(image.height - sh, sy + Math.max(-1, Math.min(1, offset)) * maxPanY));
  ctx.drawImage(image, sx, sy, sw, sh, rect.x, rect.y, rect.w, rect.h);
}

function roundedRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  radius: number,
): void {
  const r = Math.min(radius, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function withAlpha(hex: string, alpha: number): string {
  const clean = hex.replace('#', '');
  const normalized = clean.length === 3
    ? clean.split('').map((char) => char + char).join('')
    : clean;
  const value = Number.parseInt(normalized, 16);
  if (Number.isNaN(value)) return `rgba(70, 215, 232, ${alpha})`;
  const r = (value >> 16) & 255;
  const g = (value >> 8) & 255;
  const b = value & 255;
  return `rgba(${r}, ${g}, ${b}, ${Math.max(0, Math.min(1, alpha))})`;
}

function formatRate(rate: number): string {
  if (!Number.isFinite(rate) || rate <= 0) return '--';
  return rate >= 1000 ? `${rate.toFixed(1)}` : `${rate.toFixed(0)}`;
}

function peakOf(data: Float32Array, start: number, end: number): number {
  let peak = 1;
  for (let index = start; index < end; index += 1) peak = Math.max(peak, Math.abs(data[index]));
  return peak;
}
