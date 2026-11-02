export interface PhotoItem {
  image: HTMLImageElement;
  objectUrl?: string;
  name: string;
}

export interface PhotoFrame {
  current: PhotoItem | null;
  previous: PhotoItem | null;
  fade: number;
  progress: number;
  index: number;
  count: number;
}

export const DEFAULT_PHOTO_SET_VERSION = '20261031-v1';

const DEFAULT_PHOTOS = [
  { src: './photos/default-20261031-01.jpg', name: '默认 / 01' },
  { src: './photos/default-20261031-02.jpg', name: '默认 / 02' },
  { src: './photos/default-20261031-03.jpg', name: '默认 / 03' },
  { src: './photos/default-20261031-04.jpg', name: '默认 / 04' },
  { src: './photos/default-20261031-05.jpg', name: '默认 / 05' },
  { src: './photos/default-20261031-06.jpg', name: '默认 / 06' },
  { src: './photos/default-20261031-07.jpg', name: '默认 / 07' },
  { src: './photos/default-20261031-08.jpg', name: '默认 / 08' },
];

export class PhotoDeck {
  private items: PhotoItem[] = [];
  private index = 0;
  private previousIndex = -1;
  private lastSwitch = performance.now();
  private transitionStart = 0;
  private intervalMs = 10_000;
  private readonly maxItems = 24;

  async loadDefaults(): Promise<void> {
    const loaded = await Promise.all(
      DEFAULT_PHOTOS.map(
        (entry) =>
          new Promise<PhotoItem | null>((resolve) => {
            const image = new Image();
            image.decoding = 'async';
            image.onload = () => resolve({ image, name: entry.name });
            image.onerror = () => resolve(null);
            image.src = entry.src;
          }),
      ),
    );
    this.items = loaded.filter((item): item is PhotoItem => item !== null);
    this.index = 0;
    this.lastSwitch = performance.now();
  }

  async addFiles(files: FileList | File[]): Promise<number> {
    const fileArray = Array.from(files).filter((file) => file.type.startsWith('image/'));
    const added: PhotoItem[] = [];

    for (const file of fileArray) {
      const objectUrl = URL.createObjectURL(file);
      const image = await loadImage(objectUrl);
      if (image) added.push({ image, objectUrl, name: file.name });
      else URL.revokeObjectURL(objectUrl);
    }

    if (added.length === 0) return 0;
    this.items.push(...added);
    while (this.items.length > this.maxItems) {
      const removed = this.items.shift();
      if (removed?.objectUrl) URL.revokeObjectURL(removed.objectUrl);
    }
    if (this.index >= this.items.length) {
      this.index = 0;
      this.previousIndex = -1;
    }
    this.lastSwitch = performance.now();
    this.transitionStart = 0;
    return added.length;
  }

  setInterval(seconds: number): void {
    this.intervalMs = Math.max(4, seconds) * 1000;
  }

  clear(): void {
    for (const item of this.items) {
      if (item.objectUrl) URL.revokeObjectURL(item.objectUrl);
    }
    this.items = [];
    this.index = 0;
    this.previousIndex = -1;
  }

  get count(): number {
    return this.items.length;
  }

  getFrame(now: number): PhotoFrame {
    if (this.items.length > 0 && now - this.lastSwitch >= this.intervalMs) {
      this.previousIndex = this.index;
      this.index = (this.index + 1) % this.items.length;
      this.lastSwitch = now;
      this.transitionStart = now;
    }

    const fadeDuration = 1050;
    const fade = this.transitionStart > 0
      ? Math.min(1, Math.max(0, (now - this.transitionStart) / fadeDuration))
      : 1;
    if (fade >= 1) this.transitionStart = 0;

    return {
      current: this.items[this.index] ?? null,
      previous: this.previousIndex >= 0 ? this.items[this.previousIndex] ?? null : null,
      fade: easeInOut(fade),
      progress: Math.max(0, Math.min(1, (now - this.lastSwitch) / this.intervalMs)),
      index: this.index,
      count: this.items.length,
    };
  }
}

function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const image = new Image();
    image.decoding = 'async';
    image.onload = () => resolve(image);
    image.onerror = () => resolve(null);
    image.src = src;
  });
}

function easeInOut(value: number): number {
  return value < 0.5 ? 2 * value * value : 1 - Math.pow(-2 * value + 2, 2) / 2;
}
