export type SerialState =
  | 'unsupported'
  | 'insecure'
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'closing';

export interface SerialCallbacks {
  onData: (chunk: Uint8Array) => void;
  onState: (state: SerialState) => void;
  onError: (message: string) => void;
  onDisconnect: (message: string) => void;
}

export class SerialManager {
  private port: SerialPort | null = null;
  private reader: ReadableStreamDefaultReader<Uint8Array> | null = null;
  private readTask: Promise<void> | null = null;
  private stopRequested = false;
  private readonly disconnectHandler = (event: Event) => {
    if (event.target === this.port) {
      this.stopRequested = true;
      this.callbacks.onDisconnect('设备已拔出或串口已断开');
    }
  };

  constructor(private readonly callbacks: SerialCallbacks) {}

  get supported(): boolean {
    return typeof navigator !== 'undefined' && 'serial' in navigator;
  }

  get secure(): boolean {
    return window.isSecureContext;
  }

  isConnected(): boolean {
    return this.port !== null;
  }

  async connect(baudRate: number): Promise<void> {
    if (!this.supported) throw new Error('当前浏览器不支持 Web Serial，请使用 Windows Chrome 或 Edge。');
    if (!this.secure) throw new Error('Web Serial 需要安全上下文，请通过 http://localhost 或 https:// 打开。');
    if (!Number.isInteger(baudRate) || baudRate < 1200 || baudRate > 4_000_000) {
      throw new Error('波特率不合法。');
    }

    await this.disconnect();
    this.callbacks.onState('connecting');

    let port: SerialPort | null = null;
    try {
      port = await navigator.serial.requestPort();
      await port.open({
        baudRate,
        dataBits: 8,
        stopBits: 1,
        parity: 'none',
        flowControl: 'none',
        bufferSize: 64 * 1024,
      });
    } catch (error) {
      if (port) {
        try {
          await port.close();
        } catch {
          // Ignore close failure after a rejected open.
        }
      }
      this.callbacks.onState('disconnected');
      throw new Error(this.friendlyError(error));
    }

    this.port = port;
    this.stopRequested = false;
    this.callbacks.onState('connected');
    navigator.serial.addEventListener('disconnect', this.disconnectHandler);
    this.readTask = this.readLoop(port);
  }

  async disconnect(): Promise<void> {
    this.stopRequested = true;
    this.callbacks.onState('closing');

    if (this.reader) {
      try {
        await this.reader.cancel();
      } catch {
        // Reader may already be closed by the browser.
      }
    }

    if (this.readTask) {
      try {
        await this.readTask;
      } catch {
        // The read loop reports errors through callbacks.
      }
    }
    this.readTask = null;
    this.reader = null;

    if (this.port) {
      try {
        await this.port.close();
      } catch {
        // Port may already be closed after a physical disconnect.
      }
      navigator.serial.removeEventListener('disconnect', this.disconnectHandler);
      this.port = null;
    }

    this.callbacks.onState('disconnected');
  }

  private async readLoop(port: SerialPort): Promise<void> {
    try {
      while (!this.stopRequested && port.readable) {
        const reader = port.readable.getReader();
        this.reader = reader;
        try {
          while (!this.stopRequested) {
            const { value, done } = await reader.read();
            if (done) break;
            if (value && value.byteLength > 0) this.callbacks.onData(value);
          }
        } finally {
          reader.releaseLock();
          if (this.reader === reader) this.reader = null;
        }
      }
    } catch (error) {
      if (!this.stopRequested) {
        this.callbacks.onError(this.friendlyError(error));
      }
    } finally {
      if (!this.stopRequested) {
        this.stopRequested = true;
        this.callbacks.onDisconnect('串口读取循环已结束');
      }
    }
  }

  private friendlyError(error: unknown): string {
    const message = error instanceof Error ? error.message : String(error);
    const lower = message.toLowerCase();

    if (lower.includes('no port selected') || lower.includes('not found')) {
      return '未选择串口设备。';
    }
    if (lower.includes('access denied') || lower.includes('failed to open')) {
      return '串口打开失败。请关闭 VOFA+、Arduino 串口监视器或其他占用该 COM 口的软件后重试。';
    }
    if (lower.includes('networkerror') || lower.includes('device has been lost')) {
      return '设备已断开或串口不可用，请检查 USB 调试口和 FTDI 驱动。';
    }
    if (lower.includes('security') || lower.includes('permission')) {
      return '浏览器阻止了串口访问，请通过用户点击重新授权。';
    }
    return `串口错误：${message}`;
  }
}
