export type ParserMode = 'unknown' | 'justfloat' | 'adc' | 'framed';

export type DataSourceKind =
  | 'none'
  | 'justfloat'
  | 'adc'
  | 'framed'
  | 'framed-envelope'
  | 'demo';

export interface WaveBatch {
  samples: Float32Array;
  sampleRate: number;
  source: 'justfloat' | 'framed' | 'demo';
  sequence?: number;
  receivedAt: number;
}

export interface WaveEnvelopeBatch {
  mins: Float32Array;
  maxs: Float32Array;
  sampleRate: number;
  source: 'framed';
  sequence?: number;
  receivedAt: number;
  groupSize: number;
}

export interface SpectrumBatch {
  values: Uint8Array;
  sampleRate: number;
  source: 'framed' | 'demo';
  sequence?: number;
  receivedAt: number;
}

export interface AdcSnapshot {
  values: number[];
  line: string;
  receivedAt: number;
}

export interface ParseErrorDetail {
  code: string;
  message: string;
  streamOffset: number;
  expected?: string;
  actual?: string;
  frameLength?: number;
  waveCount?: number;
  bandCount?: number;
  crcExpected?: number;
  crcActual?: number;
}

export interface ParserStats {
  bytes: number;
  validFrames: number;
  errors: number;
  lastError: string;
  lastErrorDetail: ParseErrorDetail | null;
  lastValidAt: number;
  mode: ParserMode;
}

export interface ParserEvents {
  onWave?: (batch: WaveBatch) => void;
  onEnvelope?: (batch: WaveEnvelopeBatch) => void;
  onSpectrum?: (batch: SpectrumBatch) => void;
  onAdc?: (snapshot: AdcSnapshot) => void;
  onMode?: (mode: ParserMode, detail: string) => void;
  onError?: (message: string) => void;
  onParseError?: (detail: ParseErrorDetail) => void;
  onInfo?: (message: string) => void;
}
