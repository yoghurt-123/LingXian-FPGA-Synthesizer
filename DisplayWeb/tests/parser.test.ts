import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
import { StreamParser } from '../src/protocol/parser';

const usbFrame = new Uint8Array(readFileSync(new URL('./fixtures/usb_frame.bin', import.meta.url)));
const usbView = new DataView(usbFrame.buffer, usbFrame.byteOffset, usbFrame.byteLength);

function justFloat(value: number): Uint8Array {
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setFloat32(0, value, true);
  bytes.set([0x00, 0x00, 0x80, 0x7f], 4);
  return bytes;
}

function crc16(data: Uint8Array): number {
  let crc = 0xffff;
  for (const byte of data) {
    crc ^= byte << 8;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc;
}

function framedFrame(options: {
  wave: number[];
  bands: number[];
  sampleRate?: number;
  sequence?: number;
  corruptCrc?: boolean;
  type?: 1 | 2;
}): Uint8Array {
  const wave = options.wave;
  const bands = options.bands;
  const payloadLength = wave.length * 2 + bands.length;
  const frame = new Uint8Array(20 + payloadLength + 2);
  frame[0] = 0xa5;
  frame[1] = 0x5a;
  frame[2] = 1;
  frame[3] = options.type ?? 2;
  const view = new DataView(frame.buffer);
  view.setUint16(4, options.sequence ?? 7, true);
  view.setUint32(6, options.sampleRate ?? 48_000, true);
  view.setUint16(10, wave.length, true);
  view.setUint16(12, bands.length, true);
  view.setUint16(14, payloadLength, true);
  frame[16] = 1;
  let offset = 20;
  for (const value of wave) {
    view.setInt16(offset, value, true);
    offset += 2;
  }
  for (const value of bands) frame[offset++] = value;
  const crc = crc16(frame.subarray(0, offset));
  view.setUint16(offset, options.corruptCrc ? (crc ^ 0xffff) : crc, true);
  return frame;
}

describe('StreamParser', () => {
  it('parses split JustFloat frames and keeps 6031.71 S/s metadata', () => {
    const waves: Float32Array[] = [];
    const rate: number[] = [];
    const parser = new StreamParser({
      onWave: (batch) => {
        waves.push(batch.samples);
        rate.push(batch.sampleRate);
      },
    });
    const frames = new Uint8Array([...justFloat(1.5), ...justFloat(-2.5)]);
    parser.feed(frames.subarray(0, 3));
    parser.feed(frames.subarray(3, 11));
    parser.feed(frames.subarray(11));
    expect(waves.flatMap((batch) => Array.from(batch))).toEqual([1.5, -2.5]);
    expect(rate[0]).toBeCloseTo(6031.71);
    expect(parser.getStats().validFrames).toBe(2);
  });

  it('parses multiple JustFloat frames in one sticky chunk', () => {
    const samples: number[] = [];
    const parser = new StreamParser({
      onWave: (batch) => samples.push(...Array.from(batch.samples)),
    });
    const frames = new Uint8Array(8 * 20);
    for (let index = 0; index < 20; index += 1) {
      frames.set(justFloat(index), index * 8);
    }
    parser.feed(frames);
    expect(samples).toHaveLength(20);
    expect(samples[19]).toBe(19);
  });

  it('parses ADC text across half lines without touching waveform', () => {
    const adc = vi.fn();
    const wave = vi.fn();
    const parser = new StreamParser({ onAdc: adc, onWave: wave });
    parser.feed(new TextEncoder().encode('adc:12,-34,56'));
    parser.feed(new TextEncoder().encode(',78\r\nADC_TEST_ALIVE seq=00001\n'));
    expect(adc).toHaveBeenCalledTimes(1);
    expect(adc.mock.calls[0][0].values).toEqual([12, -34, 56, 78]);
    expect(wave).not.toHaveBeenCalled();
  });

  it('parses a PCM + spectrum frame split across feeds', () => {
    const wave = vi.fn();
    const spectrum = vi.fn();
    const parser = new StreamParser({ onWave: wave, onSpectrum: spectrum });
    const frame = framedFrame({ wave: [-100, 0, 100, 200], bands: [10, 20, 30], sequence: 9 });
    parser.feed(frame.subarray(0, 13));
    parser.feed(frame.subarray(13, 25));
    parser.feed(frame.subarray(25));
    expect(wave).toHaveBeenCalledTimes(1);
    expect(Array.from(wave.mock.calls[0][0].samples)).toEqual([-100, 0, 100, 200]);
    expect(wave.mock.calls[0][0].sampleRate).toBe(48000);
    expect(spectrum).toHaveBeenCalledTimes(1);
    expect(Array.from(spectrum.mock.calls[0][0].values)).toEqual([10, 20, 30]);
    expect(wave.mock.calls[0][0].sequence).toBe(9);
  });

  it('parses the current USB 128-group min/max frame with 16 bands strictly', () => {
    const envelopes = vi.fn();
    const spectra = vi.fn();
    const errors = vi.fn();
    const parser = new StreamParser({ onEnvelope: envelopes, onSpectrum: spectra, onParseError: errors });
    expect(usbFrame.length).toBe(550);
    expect(usbView.getUint16(548, true)).toBe(0x5f67);
    parser.feed(usbFrame.subarray(0, 275));
    expect(envelopes).not.toHaveBeenCalled();
    parser.feed(usbFrame.subarray(275));
    expect(envelopes).toHaveBeenCalledTimes(1);
    expect(spectra).toHaveBeenCalledTimes(1);
    const envelope = envelopes.mock.calls[0][0];
    expect(envelope.mins.length).toBe(128);
    expect(envelope.maxs.length).toBe(128);
    expect(envelope.sampleRate).toBe(48254);
    expect(envelope.sequence).toBe(1);
    expect(envelope.groupSize).toBe(4);
    expect(envelope.mins[0]).toBe(0);
    expect(envelope.maxs[0]).toBe(11792);
    expect(Array.from(spectra.mock.calls[0][0].values)).toEqual([
      210, 28, 4, 24, 37, 191, 15, 5, 2, 1, 0, 0, 0, 0, 0, 0,
    ]);
    expect(errors).not.toHaveBeenCalled();
  });

  it('rejects the USB frame when one CRC byte is corrupted and reports details', () => {
    const envelopes = vi.fn();
    const parseErrors = vi.fn();
    const parser = new StreamParser({ onEnvelope: envelopes, onParseError: parseErrors });
    const broken = usbFrame.slice();
    broken[548] ^= 0x01;
    parser.feed(broken);
    expect(envelopes).not.toHaveBeenCalled();
    expect(parseErrors).toHaveBeenCalled();
    const detail = parseErrors.mock.calls[0][0];
    expect(detail.code).toBe('CRC_MISMATCH');
    expect(detail.frameLength).toBe(550);
    expect(detail.waveCount).toBe(256);
    expect(detail.bandCount).toBe(16);
    expect(detail.crcActual).not.toBe(detail.crcExpected);
    expect(parser.getStats().lastErrorDetail?.code).toBe('CRC_MISMATCH');
  });

  it('rejects min/max order violations even when CRC is valid', () => {
    const envelopes = vi.fn();
    const parseErrors = vi.fn();
    const parser = new StreamParser({ onEnvelope: envelopes, onParseError: parseErrors });
    const broken = usbFrame.slice();
    const brokenView = new DataView(broken.buffer, broken.byteOffset, broken.byteLength);
    const firstMin = usbView.getInt16(20, true);
    brokenView.setInt16(20, 4000, true);
    brokenView.setInt16(22, -4000, true);
    brokenView.setUint16(548, crc16(broken.subarray(0, 548)), true);
    parser.feed(broken);
    expect(envelopes).not.toHaveBeenCalled();
    expect(parseErrors).toHaveBeenCalled();
    expect(parseErrors.mock.calls[0][0].code).toBe('MINMAX_ORDER');
    expect(firstMin).toBe(0);
  });

  it('ignores a corrupted CRC frame and exposes the error', () => {
    const wave = vi.fn();
    const errors = vi.fn();
    const parser = new StreamParser({ onWave: wave, onError: errors });
    parser.feed(framedFrame({ wave: [1, 2], bands: [4], corruptCrc: true }));
    expect(wave).not.toHaveBeenCalled();
    expect(errors).toHaveBeenCalled();
    expect(parser.getStats().errors).toBeGreaterThan(0);
  });

  it('waits for a complete frame instead of fabricating data', () => {
    const wave = vi.fn();
    const parser = new StreamParser({ onWave: wave });
    const frame = framedFrame({ wave: [1, 2, 3, 4], bands: [1, 2] });
    parser.feed(frame.subarray(0, frame.length - 5));
    expect(wave).not.toHaveBeenCalled();
    parser.feed(frame.subarray(frame.length - 5));
    expect(wave).toHaveBeenCalledTimes(1);
  });
});
