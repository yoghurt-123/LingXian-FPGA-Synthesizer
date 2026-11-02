export interface DemoHandlers {
  onWave: (samples: Float32Array, sampleRate: number) => void;
  onSpectrum: (values: Uint8Array, sampleRate: number) => void;
}

export class DemoSource {
  private timer = 0;
  private phase = 0;
  private beat = 0;

  constructor(private readonly handlers: DemoHandlers) {}

  start(): void {
    this.stop();
    this.timer = window.setInterval(() => this.tick(), 33);
  }

  stop(): void {
    if (this.timer) window.clearInterval(this.timer);
    this.timer = 0;
  }

  private tick(): void {
    const sampleRate = 48_000;
    const count = 512;
    const samples = new Float32Array(count);
    const waveA = 0.38;
    const waveB = 0.14;
    const drift = 1 + Math.sin(this.beat * 0.0007) * 0.016;

    for (let index = 0; index < count; index += 1) {
      this.phase += (2 * Math.PI * 220 * drift) / sampleRate;
      samples[index] =
        Math.sin(this.phase) * waveA * 32768 +
        Math.sin(this.phase * 2.01) * waveB * 32768 +
        Math.sin(this.phase * 0.501) * 0.035 * 32768;
    }

    this.beat += 33;
    this.handlers.onWave(samples, sampleRate);

    const bands = new Uint8Array(40);
    for (let index = 0; index < bands.length; index += 1) {
      const center = Math.exp(-Math.pow((index - 7) / 8, 2)) * 0.82;
      const living = 0.5 + 0.5 * Math.sin(this.beat * 0.0016 + index * 0.43);
      const upper = Math.exp(-Math.pow((index - 23) / 9, 2)) * 0.35;
      bands[index] = Math.min(255, Math.round((center * living + upper) * 255));
    }
    this.handlers.onSpectrum(bands, sampleRate);
  }
}
