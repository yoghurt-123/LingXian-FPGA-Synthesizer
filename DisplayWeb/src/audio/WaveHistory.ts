export class WaveHistory {
  private readonly data: Float32Array;
  private writeIndex = 0;
  private filled = 0;

  constructor(private readonly capacity = 8192) {
    this.data = new Float32Array(capacity);
  }

  append(samples: Float32Array): void {
    if (samples.length === 0) return;
    if (samples.length >= this.capacity) {
      this.data.set(samples.subarray(samples.length - this.capacity));
      this.writeIndex = 0;
      this.filled = this.capacity;
      return;
    }

    for (let index = 0; index < samples.length; index += 1) {
      this.data[this.writeIndex] = samples[index];
      this.writeIndex = (this.writeIndex + 1) % this.capacity;
      if (this.filled < this.capacity) this.filled += 1;
    }
  }

  get length(): number {
    return this.filled;
  }

  clear(): void {
    this.data.fill(0);
    this.writeIndex = 0;
    this.filled = 0;
  }

  latest(count: number): Float32Array {
    const size = Math.min(count, this.filled);
    const result = new Float32Array(size);
    if (size === 0) return result;
    let readIndex = (this.writeIndex - size + this.capacity) % this.capacity;
    for (let index = 0; index < size; index += 1) {
      result[index] = this.data[readIndex];
      readIndex = (readIndex + 1) % this.capacity;
    }
    return result;
  }
}
