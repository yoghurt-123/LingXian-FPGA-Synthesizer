export type SpectrumColumnCount = 32 | 64 | 96;

export interface SpectrumDisplaySettings {
  columns: SpectrumColumnCount;
  gain: number;
  intensity: number;
}

interface ColorStop {
  at: number;
  color: [number, number, number];
}

const RAINBOW: ColorStop[] = [
  { at: 0.0, color: [255, 62, 48] },
  { at: 0.16, color: [255, 132, 20] },
  { at: 0.33, color: [255, 210, 24] },
  { at: 0.50, color: [60, 202, 106] },
  { at: 0.66, color: [48, 211, 226] },
  { at: 0.82, color: [56, 112, 241] },
  { at: 1.0, color: [166, 84, 244] },
];

export class SpectrumDisplay {
  private source: Float32Array = new Float32Array(0);
  private previousSource: Float32Array = new Float32Array(0);
  private targetLevel: Float32Array = new Float32Array(0);
  private displayLevel: Float32Array = new Float32Array(0);
  private peakLevel: Float32Array = new Float32Array(0);
  private transientTarget: Float32Array = new Float32Array(0);
  private transientLevel: Float32Array = new Float32Array(0);
  private columns: SpectrumColumnCount = 64;
  private lastUpdate = 0;

  setColumns(columns: SpectrumColumnCount): void {
    this.columns = columns;
  }

  reset(): void {
    this.source = new Float32Array(0);
    this.previousSource = new Float32Array(0);
    this.targetLevel = new Float32Array(0);
    this.displayLevel = new Float32Array(0);
    this.peakLevel = new Float32Array(0);
    this.transientTarget = new Float32Array(0);
    this.transientLevel = new Float32Array(0);
    this.lastUpdate = 0;
  }

  setValues(values: Uint8Array): void {
    if (values.length === 0) return;
    const source = new Float32Array(values.length);
    for (let index = 0; index < values.length; index += 1) {
      const normalized = Math.max(0, Math.min(255, values[index])) / 255;
      source[index] = normalized <= 0.018 ? 0 : normalized;
    }

    const firstFrame = this.displayLevel.length !== source.length;
    if (firstFrame) {
      this.source = source;
      this.previousSource = new Float32Array(source.length);
      this.targetLevel = new Float32Array(source.length);
      this.displayLevel = new Float32Array(source.length);
      this.peakLevel = new Float32Array(source.length);
      this.transientTarget = new Float32Array(source.length);
      this.transientLevel = new Float32Array(source.length);
    } else {
      this.previousSource = this.source;
      this.source = source;
    }

    for (let index = 0; index < source.length; index += 1) {
      const value = this.source[index];
      const shaped = Math.pow(value, 0.72) * this.currentGain();
      this.targetLevel[index] = Math.min(1, Math.tanh(shaped * 1.15) / Math.tanh(1.15));
      const delta = firstFrame ? 0 : Math.max(0, value - (this.previousSource[index] ?? 0));
      const lowWeight = index <= 3 ? 1.35 : 1;
      const highWeight = index >= Math.max(0, source.length - 4) ? 1.25 : 1;
      const midWeight = index >= 4 && index <= Math.floor(source.length * 0.7) ? 1.08 : 1;
      const transient = Math.min(1, Math.pow(delta, 0.62) * 2.4 * lowWeight * highWeight * midWeight);
      this.transientTarget[index] = transient;
    }
  }

  setSettings(settings: SpectrumDisplaySettings): void {
    this.columns = settings.columns;
    this.gainSetting = settings.gain;
    this.intensitySetting = settings.intensity;
  }

  draw(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
    now: number,
  ): void {
    const sourceCount = this.source.length;
    if (sourceCount === 0 || this.displayLevel.length === 0) {
      this.drawWaiting(ctx, rect);
      return;
    }

    const dt = this.lastUpdate === 0 ? 1 / 60 : Math.min(0.1, (now - this.lastUpdate) / 1000);
    this.lastUpdate = now;
    this.updateLevels(dt);

    const count = this.columns;
    const gap = count >= 80 ? 1.2 : 1.8;
    const barWidth = Math.max(1, (rect.w - gap * (count - 1)) / count);
    const alpha = 0.55 + this.intensitySetting * 0.55;

    ctx.save();
    ctx.shadowColor = `rgba(255, 255, 255, ${0.10 * alpha})`;
    ctx.shadowBlur = 7;
    for (let index = 0; index < count; index += 1) {
      const t = index / (count - 1);
      const value = this.interpolate(this.displayLevel, t);
      const transient = this.interpolate(this.transientLevel, t);
      const height = Math.min(1, value + transient * 0.34);
      const barHeight = Math.max(1.5, height * rect.h);
      const x = rect.x + index * (barWidth + gap);
      const y = rect.y + rect.h - barHeight;
      const color = rainbow(t);
      ctx.fillStyle = `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${0.78 * alpha})`;
      roundedBar(ctx, x, y, barWidth, barHeight);
      ctx.fill();

      const peak = this.interpolate(this.peakLevel, t);
      const peakY = rect.y + rect.h - Math.max(1.5, peak * rect.h);
      ctx.fillStyle = `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${0.95 * alpha})`;
      roundedBar(ctx, x, peakY - 1.2, barWidth, 2.2);
      ctx.fill();
    }
    ctx.restore();

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.10)';
    ctx.beginPath();
    ctx.moveTo(rect.x, rect.y + rect.h);
    ctx.lineTo(rect.x + rect.w, rect.y + rect.h);
    ctx.stroke();
  }

  get realBandCount(): number {
    return this.source.length;
  }

  get displayedColumnCount(): number {
    return this.columns;
  }

  private gainSetting = 1.25;
  private intensitySetting = 0.78;

  private currentGain(): number {
    return this.gainSetting;
  }

  private updateLevels(dt: number): void {
    const sourceCount = this.source.length;
    const attack = 1 - Math.exp(-dt / 0.03);
    const release = 1 - Math.exp(-dt / 0.24);
    const peakRelease = Math.max(0, dt / 0.42);

    for (let index = 0; index < sourceCount; index += 1) {
      const target = this.targetLevel[index];
      const current = this.displayLevel[index];
      const coeff = target > current ? attack : release;
      this.displayLevel[index] = current + (target - current) * Math.min(1, coeff);

      const transientTarget = this.transientTarget[index];
      const transientCurrent = this.transientLevel[index];
      const transientCoeff = transientTarget > transientCurrent ? attack : release;
      this.transientLevel[index] = transientCurrent + (transientTarget - transientCurrent) * Math.min(1, transientCoeff);

      const peakFloor = Math.max(0, this.peakLevel[index] - peakRelease);
      this.peakLevel[index] = Math.max(this.displayLevel[index], peakFloor);
    }
  }

  private interpolate(data: Float32Array, t: number): number {
    if (data.length === 0) return 0;
    if (data.length === 1) return data[0];
    const position = t * (data.length - 1);
    const low = Math.floor(position);
    const high = Math.min(data.length - 1, low + 1);
    const fraction = position - low;
    return data[low] * (1 - fraction) + data[high] * fraction;
  }

  private drawWaiting(
    ctx: CanvasRenderingContext2D,
    rect: { x: number; y: number; w: number; h: number },
  ): void {
    ctx.save();
    ctx.strokeStyle = 'rgba(230, 238, 243, 0.12)';
    ctx.setLineDash([4, 8]);
    ctx.beginPath();
    ctx.moveTo(rect.x, rect.y + rect.h);
    ctx.lineTo(rect.x + rect.w, rect.y + rect.h);
    ctx.stroke();
    ctx.restore();
  }
}

function rainbow(t: number): [number, number, number] {
  const value = Math.max(0, Math.min(1, t));
  let low = RAINBOW[0];
  let high = RAINBOW[RAINBOW.length - 1];
  for (let index = 1; index < RAINBOW.length; index += 1) {
    if (value <= RAINBOW[index].at) {
      low = RAINBOW[index - 1];
      high = RAINBOW[index];
      break;
    }
  }
  const span = Math.max(0.0001, high.at - low.at);
  const fraction = Math.max(0, Math.min(1, (value - low.at) / span));
  return [
    Math.round(low.color[0] + (high.color[0] - low.color[0]) * fraction),
    Math.round(low.color[1] + (high.color[1] - low.color[1]) * fraction),
    Math.round(low.color[2] + (high.color[2] - low.color[2]) * fraction),
  ];
}

function roundedBar(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
): void {
  const radius = Math.min(width / 2, 2.5);
  const r = Math.min(radius, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + width, y, x + width, y + height, r);
  ctx.arcTo(x + width, y + height, x, y + height, r);
  ctx.arcTo(x, y + height, x, y, r);
  ctx.arcTo(x, y, x + width, y, r);
  ctx.closePath();
}
