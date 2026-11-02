import './style.css';
import { DemoSource } from './audio/DemoSource';
import { StreamParser } from './protocol/parser';
import { DEFAULT_PHOTO_SET_VERSION, PhotoDeck } from './render/PhotoDeck';
import { Visualizer, type DataState, type VisualSettings } from './render/Visualizer';
import type { SpectrumColumnCount } from './render/SpectrumDisplay';
import { SerialManager, type SerialState } from './serial/SerialManager';
import { RawPreview } from './ui/RawPreview';
import type { DataSourceKind, ParseErrorDetail, ParserMode } from './types';

type UiConnection = 'disconnected' | 'connecting' | 'connected' | 'error';
type StreamState = 'none' | 'waiting' | 'receiving' | 'interrupted' | 'adc';

const byId = <T extends HTMLElement>(id: string): T => {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing element #${id}`);
  return element as T;
};

const statusPill = byId<HTMLDivElement>('statusPill');
const statusText = byId<HTMLSpanElement>('statusText');
const sourcePill = byId<HTMLDivElement>('sourcePill');
const liveTime = byId<HTMLDivElement>('liveTime');
const stageClock = byId<HTMLDivElement>('stageClock');
const emptyState = byId<HTMLDivElement>('emptyState');
const demoBanner = byId<HTMLDivElement>('demoBanner');
const serialHint = byId<HTMLDivElement>('serialHint');
const supportState = byId<HTMLSpanElement>('supportState');
const connectButton = byId<HTMLButtonElement>('connectButton');
const disconnectButton = byId<HTMLButtonElement>('disconnectButton');
const panelConnect = byId<HTMLButtonElement>('panelConnect');
const reconnectButton = byId<HTMLButtonElement>('reconnectButton');
const emptyConnect = byId<HTMLButtonElement>('emptyConnect');
const fullscreenButton = byId<HTMLButtonElement>('fullscreenButton');
const baudSelect = byId<HTMLSelectElement>('baudSelect');
const photoInput = byId<HTMLInputElement>('photoInput');
const photoCount = byId<HTMLSpanElement>('photoCount');
const intervalRange = byId<HTMLInputElement>('intervalRange');
const intervalValue = byId<HTMLOutputElement>('intervalValue');
const photoOffsetRange = byId<HTMLInputElement>('photoOffsetRange');
const photoOffsetValue = byId<HTMLOutputElement>('photoOffsetValue');
const spectrumBars = byId<HTMLSelectElement>('spectrumBars');
const spectrumColor = byId<HTMLInputElement>('spectrumColor');
const waveColor = byId<HTMLInputElement>('waveColor');
const spectrumGainRange = byId<HTMLInputElement>('spectrumGainRange');
const spectrumGainValue = byId<HTMLOutputElement>('spectrumGainValue');
const intensityRange = byId<HTMLInputElement>('intensityRange');
const intensityValue = byId<HTMLOutputElement>('intensityValue');
const fullscreenHud = byId<HTMLDivElement>('fullscreenHud');
const fsStatus = byId<HTMLElement>('fsStatus');
const fsSource = byId<HTMLElement>('fsSource');
const fsConnectButton = byId<HTMLButtonElement>('fsConnectButton');
const fsDisconnectButton = byId<HTMLButtonElement>('fsDisconnectButton');
const exitFullscreenButton = byId<HTMLButtonElement>('exitFullscreenButton');
const demoToggle = byId<HTMLInputElement>('demoToggle');
const formatValue = byId<HTMLSpanElement>('formatValue');
const rateValue = byId<HTMLSpanElement>('rateValue');
const bytesValue = byId<HTMLSpanElement>('bytesValue');
const framesValue = byId<HTMLSpanElement>('framesValue');
const errorsValue = byId<HTMLSpanElement>('errorsValue');
const lastValue = byId<HTMLSpanElement>('lastValue');
const protocolNote = byId<HTMLDivElement>('protocolNote');
const diagConnection = byId<HTMLElement>('diagConnection');
const diagDataState = byId<HTMLElement>('diagDataState');
const diagProtocol = byId<HTMLElement>('diagProtocol');
const diagByteRate = byId<HTMLElement>('diagByteRate');
const diagError = byId<HTMLElement>('diagError');
const diagSpectrum = byId<HTMLElement>('diagSpectrum');
const diagSummary = byId<HTMLSpanElement>('diagSummary');
const rawPreviewElement = byId<HTMLPreElement>('rawPreview');
const rawMeta = byId<HTMLElement>('rawMeta');
const parseErrorCode = byId<HTMLElement>('parseErrorCode');
const parseErrorDetailElement = byId<HTMLPreElement>('parseErrorDetail');

const rawPreview = new RawPreview(rawPreviewElement, rawMeta);
const photoDeck = new PhotoDeck();
const visualizer = new Visualizer(byId<HTMLCanvasElement>('stage'), photoDeck);
const parser = new StreamParser({
  onMode: (mode, detail) => handleMode(mode, detail),
  onWave: (batch) => {
    if (demoActive) return;
    lastValidAt = batch.receivedAt;
    dataState = 'receiving';
    sourceKind = batch.source;
    parserMode = batch.source === 'framed' ? 'framed' : 'justfloat';
    sampleRate = batch.sampleRate;
    visualizer.setDataState('receiving');
    visualizer.setMeta({
      mode: parserMode,
      source: batch.source,
      sampleRate,
      detail: batch.source === 'justfloat' ? 'VOFA JustFloat · 原始 PCM' : 'FPGA 帧协议',
    });
    visualizer.pushWave(batch.samples, batch.sampleRate);
    frameCounter += 1;
    updateFrameClock();
    renderStatus();
  },
  onEnvelope: (batch) => {
    if (demoActive) return;
    lastValidAt = batch.receivedAt;
    dataState = 'receiving';
    sourceKind = 'framed-envelope';
    parserMode = 'framed';
    sampleRate = batch.sampleRate;
    visualizer.setDataState('receiving');
    visualizer.setMeta({
      mode: 'framed',
      source: 'framed',
      sampleRate,
      detail: 'USB 候选 · 128 组 min/max + 16 bands',
    });
    visualizer.pushEnvelope(batch.mins, batch.maxs, batch.sampleRate);
    frameCounter += 1;
    updateFrameClock();
    renderStatus();
  },
  onSpectrum: (batch) => {
    if (demoActive) return;
    lastValidAt = batch.receivedAt;
    dataState = 'receiving';
    if (sourceKind !== 'framed-envelope') sourceKind = 'framed';
    parserMode = 'framed';
    sampleRate = batch.sampleRate;
    spectrumBands = batch.values.length;
    visualizer.setDataState('receiving');
    visualizer.setMeta({
      mode: 'framed',
      source: 'framed',
      sampleRate,
      detail: sourceKind === 'framed-envelope'
        ? 'USB 候选 · 128 组 min/max + 16 bands'
        : 'FPGA 帧协议 · PCM + 频谱',
    });
    visualizer.pushSpectrum(batch.values, batch.sampleRate);
    frameCounter += 1;
    updateFrameClock();
    renderStatus();
  },
  onAdc: (snapshot) => {
    if (demoActive) return;
    lastValidAt = snapshot.receivedAt;
    dataState = 'adc';
    sourceKind = 'adc';
    parserMode = 'adc';
    spectrumBands = 0;
    adcValues = snapshot.values.slice();
    visualizer.setDataState('adc');
    visualizer.clearWave();
    visualizer.clearSpectrum();
    visualizer.setAdc(snapshot.values);
    visualizer.setMeta({ mode: 'adc', source: 'adc', sampleRate: 0, detail: 'ADC 遥测 / 非音频' });
    frameCounter += 1;
    updateFrameClock();
    renderStatus();
  },
  onInfo: (message) => {
    if (/ADC_TEST_START/.test(message)) lastError = '';
    renderStatus();
  },
  onError: (message) => {
    lastError = message;
    renderStatus();
  },
  onParseError: (detail) => {
    lastParseError = detail;
    lastError = detail.message;
    renderStatus();
  },
});

const serial = new SerialManager({
  onData: (chunk) => {
    rawPreview.append(chunk);
    parser.feed(chunk);
    syncStats();
  },
  onState: (state) => {
    serialState = state;
    if (state === 'connected') {
      uiConnection = 'connected';
      if (!demoActive) {
        dataState = 'waiting';
        visualizer.setDataState('waiting');
      }
    } else if (state === 'connecting') {
      uiConnection = 'connecting';
    } else if (state === 'disconnected') {
      uiConnection = 'disconnected';
      if (!demoActive) {
        dataState = 'none';
        spectrumBands = 0;
        visualizer.setDataState('none');
        visualizer.clearWave();
        visualizer.clearSpectrum();
      }
    }
    renderStatus();
  },
  onError: (message) => {
    lastError = message;
    if (uiConnection === 'connected' && dataState === 'waiting') {
      dataState = 'interrupted';
      visualizer.setDataState('interrupted');
    }
    renderStatus();
  },
  onDisconnect: (message) => {
    uiConnection = 'disconnected';
    serialState = 'disconnected';
    lastError = message;
    if (!demoActive) {
      dataState = 'none';
      spectrumBands = 0;
      adcValues = [];
      visualizer.setDataState('none');
      visualizer.clearWave();
      visualizer.clearSpectrum();
    }
    setConnectDisabled(false);
    renderStatus();
  },
});

const demo = new DemoSource({
  onWave: (samples, sampleRate) => {
    if (!demoActive) return;
    visualizer.setDataState('receiving');
    visualizer.pushWave(samples, sampleRate);
    frameCounter += 1;
    updateFrameClock();
  },
  onSpectrum: (values, sampleRate) => {
    if (!demoActive) return;
    visualizer.setDataState('receiving');
    visualizer.pushSpectrum(values, sampleRate);
    frameCounter += 1;
    updateFrameClock();
  },
});

let serialState: SerialState = 'disconnected';
let uiConnection: UiConnection = 'disconnected';
let dataState: StreamState = 'none';
let sourceKind: DataSourceKind = 'none';
let parserMode: ParserMode = 'unknown';
let sampleRate = 0;
let spectrumBands = 0;
let adcValues: number[] = [];
let lastValidAt = 0;
let lastError = '';
let lastParseError: ParseErrorDetail | null = null;
let frameCounter = 0;
let demoActive = false;
let byteRate = 0;
let lastBytes = 0;
let lastByteSample = performance.now();

migrateLegacyPhotoState();
const stored = readStoredSettings();
const columnsFromStorage: SpectrumColumnCount =
  stored.spectrumColumns === 32 || stored.spectrumColumns === 96 ? stored.spectrumColumns : 64;
const settings: VisualSettings = {
  spectrumColor: stored.spectrumColor ?? '#46d7e8',
  waveColor: stored.waveColor ?? '#9bffef',
  intensity: stored.intensity ?? 0.78,
  spectrumColumns: columnsFromStorage,
  spectrumGain: Math.min(2.4, Math.max(0.6, stored.spectrumGain ?? 1.4)),
  photoOffset: Math.min(1, Math.max(-1, stored.photoOffset ?? 0)),
};

applySettings();
void loadPhotos();
updateSupportState();
startClocks();
renderStatus();
applyFullscreenState();

function startClocks(): void {
  window.setInterval(() => {
    liveTime.textContent = new Date().toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    updateLastValue();
    updateByteRate();
    checkDataTimeout();
    syncStats();
    rawPreview.render();
    renderStatus();
  }, 250);

  window.setInterval(() => {
    liveTime.textContent = new Date().toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  }, 1000);
}

function checkDataTimeout(): void {
  if (demoActive || uiConnection !== 'connected' || !lastValidAt) return;
  if (dataState !== 'receiving' && dataState !== 'adc') return;
  const timeout = parserMode === 'adc' ? 3000 : parserMode === 'framed' ? 2200 : 1600;
  if (performance.now() - lastValidAt > timeout) {
    dataState = 'interrupted';
    visualizer.setDataState('interrupted');
  }
}

function updateSupportState(): void {
  if (!serial.supported) {
    supportState.textContent = '需要 Chrome / Edge Web Serial';
    serialHint.textContent = '当前浏览器不支持 Web Serial，请使用 Windows Chrome 或 Edge。';
    setConnectDisabled(true);
    return;
  }
  if (!serial.secure) {
    supportState.textContent = '需要 localhost 或 HTTPS';
    serialHint.textContent = 'Web Serial 只能在安全上下文使用，请用 localhost 启动。';
    setConnectDisabled(true);
    return;
  }
  supportState.textContent = 'Web Serial 可用 · Chrome/Edge';
  serialHint.textContent = 'Chrome / Edge · 需要 localhost 或 HTTPS。必须由用户点击选择串口。';
  setConnectDisabled(false);
}

async function loadPhotos(): Promise<void> {
  await photoDeck.loadDefaults();
  photoDeck.setInterval(Number(intervalRange.value));
  updatePhotoCount();
  syncEmptyState();
}

async function connectSerial(): Promise<void> {
  if (demoActive) setDemoMode(false);
  setConnectDisabled(true);
  lastError = '';
  lastParseError = null;
  rawPreview.clear();
  parser.reset();
  visualizer.clearWave();
  visualizer.clearSpectrum();
  visualizer.setDataState('waiting');
  dataState = 'waiting';
  sourceKind = 'none';
  parserMode = 'unknown';
  sampleRate = 0;
  spectrumBands = 0;
  adcValues = [];
  lastValidAt = 0;
  lastBytes = 0;
  byteRate = 0;
  syncStats();
  updateFrameClock();
  renderStatus();

  try {
    await serial.connect(Number(baudSelect.value));
  } catch (error) {
    uiConnection = 'error';
    lastError = error instanceof Error ? error.message : String(error);
    dataState = 'none';
    visualizer.setDataState('none');
    renderStatus();
  } finally {
    setConnectDisabled(uiConnection === 'connected' || uiConnection === 'connecting');
  }
}

async function disconnectSerial(): Promise<void> {
  await serial.disconnect();
  uiConnection = 'disconnected';
  dataState = 'none';
  spectrumBands = 0;
  adcValues = [];
  visualizer.setDataState('none');
  visualizer.clearWave();
  visualizer.clearSpectrum();
  setConnectDisabled(false);
  renderStatus();
}

function setConnectDisabled(disabled: boolean): void {
  connectButton.disabled = disabled;
  panelConnect.disabled = disabled;
  emptyConnect.disabled = disabled;
  fsConnectButton.disabled = disabled;
  reconnectButton.disabled = uiConnection !== 'error' && uiConnection !== 'disconnected';
  disconnectButton.disabled = !(serial.isConnected() || serialState === 'connected');
  fsDisconnectButton.disabled = disconnectButton.disabled;
}

function handleMode(mode: ParserMode, detail: string): void {
  parserMode = mode;
  if (mode === 'justfloat') {
    sourceKind = 'justfloat';
    dataState = uiConnection === 'connected' ? 'waiting' : dataState;
    spectrumBands = 0;
    visualizer.setMeta({ mode, source: 'justfloat', sampleRate: 6031.71, detail });
    visualizer.clearSpectrum();
  } else if (mode === 'framed') {
    sourceKind = 'framed';
    dataState = uiConnection === 'connected' ? 'waiting' : dataState;
    spectrumBands = 0;
    visualizer.setMeta({ mode, source: 'framed', sampleRate: 0, detail });
  } else if (mode === 'adc') {
    sourceKind = 'adc';
    dataState = 'adc';
    spectrumBands = 0;
    adcValues = [];
    visualizer.setDataState('adc');
    visualizer.clearWave();
    visualizer.clearSpectrum();
    visualizer.setMeta({ mode, source: 'adc', sampleRate: 0, detail });
  }
  if (uiConnection === 'connected') visualizer.setDataState(dataState);
  renderStatus();
}

function setDemoMode(active: boolean): void {
  demoActive = active;
  demoToggle.checked = active;
  demoBanner.hidden = !active;
  visualizer.setDemo(active);

  if (active) {
    void serial.disconnect();
    uiConnection = 'disconnected';
    sourceKind = 'demo';
    parserMode = 'framed';
    sampleRate = 48_000;
    spectrumBands = 0;
    dataState = 'receiving';
    rawPreview.clear('DEMO 模式：无串口原始字节');
    visualizer.setDataState('receiving');
    visualizer.setMeta({ mode: 'framed', source: 'demo', sampleRate: 48_000, detail: 'DEMO / 本地生成' });
    demo.start();
  } else {
    demo.stop();
    visualizer.setDataState('none');
    visualizer.clearWave();
    visualizer.clearSpectrum();
    visualizer.setDemo(false);
    sourceKind = 'none';
    parserMode = 'unknown';
    sampleRate = 0;
    spectrumBands = 0;
    adcValues = [];
    dataState = serial.isConnected() ? 'waiting' : 'none';
    visualizer.setDataState(dataState);
    lastValidAt = 0;
  }
  syncEmptyState();
  renderStatus();
}

function renderStatus(): void {
  let label = '未连接';
  let pillState = 'disconnected';
  let sourceLabel = '等待数据源';

  if (demoActive) {
    label = 'DEMO · 非硬件数据';
    pillState = 'waiting';
    sourceLabel = 'DEMO / 本地合成';
  } else if (uiConnection === 'error') {
    label = '连接失败';
    pillState = 'error';
    sourceLabel = '检查 USB 调试口与串口占用';
  } else if (uiConnection === 'connecting') {
    label = '正在连接';
    pillState = 'waiting';
    sourceLabel = '请求串口授权';
  } else if (uiConnection === 'connected') {
    if (dataState === 'receiving') {
      label = '正在接收有效数据';
      pillState = 'receiving';
    } else if (dataState === 'adc') {
      label = 'ADC 遥测（非音频）';
      pillState = 'waiting';
    } else if (dataState === 'interrupted') {
      label = '数据中断';
      pillState = 'error';
    } else if (parserMode === 'unknown' && parser.getStats().bytes > 0 && parser.getStats().errors > 3) {
      label = '协议不匹配';
      pillState = 'error';
    } else {
      label = '已连接，等待数据';
      pillState = 'waiting';
    }
    sourceLabel = sourceLabelFor(sourceKind, parserMode);
  } else {
    label = '未连接';
    pillState = 'disconnected';
    sourceLabel = '选择 USB 调试串口';
  }

  statusPill.dataset.state = pillState;
  statusText.textContent = label;
  sourcePill.textContent = sourceLabel;
  fsStatus.textContent = label;
  fsSource.textContent = sourceLabel;
  formatValue.textContent = formatMode(parserMode, sourceKind);
  rateValue.textContent = sampleRate > 0 ? `${sampleRate.toFixed(1)} S/s` : '--';
  errorsValue.textContent = String(parser.getStats().errors);
  diagConnection.textContent = serialState;
  diagDataState.textContent = dataState === 'adc' && adcValues.length > 0
    ? `adc ${adcValues.join(', ')} mV`
    : dataState;
  diagProtocol.textContent = parserMode === 'unknown' ? '等待自动识别' : `${parserMode} · ${sourceLabel}`;
  diagError.textContent = lastError || '无';
  parseErrorCode.textContent = lastParseError?.code ?? '无';
  parseErrorDetailElement.textContent = formatParseError(lastParseError);
  diagSpectrum.textContent = spectrumDiagnostic();
  protocolNote.textContent = protocolCopy();
  disconnectButton.disabled = !serial.isConnected() && uiConnection !== 'connected';
  reconnectButton.disabled = !(uiConnection === 'error' || uiConnection === 'disconnected');
  syncEmptyState();
}

function syncStats(): void {
  const stats = parser.getStats();
  bytesValue.textContent = formatCount(stats.bytes);
  framesValue.textContent = formatCount(stats.validFrames);
  errorsValue.textContent = formatCount(stats.errors);
  updateLastValue();
  updateByteRate();
}

function updateLastValue(): void {
  if (!lastValidAt) {
    lastValue.textContent = '--';
    return;
  }
  const seconds = Math.max(0, (performance.now() - lastValidAt) / 1000);
  lastValue.textContent = seconds < 1 ? '刚刚' : `${seconds.toFixed(1)} s 前`;
}

function updateByteRate(): void {
  const now = performance.now();
  const stats = parser.getStats();
  const elapsed = (now - lastByteSample) / 1000;
  if (elapsed >= 0.4) {
    const delta = Math.max(0, stats.bytes - lastBytes);
    byteRate = delta / elapsed;
    lastBytes = stats.bytes;
    lastByteSample = now;
  }
  diagByteRate.textContent = `${formatCount(byteRate)} B/s`;
}

function updateFrameClock(): void {
  stageClock.textContent = `FRAME ${String(frameCounter % 1_000_000).padStart(6, '0')}`;
}

function updatePhotoCount(): void {
  const count = photoDeck.count;
  photoCount.textContent = `${count} 张本地照片`;
  if (count > 0) {
    emptyState.classList.add('is-hidden');
  }
}

function syncEmptyState(): void {
  const connected = uiConnection === 'connected' || demoActive;
  const hasData = dataState === 'receiving' || dataState === 'adc';
  const hide = photoDeck.count > 0 || connected || hasData || uiConnection === 'connecting';
  emptyState.classList.toggle('is-hidden', hide);
}

function formatMode(mode: ParserMode, source: DataSourceKind): string {
  if (source === 'demo') return 'DEMO';
  if (source === 'framed-envelope') return 'FRAME · MIN/MAX';
  if (mode === 'justfloat') return 'VOFA JustFloat';
  if (mode === 'framed') return 'FPGA FRAME';
  if (mode === 'adc') return 'ADC TEXT';
  return '未识别';
}

function sourceLabelFor(source: DataSourceKind, mode: ParserMode): string {
  if (source === 'framed-envelope') return 'FPGA MIN/MAX · 128 组';
  if (source === 'justfloat' || mode === 'justfloat') return 'VOFA JustFloat · PCM';
  if (source === 'framed' || mode === 'framed') return 'FPGA FRAME · PCM/FFT';
  if (source === 'adc' || mode === 'adc') return 'ADC 遥测 · 非音频';
  return '已连接 · 等待协议';
}

function spectrumDiagnostic(): string {
  if (demoActive) return 'DEMO 合成频谱';
  if (sourceKind === 'adc' || parserMode === 'adc') return '不适用（ADC 遥测）';
  if (spectrumBands > 0) {
    return `${spectrumBands} REAL BANDS · ${settings.spectrumColumns} DISPLAY COLUMNS · ${sampleRate.toFixed(0)} S/s`;
  }
  if (parserMode === 'justfloat') return '当前固件未发送 FFT';
  if (parserMode === 'framed') return '等待频谱字段';
  return '等待帧协议';
}

function protocolCopy(): string {
  if (demoActive) return '演示模式：波形和频谱由浏览器生成，不是硬件数据。';
  if (parserMode === 'justfloat') {
    return '当前音频工程：U15 → FTDI → COM，921600 8N1，VOFA JustFloat 原始 PCM，约 6031.7 S/s；当前流没有 FPGA 频谱。';
  }
  if (parserMode === 'framed' && sourceKind === 'framed-envelope') {
    return '当前 USB 候选：type 2，256 个 int16 = 128 组 {min,max}，16 个 Goertzel 频段；CRC16 严格校验，详情见 docs/PROTOCOL.md。';
  }
  if (parserMode === 'framed') {
    return '已识别 FPGA 帧协议。波形与频谱均来自同一帧；详情见 docs/PROTOCOL.md。';
  }
  if (parserMode === 'adc') {
    return adcValues.length > 0
      ? `当前为 ADC 滑杆遥测（约 8 Hz 文本）：A0..A3 = ${adcValues.join(', ')} mV，不是音频波形；不绘制为频谱。`
      : '当前为 ADC 滑杆遥测（约 8 Hz 文本），不是音频波形；不绘制为频谱。';
  }
  return '连接 USB 调试口后自动识别。照片与数据只在本机浏览器处理。当前音频固件只发送 PCM，频谱需要新增帧协议。';
}

function setConnectDisabledState(): void {
  setConnectDisabled(uiConnection === 'connected' || uiConnection === 'connecting');
}

function migrateLegacyPhotoState(): void {
  const markerKey = 'instrument-display-default-photo-set';
  try {
    if (localStorage.getItem(markerKey) === DEFAULT_PHOTO_SET_VERSION) return;

    // The old default files were removed. Drop any persisted photo index,
    // composition and carousel interval so a stale session cannot point at
    // missing images or apply the old crop to the new set.
    for (const key of [
      'instrument-display-photo-index',
      'instrument-display-photo-index-v1',
      'instrument-display-carousel-index',
      'instrument-display-default-photo-index',
    ]) {
      localStorage.removeItem(key);
    }

    const raw = localStorage.getItem('instrument-display-settings');
    if (raw) {
      const parsed = JSON.parse(raw) as Record<string, unknown> | null;
      if (parsed && typeof parsed === 'object') {
        delete parsed.photoOffset;
        localStorage.setItem('instrument-display-settings', JSON.stringify(parsed));
      }
    }

    localStorage.removeItem('instrument-display-interval');
    localStorage.setItem(markerKey, DEFAULT_PHOTO_SET_VERSION);
  } catch {
    // Storage can be unavailable in private/restricted browsing; defaults still work.
  }
}
function readStoredSettings(): {
  spectrumColor?: string;
  waveColor?: string;
  intensity?: number;
  spectrumColumns?: number;
  spectrumGain?: number;
  photoOffset?: number;
} {
  try {
    return JSON.parse(localStorage.getItem('instrument-display-settings') ?? '{}');
  } catch {
    return {};
  }
}

function applySettings(): void {
  spectrumColor.value = settings.spectrumColor;
  waveColor.value = settings.waveColor;
  spectrumBars.value = String(settings.spectrumColumns);
  spectrumGainRange.value = String(settings.spectrumGain);
  spectrumGainValue.textContent = `${settings.spectrumGain.toFixed(2)}×`;
  intensityRange.value = String(Math.round(settings.intensity * 100));
  intensityValue.textContent = `${Math.round(settings.intensity * 100)}%`;
  photoOffsetRange.value = String(Math.round(settings.photoOffset * 100));
  photoOffsetValue.textContent = settings.photoOffset === 0
    ? '居中'
    : `${settings.photoOffset < 0 ? '上移' : '下移'} ${Math.abs(Math.round(settings.photoOffset * 100))}%`;
  visualizer.setSettings(settings);
}

function persistSettings(): void {
  localStorage.setItem('instrument-display-settings', JSON.stringify(settings));
}

function formatParseError(detail: ParseErrorDetail | null): string {
  if (!detail) return '无';
  const lines = [
    `code: ${detail.code}`,
    `offset: ${detail.streamOffset} (0x${detail.streamOffset.toString(16).toUpperCase()})`,
    `message: ${detail.message}`,
  ];
  if (detail.expected !== undefined) lines.push(`expected: ${detail.expected}`);
  if (detail.actual !== undefined) lines.push(`actual: ${detail.actual}`);
  if (detail.frameLength !== undefined) lines.push(`frame_length: ${detail.frameLength}`);
  if (detail.waveCount !== undefined) lines.push(`wave_count: ${detail.waveCount}`);
  if (detail.bandCount !== undefined) lines.push(`band_count: ${detail.bandCount}`);
  if (detail.crcExpected !== undefined) lines.push(`crc_expected: 0x${detail.crcExpected.toString(16).padStart(4, '0')}`);
  if (detail.crcActual !== undefined) lines.push(`crc_actual: 0x${detail.crcActual.toString(16).padStart(4, '0')}`);
  return lines.join('\n');
}

function formatCount(value: number): string {
  if (!Number.isFinite(value)) return '--';
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)} M`;
  if (value >= 10_000) return `${(value / 1000).toFixed(1)} k`;
  return `${Math.round(value)}`;
}

function setDemoFromUi(): void {
  setDemoMode(demoToggle.checked);
  setConnectDisabledState();
}

connectButton.addEventListener('click', () => void connectSerial());
panelConnect.addEventListener('click', () => void connectSerial());
emptyConnect.addEventListener('click', () => void connectSerial());
reconnectButton.addEventListener('click', () => void connectSerial());
disconnectButton.addEventListener('click', () => void disconnectSerial());
demoToggle.addEventListener('change', setDemoFromUi);

function applyFullscreenState(): void {
  const active = document.fullscreenElement !== null;
  document.body.classList.toggle('is-fullscreen', active);
  fullscreenHud.hidden = !active;
  visualizer.setFullscreen(active);
  requestAnimationFrame(() => visualizer.refreshSize());
  renderStatus();
}

fullscreenButton.addEventListener('click', () => {
  if (document.fullscreenElement) void document.exitFullscreen();
  else void document.documentElement.requestFullscreen().catch(() => undefined);
});

fsConnectButton.addEventListener('click', () => void connectSerial());
fsDisconnectButton.addEventListener('click', () => void disconnectSerial());

exitFullscreenButton.addEventListener('click', () => {
  if (document.fullscreenElement) void document.exitFullscreen();
});

document.addEventListener('fullscreenchange', applyFullscreenState);

photoInput.addEventListener('change', async () => {
  if (!photoInput.files) return;
  const added = await photoDeck.addFiles(photoInput.files);
  photoInput.value = '';
  updatePhotoCount();
  syncEmptyState();
  if (added === 0) lastError = '没有读取到有效图片文件。';
  else lastError = '';
  renderStatus();
});

intervalRange.addEventListener('input', () => {
  const seconds = Number(intervalRange.value);
  intervalValue.textContent = `${seconds.toFixed(1)} s`;
  photoDeck.setInterval(seconds);
  localStorage.setItem('instrument-display-interval', String(seconds));
});

photoOffsetRange.addEventListener('input', () => {
  settings.photoOffset = Number(photoOffsetRange.value) / 100;
  photoOffsetValue.textContent = settings.photoOffset === 0
    ? '居中'
    : `${settings.photoOffset < 0 ? '上移' : '下移'} ${Math.abs(Math.round(settings.photoOffset * 100))}%`;
  visualizer.setSettings(settings);
  persistSettings();
});

spectrumBars.addEventListener('change', () => {
  settings.spectrumColumns = Number(spectrumBars.value) as SpectrumColumnCount;
  visualizer.setSettings(settings);
  renderStatus();
  persistSettings();
});

spectrumGainRange.addEventListener('input', () => {
  settings.spectrumGain = Number(spectrumGainRange.value);
  spectrumGainValue.textContent = `${settings.spectrumGain.toFixed(2)}×`;
  visualizer.setSettings(settings);
  persistSettings();
});

spectrumColor.addEventListener('input', () => {
  settings.spectrumColor = spectrumColor.value;
  visualizer.setSettings(settings);
  persistSettings();
});

waveColor.addEventListener('input', () => {
  settings.waveColor = waveColor.value;
  visualizer.setSettings(settings);
  persistSettings();
});

intensityRange.addEventListener('input', () => {
  settings.intensity = Number(intensityRange.value) / 100;
  intensityValue.textContent = `${Math.round(settings.intensity * 100)}%`;
  visualizer.setSettings(settings);
  persistSettings();
});

const savedInterval = Number(localStorage.getItem('instrument-display-interval') ?? '10');
if (Number.isFinite(savedInterval) && savedInterval >= 4 && savedInterval <= 30) {
  intervalRange.value = String(savedInterval);
  intervalValue.textContent = `${savedInterval.toFixed(1)} s`;
  photoDeck.setInterval(savedInterval);
} else {
  photoDeck.setInterval(10);
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden' && demoActive) {
    demo.stop();
  } else if (document.visibilityState === 'visible' && demoActive) {
    demo.start();
  }
});

window.addEventListener('beforeunload', () => {
  demo.stop();
  void serial.disconnect();
  photoDeck.clear();
  localStorage.setItem('instrument-display-settings', JSON.stringify(settings));
});
