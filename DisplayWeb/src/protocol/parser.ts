import type {
  AdcSnapshot,
  ParseErrorDetail,
  ParserEvents,
  ParserMode,
  ParserStats,
  SpectrumBatch,
  WaveBatch,
  WaveEnvelopeBatch,
} from '../types';

const MAGIC_0 = 0xa5;
const MAGIC_1 = 0x5a;
const HEADER_LEN = 20;
const MAX_WAVE_POINTS = 1024;
const MAX_BANDS = 64;
const MAX_PAYLOAD = MAX_WAVE_POINTS * 2 + MAX_BANDS;
const BUFFER_SIZE = 256 * 1024;
const JUSTFLOAT_RATE = 6031.71;
const TRAILER = [0x00, 0x00, 0x80, 0x7f];
const TEXT_LIMIT = 512 * 1024;
const ENVELOPE_WAVE_COUNT = 256;
const ENVELOPE_BAND_COUNT = 16;

export class StreamParser {
  private readonly buffer = new Uint8Array(BUFFER_SIZE);
  private start = 0;
  private end = 0;
  private mode: ParserMode = 'unknown';
  private textBuffer = '';
  private lastErrorEmit = 0;
  private decoder = new TextDecoder();

  private stats: ParserStats = {
    bytes: 0,
    validFrames: 0,
    errors: 0,
    lastError: '',
    lastErrorDetail: null,
    lastValidAt: 0,
    mode: 'unknown',
  };

  constructor(private readonly events: ParserEvents = {}) {}

  getStats(): ParserStats {
    return { ...this.stats, lastErrorDetail: this.stats.lastErrorDetail };
  }

  reset(): void {
    this.start = 0;
    this.end = 0;
    this.textBuffer = '';
    this.mode = 'unknown';
    this.stats = {
      bytes: 0,
      validFrames: 0,
      errors: 0,
      lastError: '',
      lastErrorDetail: null,
      lastValidAt: 0,
      mode: 'unknown',
    };
  }

  feed(chunk: Uint8Array): void {
    if (chunk.length === 0) return;
    this.stats.bytes += chunk.length;
    this.makeRoom(chunk.length);
    this.buffer.set(chunk, this.end);
    this.end += chunk.length;

    if (this.mode === 'adc') {
      this.drainText();
      return;
    }

    let guard = 0;
    while (guard++ < 64) {
      if (this.mode === 'unknown' && !this.detectMode()) return;
      const active = this.mode as ParserMode;
      if (active === 'adc') {
        this.drainText();
        return;
      }
      if (active === 'justfloat') {
        if (!this.parseJustFloat()) break;
      } else if (active === 'framed') {
        if (!this.parseFramed()) break;
      } else {
        break;
      }
    }
  }

  private makeRoom(incoming: number): void {
    if (incoming > this.buffer.length) {
      this.start = this.end = 0;
      this.recordError('BUFFER_OVERFLOW', '单次读取超过接收缓冲区上限');
      return;
    }
    if (this.end + incoming <= this.buffer.length) {
      if (this.start > 0 && this.start > 64 * 1024) this.compact();
      return;
    }
    this.compact();
    if (this.end + incoming <= this.buffer.length) return;

    const keep = Math.max(0, this.buffer.length - incoming);
    if (keep > 0) {
      this.buffer.copyWithin(0, this.end - keep, this.end);
      this.start = 0;
      this.end = keep;
    } else {
      this.start = this.end = 0;
    }
    this.recordError('BUFFER_OVERFLOW', '接收缓冲区溢出，已丢弃最旧字节');
  }

  private compact(): void {
    if (this.start === 0) return;
    const length = this.end - this.start;
    if (length > 0) this.buffer.copyWithin(0, this.start, this.end);
    this.start = 0;
    this.end = length;
  }

  private available(): number {
    return this.end - this.start;
  }

  private streamOffset(): number {
    return Math.max(0, this.stats.bytes - this.available());
  }

  private u8(offset: number): number {
    return this.buffer[this.start + offset];
  }

  private u16(offset: number): number {
    return this.u8(offset) | (this.u8(offset + 1) << 8);
  }

  private u32(offset: number): number {
    return (this.u8(offset) |
      (this.u8(offset + 1) << 8) |
      (this.u8(offset + 2) << 16) |
      (this.u8(offset + 3) << 24)) >>> 0;
  }

  private i16(offset: number): number {
    const value = this.u16(offset);
    return value & 0x8000 ? value - 0x10000 : value;
  }

  private f32(offset: number): number {
    const view = new DataView(
      this.buffer.buffer,
      this.buffer.byteOffset + this.start + offset,
      4,
    );
    return view.getFloat32(0, true);
  }

  private consume(count: number): void {
    this.start += Math.min(count, this.available());
  }

  private setMode(mode: ParserMode, detail: string): void {
    if (this.mode === mode) return;
    this.mode = mode;
    this.stats.mode = mode;
    this.events.onMode?.(mode, detail);
  }

  private detectMode(): boolean {
    const available = this.available();
    if (available < 1) return false;
    const previewLength = Math.min(available, 320);
    const preview = this.decoder.decode(
      this.buffer.subarray(this.start, this.start + previewLength),
    );

    if (this.u8(0) === MAGIC_0 && available >= 2 && this.u8(1) === MAGIC_1) {
      this.setMode('framed', '检测到 FPGA 帧协议 A5 5A');
      return true;
    }
    if (/adc:|ADC_TEST|ADC_ERR|ADC_TEST_START/.test(preview)) {
      this.setMode('adc', '检测到 ADC 遥测文本');
      return true;
    }
    if (available >= 8) {
      const scanLimit = Math.min(available - 8, 48);
      for (let offset = 0; offset <= scanLimit; offset += 1) {
        if (this.isTrailerAt(offset + 4)) {
          if (offset > 0) this.consume(offset);
          this.setMode('justfloat', '检测到 VOFA JustFloat 8 字节 PCM 帧');
          return true;
        }
      }
    }
    for (let offset = 1; offset < Math.min(available - 1, 256); offset += 1) {
      if (this.u8(offset) === MAGIC_0 && this.u8(offset + 1) === MAGIC_1) {
        this.consume(offset);
        this.setMode('framed', '重新同步到 FPGA 帧协议');
        return true;
      }
    }
    if (available > 4096) {
      this.consume(available - 4096);
      this.recordError('UNKNOWN_FORMAT', '未识别的数据格式，保留最近 4 KiB 等待协议');
    }
    return false;
  }

  private isTrailerAt(offset: number): boolean {
    if (offset + 4 > this.available()) return false;
    return (
      this.u8(offset) === TRAILER[0] &&
      this.u8(offset + 1) === TRAILER[1] &&
      this.u8(offset + 2) === TRAILER[2] &&
      this.u8(offset + 3) === TRAILER[3]
    );
  }

  private parseJustFloat(): boolean {
    const samples: number[] = [];
    let progress = false;

    while (this.available() >= 8) {
      if (!this.isTrailerAt(4)) {
        let found = -1;
        const limit = Math.min(this.available() - 8, 1024);
        for (let offset = 1; offset <= limit; offset += 1) {
          if (this.isTrailerAt(offset + 4)) {
            found = offset;
            break;
          }
        }
        if (found < 0) {
          const drop = Math.max(0, this.available() - 7);
          if (drop > 0) this.consume(drop);
          this.recordError('JUSTFLOAT_TRAILER', 'JustFloat 帧尾丢失，正在重新同步');
          return progress;
        }
        this.consume(found);
        this.recordError('JUSTFLOAT_RESYNC', 'JustFloat 丢弃错位字节');
        progress = true;
      }

      if (this.available() < 8) return progress;
      const sample = this.f32(0);
      if (!Number.isFinite(sample) || Math.abs(sample) > 200000) {
        this.consume(1);
        this.recordError('JUSTFLOAT_VALUE', 'JustFloat PCM 数值非法');
        progress = true;
        continue;
      }

      samples.push(sample);
      this.consume(8);
      this.stats.validFrames += 1;
      this.stats.lastValidAt = performance.now();
      progress = true;

      if (samples.length >= 256) {
        this.emitJustFloat(samples);
        samples.length = 0;
      }
    }

    if (samples.length > 0) this.emitJustFloat(samples);
    return progress;
  }

  private emitJustFloat(samples: number[]): void {
    const batch: WaveBatch = {
      samples: Float32Array.from(samples),
      sampleRate: JUSTFLOAT_RATE,
      source: 'justfloat',
      receivedAt: performance.now(),
    };
    this.events.onWave?.(batch);
  }

  private parseFramed(): boolean {
    if (this.available() < 2) return false;
    const frameOffset = this.streamOffset();

    if (this.u8(0) !== MAGIC_0 || this.u8(1) !== MAGIC_1) {
      let found = -1;
      const limit = Math.min(this.available() - 1, 1024);
      for (let offset = 1; offset < limit; offset += 1) {
        if (this.u8(offset) === MAGIC_0 && this.u8(offset + 1) === MAGIC_1) {
          found = offset;
          break;
        }
      }
      if (found < 0) {
        this.consume(Math.max(0, this.available() - 1));
        this.recordError(
          'FRAME_HEADER_LOST',
          '帧协议头丢失，正在重新同步',
          { streamOffset: frameOffset },
        );
        return false;
      }
      this.consume(found);
      this.recordError(
        'FRAME_RESYNC',
        '丢弃帧协议前导字节',
        { streamOffset: frameOffset, actual: `${found} bytes` },
      );
      return true;
    }

    if (this.available() < HEADER_LEN) return false;

    const version = this.u8(2);
    const type = this.u8(3);
    const sequence = this.u16(4);
    const sampleRate = this.u32(6);
    const waveCount = this.u16(10);
    const bandCount = this.u16(12);
    const payloadLength = this.u16(14);
    const flags = this.u8(16);
    const expectedPayload = waveCount * 2 + bandCount;
    const isEnvelope = type === 2 &&
      waveCount === ENVELOPE_WAVE_COUNT &&
      bandCount === ENVELOPE_BAND_COUNT;

    if (version !== 1) {
      this.rejectFramedHeader(frameOffset, 'FRAME_VERSION', '不支持的帧版本', {
        expected: 'version 1',
        actual: `version ${version}`,
        waveCount,
        bandCount,
      });
      return true;
    }
    if (type !== 1 && type !== 2) {
      this.rejectFramedHeader(frameOffset, 'FRAME_TYPE', '不支持的帧类型', {
        expected: 'type 1 or 2',
        actual: `type ${type}`,
        waveCount,
        bandCount,
      });
      return true;
    }
    if (
      waveCount > MAX_WAVE_POINTS ||
      bandCount > MAX_BANDS ||
      payloadLength !== expectedPayload ||
      payloadLength > MAX_PAYLOAD ||
      sampleRate === 0
    ) {
      this.rejectFramedHeader(frameOffset, 'FRAME_HEADER', '帧头长度/采样率校验失败', {
        expected: `payload ${expectedPayload}, sample_rate > 0`,
        actual: `payload ${payloadLength}, sample_rate ${sampleRate}, wave ${waveCount}, band ${bandCount}`,
        waveCount,
        bandCount,
      });
      return true;
    }
    if (type === 2 && (waveCount & 1) !== 0) {
      this.rejectFramedHeader(frameOffset, 'FRAME_LAYOUT', 'type 2 波形点数为奇数，无法按 min/max 组解析', {
        expected: 'even wave_count',
        actual: `wave_count ${waveCount}`,
        waveCount,
        bandCount,
      });
      return true;
    }

    const frameLength = HEADER_LEN + payloadLength + 2;
    if (this.available() < frameLength) return false;

    const expectedCrc = this.u16(HEADER_LEN + payloadLength);
    const actualCrc = crc16(this.buffer, this.start, this.start + HEADER_LEN + payloadLength);
    if (expectedCrc !== actualCrc) {
      this.consume(frameLength);
      this.recordError('CRC_MISMATCH', 'CRC16 校验失败，整帧已丢弃', {
        streamOffset: frameOffset,
        expected: `0x${expectedCrc.toString(16).padStart(4, '0')}`,
        actual: `0x${actualCrc.toString(16).padStart(4, '0')}`,
        frameLength,
        waveCount,
        bandCount,
        crcExpected: expectedCrc,
        crcActual: actualCrc,
      });
      return true;
    }

    if (isEnvelope) {
      const groups = waveCount / 2;
      const mins = new Float32Array(groups);
      const maxs = new Float32Array(groups);
      let orderError = '';
      for (let index = 0; index < groups; index += 1) {
        const min = this.i16(HEADER_LEN + index * 4);
        const max = this.i16(HEADER_LEN + index * 4 + 2);
        mins[index] = min;
        maxs[index] = max;
        if (min > max && !orderError) {
          orderError = `group ${index}: min ${min} > max ${max}`;
        }
      }
      if (orderError) {
        this.consume(frameLength);
        this.stats.validFrames += 1;
        this.stats.lastValidAt = performance.now();
        this.recordError('MINMAX_ORDER', `min/max 顺序错误：${orderError}`, {
          streamOffset: frameOffset,
          frameLength,
          waveCount,
          bandCount,
        });
        return true;
      }

      const envelope: WaveEnvelopeBatch = {
        mins,
        maxs,
        sampleRate,
        source: 'framed',
        sequence,
        receivedAt: performance.now(),
        groupSize: 4,
      };
      this.events.onEnvelope?.(envelope);
    } else if (waveCount > 0) {
      const samples = new Float32Array(waveCount);
      for (let index = 0; index < waveCount; index += 1) {
        samples[index] = this.i16(HEADER_LEN + index * 2);
      }
      const batch: WaveBatch = {
        samples,
        sampleRate,
        source: 'framed',
        sequence,
        receivedAt: performance.now(),
      };
      this.events.onWave?.(batch);
    }

    if (bandCount > 0) {
      const values = new Uint8Array(bandCount);
      const spectrumOffset = HEADER_LEN + waveCount * 2;
      for (let index = 0; index < bandCount; index += 1) {
        values[index] = this.u8(spectrumOffset + index);
      }
      const spectrum: SpectrumBatch = {
        values,
        sampleRate,
        source: 'framed',
        sequence,
        receivedAt: performance.now(),
      };
      this.events.onSpectrum?.(spectrum);
    }

    this.stats.validFrames += 1;
    this.stats.lastValidAt = performance.now();
    this.consume(frameLength);
    return true;
  }

  private rejectFramedHeader(
    streamOffset: number,
    code: string,
    message: string,
    details: Partial<ParseErrorDetail>,
  ): void {
    this.consume(2);
    this.recordError(code, message, { streamOffset, ...details });
  }

  private drainText(): void {
    if (this.available() > 0) {
      const text = this.decoder.decode(this.buffer.subarray(this.start, this.end));
      this.textBuffer += text;
      this.start = this.end;
      if (this.textBuffer.length > TEXT_LIMIT) {
        this.textBuffer = this.textBuffer.slice(-8192);
        this.recordError('TEXT_OVERFLOW', 'ADC 文本缓冲过长，已截断');
      }
    }

    let lineEnd = this.textBuffer.indexOf('\n');
    while (lineEnd >= 0) {
      const line = this.textBuffer.slice(0, lineEnd).replace(/\r$/, '');
      this.textBuffer = this.textBuffer.slice(lineEnd + 1);
      this.processTextLine(line);
      lineEnd = this.textBuffer.indexOf('\n');
    }
  }

  private processTextLine(line: string): void {
    if (!line) return;
    const adcMatch = /^adc:(-?\d+),(-?\d+),(-?\d+),(-?\d+)\s*$/.exec(line);
    if (adcMatch) {
      const snapshot: AdcSnapshot = {
        values: adcMatch.slice(1).map((value) => Number(value)),
        line,
        receivedAt: performance.now(),
      };
      this.stats.validFrames += 1;
      this.stats.lastValidAt = performance.now();
      this.events.onAdc?.(snapshot);
      return;
    }
    if (/^ADC_TEST_ALIVE\b/.test(line) || /^ADC_TEST_START\b/.test(line)) {
      this.stats.lastValidAt = performance.now();
      this.events.onInfo?.(line);
      return;
    }
    if (/^ADC_ERR\b/.test(line)) {
      this.stats.errors += 1;
      this.stats.lastError = line;
      this.stats.lastErrorDetail = {
        code: 'ADC_ERROR',
        message: line,
        streamOffset: this.streamOffset(),
      };
      this.events.onError?.(line);
      this.events.onParseError?.(this.stats.lastErrorDetail);
    }
  }

  private recordError(
    code: string,
    message: string,
    details: Partial<ParseErrorDetail> = {},
  ): void {
    this.stats.errors += 1;
    this.stats.lastError = message;
    const detail: ParseErrorDetail = {
      code,
      message,
      streamOffset: details.streamOffset ?? this.streamOffset(),
      ...details,
    };
    this.stats.lastErrorDetail = detail;
    const now = performance.now();
    if (this.lastErrorEmit === 0 || now - this.lastErrorEmit > 250) {
      this.lastErrorEmit = now;
      this.events.onError?.(message);
      this.events.onParseError?.(detail);
    }
  }
}

function crc16(data: Uint8Array, start: number, end: number): number {
  let crc = 0xffff;
  for (let index = start; index < end; index += 1) {
    crc ^= data[index] << 8;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc & 0xffff;
}
