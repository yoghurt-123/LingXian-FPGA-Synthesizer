export class RawPreview {
  private readonly buffer: Uint8Array;
  private writeIndex = 0;
  private filled = 0;
  private totalBytes = 0;
  private message = '';

  constructor(
    private readonly preview: HTMLPreElement,
    private readonly meta: HTMLElement,
    private readonly capacity = 2048,
  ) {
    this.buffer = new Uint8Array(capacity);
    this.render();
  }

  clear(message = '等待串口原始字节…'): void {
    this.writeIndex = 0;
    this.filled = 0;
    this.totalBytes = 0;
    this.message = message;
    this.render();
  }

  append(chunk: Uint8Array): void {
    this.totalBytes += chunk.length;
    for (const byte of chunk) {
      this.buffer[this.writeIndex] = byte;
      this.writeIndex = (this.writeIndex + 1) % this.capacity;
      if (this.filled < this.capacity) this.filled += 1;
    }
  }

  setMessage(message: string): void {
    this.message = message;
    this.render();
  }

  render(): void {
    if (this.filled === 0) {
      this.preview.textContent = this.message || '等待串口原始字节…';
      this.meta.textContent = '0 B';
      return;
    }

    const bytes = new Uint8Array(this.filled);
    const start = (this.writeIndex - this.filled + this.capacity) % this.capacity;
    for (let index = 0; index < this.filled; index += 1) {
      bytes[index] = this.buffer[(start + index) % this.capacity];
    }

    const show = Math.min(bytes.length, this.capacity);
    const firstAbsolute = this.totalBytes - bytes.length;
    const lines: string[] = [];
    const base = Math.max(0, bytes.length - show);
    for (let offset = 0; offset < show; offset += 16) {
      const slice = bytes.subarray(base + offset, base + offset + 16);
      const address = (firstAbsolute + base + offset)
        .toString(16)
        .toUpperCase()
        .padStart(8, '0');
      const hex = Array.from(slice, (byte) => byte.toString(16).toUpperCase().padStart(2, '0')).join(' ');
      const ascii = Array.from(slice, (byte) => (byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.')).join('');
      lines.push(`${address}  ${hex.padEnd(47, ' ')}  ${ascii}`);
    }
    this.preview.textContent = lines.join('\n');
    this.meta.textContent = `${this.totalBytes} B · 最近 ${show} B`;
  }
}
