// iPad -> BLE -> ESP32-C3-Zero -> UART -> FPGA -> UART -> ESP -> BLE -> iPad
// Board: ESP32C3 Dev Module, USB CDC On Boot = Enabled.
// ASCII PING/FPGA_PING diagnostics remain. The app may send compact binary
// performance events: E0 EVENT KEY VALUE.

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <atomic>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <Preferences.h>
#include <SPIFFS.h>
#include <mbedtls/sha256.h>

namespace {

constexpr const char *kDeviceName = "FPGA-Instrument";
constexpr const char *kServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr const char *kRxUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr const char *kTxUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

constexpr uint8_t kFpgaRxPin = 20;
constexpr uint8_t kFpgaTxPin = 21;
constexpr uint32_t kFpgaBaud = 115200;
constexpr uint32_t kRequestTimeoutMs = 600;
constexpr uint32_t kPartialFrameTimeoutMs = 20;
constexpr uint32_t kHeartbeatMs = 500;

constexpr uint8_t kHeader0 = 0xA5;
constexpr uint8_t kHeader1 = 0x5A;
constexpr uint8_t kTypePingRequest = 0x01;
constexpr uint8_t kTypePingReply = 0x81;
constexpr uint8_t kTypeEvent = 0x10;
constexpr uint8_t kTypeQuery = 0x11;
constexpr uint8_t kTypeQueryReply = 0x91;
constexpr uint8_t kAppMagic = 0xE0;
constexpr uint8_t kQueryMagic = 0xE1;
constexpr uint8_t kMusicMagic = 0xE2;
constexpr uint8_t kMusicBegin = 0x10;
constexpr uint8_t kMusicData = 0x11;
constexpr uint8_t kMusicCommit = 0x12;
constexpr uint8_t kMusicPrepare = 0x13;
constexpr uint8_t kMusicPlay = 0x14;
constexpr uint8_t kMusicStop = 0x15;
constexpr uint8_t kMusicStatusReq = 0x16;
constexpr uint8_t kMusicCapsReq = 0x01;
constexpr uint8_t kMusicCapsRsp = 0x81;
constexpr uint8_t kMusicAck = 0x92;
constexpr uint8_t kMusicStatusRsp = 0x96;
constexpr uint8_t kMusicError = 0x97;
constexpr uint8_t kMusicProgress = 0xB1;
constexpr uint32_t kMusicMaxBytes = 65536;
constexpr const char *kMusicStoragePath = "/music_perf.bin";
constexpr const char *kMusicStorageTempPath = "/music_perf.tmp";
constexpr uint32_t kMusicPreloadMs = 1000;
constexpr uint32_t kMusicLeadMs = 500;
constexpr uint32_t kMusicFsNum = 52500000;
constexpr uint32_t kMusicFsDen = 1088;

constexpr uint8_t kEvNoteOn = 0x01;
constexpr uint8_t kEvNoteOff = 0x02;
constexpr uint8_t kEvDrum = 0x03;
constexpr uint8_t kEvGuitar = 0x04;
constexpr uint8_t kEvReleaseAll = 0x05;
constexpr uint8_t kEvAllOff = 0x06;
constexpr uint8_t kEvSessionStart = 0x07;
constexpr uint8_t kEvHeartbeat = 0x08;
constexpr uint8_t kEvGtrPluck = 0x20;
constexpr uint8_t kEvGtrFret = 0x21;
constexpr uint8_t kEvGtrPalm = 0x22;
constexpr uint8_t kEvChordSelect = 0x23;
constexpr uint8_t kEvChordTrigger = 0x24;
constexpr uint8_t kEvChordRelease = 0x25;
constexpr uint8_t kEvBend = 0x26;
constexpr uint8_t kEvVibrato = 0x27;
constexpr uint8_t kEvGlide = 0x28;
constexpr uint8_t kEvSlideTime = 0x29;
constexpr uint8_t kEvOverdrive = 0x2A;
constexpr uint8_t kEvReverb = 0x2B;
constexpr uint8_t kEvPianoOct = 0x30;
constexpr uint8_t kEvPianoDamp = 0x31;
constexpr uint8_t kEvPianoPedalDelay = 0x32;
constexpr uint8_t kEvPianoPedalRelease = 0x33;
constexpr uint8_t kMaxPayload = 16;

struct BleCommand {
  uint8_t data[32];
  uint8_t len;
};

struct AppEvent {
  uint8_t event;
  uint8_t key;
  uint8_t value;
};

struct MusicCommand {
  uint8_t data[200];
  uint8_t len;
};

HardwareSerial FpgaSerial(1);
BLECharacteristic *bleTx = nullptr;
QueueHandle_t bleCommands = nullptr;
QueueHandle_t appQueue = nullptr;
QueueHandle_t musicCommands = nullptr;

uint8_t *musicPerf = nullptr;
uint32_t musicTotal = 0;
uint32_t musicWritten = 0;
uint32_t musicSession = 0;
uint32_t musicPlayId = 0;
uint32_t musicEventCount = 0;
uint32_t musicDurationSamples = 0;
uint32_t musicNextEvent = 0;
uint32_t musicStartMs = 0;
bool musicReady = false;
bool musicStreaming = false;
bool musicStorageLoaded = false;
bool musicPrepared = false;
uint8_t musicHash[32] = {};
bool musicHashValid = false;
Preferences musicPrefs;

constexpr uint32_t kMusicStartTimeoutMs = 3000;
constexpr uint32_t kMusicStopTimeoutMs = 2000;
constexpr uint8_t kMusicTxIdle = 0;
constexpr uint8_t kMusicTxBegin = 1;
constexpr uint8_t kMusicTxPreload = 2;
constexpr uint8_t kMusicTxPlay = 3;
constexpr uint8_t kMusicTxStreaming = 4;
constexpr uint8_t kMusicTxStop = 5;
uint8_t musicTxPhase = kMusicTxIdle;
uint8_t musicStartSeq = 0;
uint8_t musicStartUartSeq = 0;
uint8_t musicPlayUartSeq = 0;
uint8_t musicStopSeq = 0;
uint8_t musicStopUartSeq = 0;
uint8_t musicStopReason = 0;
bool musicStopNotify = false;
uint32_t musicStartAtMs = 0;
uint32_t musicStartDeadlineMs = 0;
uint32_t musicStopDeadlineMs = 0;
uint32_t musicTxLastLogMs = 0;
uint8_t musicBeginPayload[16] = {};
uint8_t musicPlayPayload[12] = {};
uint8_t musicStopPayload[5] = {};

std::atomic<bool> bleConnected(false);
std::atomic<bool> bleRestart(false);
std::atomic<bool> bleConnectEvent(false);
std::atomic<bool> queryRequested(false);
std::atomic<bool> appQueueFull(false);
std::atomic<bool> rxTooLong(false);

bool fpgaPending = false;
uint8_t fpgaSeq = 0;
uint8_t nextSeq = 1;
uint32_t fpgaDeadlineMs = 0;

bool queryPending = false;
bool usbTestMode = false;
uint8_t querySeq = 0;
uint32_t queryDeadlineMs = 0;

uint8_t appSeq = 1;
uint32_t lastHeartbeatMs = 0;

enum RxState : uint8_t {
  RX_WAIT_A5, RX_WAIT_5A, RX_TYPE, RX_SEQ, RX_LEN, RX_PAYLOAD, RX_CRC
};

RxState rxState = RX_WAIT_A5;
uint8_t rxType = 0;
uint8_t rxSeq = 0;
uint8_t rxLen = 0;
uint8_t rxPayload[kMaxPayload] = {};
uint8_t rxPayloadCount = 0;
uint8_t rxCrc = 0;
uint32_t rxLastByteMs = 0;

uint8_t crc8Update(uint8_t crc, uint8_t value) {
  crc ^= value;
  for (uint8_t bit = 0; bit < 8; ++bit)
    crc = (crc & 0x80) ? static_cast<uint8_t>((crc << 1) ^ 0x07)
                       : static_cast<uint8_t>(crc << 1);
  return crc;
}

uint8_t crc8(const uint8_t *data, size_t len) {
  uint8_t crc = 0;
  for (size_t i = 0; i < len; ++i) crc = crc8Update(crc, data[i]);
  return crc;
}

void writeLog(const char *text) {
  Serial.write(reinterpret_cast<const uint8_t *>(text), strlen(text));
}

void sendBle(const String &text) {
  if (!bleConnected.load() || bleTx == nullptr) return;
  char log[96];
  snprintf(log, sizeof(log), "BLE TX: %s\n", text.c_str());
  writeLog(log);
  bleTx->setValue(reinterpret_cast<const uint8_t *>(text.c_str()), text.length());
  bleTx->notify();
}

void sendBleBinary(const uint8_t *data, size_t len) {
  if (!bleConnected.load() || bleTx == nullptr || len == 0) return;
  bleTx->setValue(data, len);
  bleTx->notify();
  char log[64];
  snprintf(log, sizeof(log), "BLE TX binary len=%u\n", static_cast<unsigned>(len));
  writeLog(log);
}

void sendMusicProgress(uint8_t seq, const uint8_t *payload, uint8_t len);

void resetUartParser() {
  rxState = RX_WAIT_A5;
  rxType = 0;
  rxSeq = 0;
  rxLen = 0;
  rxPayloadCount = 0;
  rxCrc = 0;
  rxLastByteMs = millis();
}

void logUartFrame(const char *direction, uint8_t type, uint8_t seq,
                  const uint8_t *payload, uint8_t len) {
  char buf[128];
  int n = snprintf(buf, sizeof(buf), "%s type=0x%02X seq=%u len=%u frame=",
                   direction, type, seq, len);
  if (n < 0) return;
  for (uint8_t i = 0; i < len + 6 && n < static_cast<int>(sizeof(buf)) - 3; ++i) {
    // Frame is logged by callers through a concise header; payload is enough here.
  }
  if (len > 0) {
    n += snprintf(buf + n, sizeof(buf) - n, " payload=");
    for (uint8_t i = 0; i < len && n < static_cast<int>(sizeof(buf)) - 4; ++i)
      n += snprintf(buf + n, sizeof(buf) - n, "%02X", payload[i]);
  }
  if (n < static_cast<int>(sizeof(buf)) - 1) {
    buf[n++] = '\n';
    buf[n] = 0;
    writeLog(buf);
  }
}

bool sendUartFrame(uint8_t type, uint8_t seq, const uint8_t *payload, uint8_t len) {
  if (len > kMaxPayload) return false;
  uint8_t frame[6 + kMaxPayload];
  frame[0] = kHeader0;
  frame[1] = kHeader1;
  frame[2] = type;
  frame[3] = seq;
  frame[4] = len;
  for (uint8_t i = 0; i < len; ++i) frame[5 + i] = payload[i];
  frame[5 + len] = crc8(&frame[2], static_cast<size_t>(3 + len));
  const size_t total = static_cast<size_t>(6 + len);
  if (FpgaSerial.availableForWrite() < static_cast<int>(total)) return false;
  const size_t written = FpgaSerial.write(frame, total);
  logUartFrame("UART TX", type, seq, payload, len);
  return written == total;
}

void completeFpgaPing() {
  if (!fpgaPending) return;
  if (rxType != kTypePingReply || rxLen != 0 || rxSeq != fpgaSeq) {
    writeLog("UART RX: ping reply mismatch; waiting for timeout\n");
    return;
  }
  fpgaPending = false;
  char log[64];
  snprintf(log, sizeof(log), "UART RX seq=%u type=0x%02X len=0 crc=OK\n", rxSeq, rxType);
  writeLog(log);
  String reply = "FPGA_PONG seq=";
  reply += String(fpgaSeq);
  if (bleConnected.load()) sendBle(reply);
  else writeLog((reply + "\n").c_str());
}

void completeFpgaQuery() {
  if (!queryPending) return;
  if (rxType != kTypeQueryReply || rxLen != 6 || rxSeq != querySeq) {
    writeLog("UART RX: query reply mismatch; waiting for timeout\n");
    return;
  }
  queryPending = false;
  char log[64];
  snprintf(log, sizeof(log), "UART RX seq=%u type=0x%02X len=6 crc=OK\n", rxSeq, rxType);
  writeLog(log);
  char reply[32];
  snprintf(reply, sizeof(reply), "CAPS;%u;%02X%02X%02X%02X;%u",
           rxPayload[0], rxPayload[4], rxPayload[3], rxPayload[2],
           rxPayload[1], rxPayload[5] & 1);
  if (bleConnected.load()) sendBle(reply);
  else writeLog((String(reply) + "\n").c_str());
}

void feedUartByte(uint8_t value) {
  rxLastByteMs = millis();
  switch (rxState) {
    case RX_WAIT_A5:
      if (value == kHeader0) rxState = RX_WAIT_5A;
      break;
    case RX_WAIT_5A:
      if (value == kHeader1) {
        rxState = RX_TYPE;
        rxCrc = 0;
      } else if (value != kHeader0) {
        rxState = RX_WAIT_A5;
      }
      break;
    case RX_TYPE:
      rxType = value;
      rxCrc = crc8Update(rxCrc, value);
      rxState = RX_SEQ;
      break;
    case RX_SEQ:
      rxSeq = value;
      rxCrc = crc8Update(rxCrc, value);
      rxState = RX_LEN;
      break;
    case RX_LEN:
      rxLen = value;
      rxCrc = crc8Update(rxCrc, value);
      rxPayloadCount = 0;
      if (rxLen > kMaxPayload) resetUartParser();
      else if (rxLen == 0) rxState = RX_CRC;
      else rxState = RX_PAYLOAD;
      break;
    case RX_PAYLOAD:
      rxPayload[rxPayloadCount++] = value;
      rxCrc = crc8Update(rxCrc, value);
      if (rxPayloadCount == rxLen) rxState = RX_CRC;
      break;
    case RX_CRC: {
      const bool crcOk = (value == rxCrc);
      char log[64];
      snprintf(log, sizeof(log), "UART RX seq=%u type=0x%02X len=%u crc=%s\n",
               rxSeq, rxType, rxLen, crcOk ? "OK" : "BAD");
      writeLog(log);
      if (crcOk) {
        if (rxType == kTypePingReply) completeFpgaPing();
        else if (rxType == kTypeQueryReply) completeFpgaQuery();
        else if (rxType == kMusicProgress && rxLen == 7) sendMusicProgress(rxSeq, rxPayload, 7);
      }
      resetUartParser();
      break;
    }
    default: resetUartParser(); break;
  }
}

void startFpgaPing() {
  if (!bleConnected.load() && !usbTestMode) return;
  if (fpgaPending) {
    sendBle("ERR:BUSY");
    return;
  }
  while (FpgaSerial.available() > 0) (void)FpgaSerial.read();
  resetUartParser();
  fpgaSeq = nextSeq++;
  if (!sendUartFrame(kTypePingRequest, fpgaSeq, nullptr, 0)) {
    sendBle("ERR:UART_TX");
    return;
  }
  fpgaPending = true;
  fpgaDeadlineMs = millis() + kRequestTimeoutMs;
}

void startFpgaQuery() {
  if (!bleConnected.load() && !usbTestMode) return;
  if (queryPending) {
    sendBle("ERR:BUSY");
    return;
  }
  uint8_t payload[1] = {0x01};
  querySeq = nextSeq++;
  if (!sendUartFrame(kTypeQuery, querySeq, payload, 1)) {
    sendBle("ERR:UART_TX");
    return;
  }
  queryPending = true;
  queryDeadlineMs = millis() + kRequestTimeoutMs;
}

bool sendAppEventFrame(uint8_t event, uint8_t key, uint8_t value) {
  uint8_t payload[3] = {event, key, value};
  return sendUartFrame(kTypeEvent, appSeq++, payload, 3);
}

bool validAppEvent(const AppEvent &e) {
  switch (e.event) {
    case kEvNoteOn:
    case kEvNoteOff: return e.key < 16;
    case kEvDrum: return e.key < 9;
    case kEvGuitar:
    case kEvGtrPluck: return e.key < 6;
    case kEvGtrFret: return e.key <= 12;
    case kEvGtrPalm: return e.key < 2;
    case kEvChordSelect: return e.key < 4;
    case kEvChordTrigger: return e.key == 0 && e.value >= 1 && e.value <= 15;
    case kEvChordRelease: return true;
    case kEvBend: return e.key < 3;
    case kEvVibrato:
    case kEvGlide: return e.key < 2;
    case kEvSlideTime: return e.key >= 1 && e.key <= 15;
    case kEvOverdrive:
    case kEvReverb: return e.key < 2;
    case kEvPianoOct: return e.key < 3;
    case kEvPianoDamp:
    case kEvPianoPedalDelay: return e.key < 2;
    case kEvPianoPedalRelease:
    case kEvReleaseAll:
    case kEvAllOff:
    case kEvSessionStart:
    case kEvHeartbeat: return true;
    default: return false;
  }
}

void enqueueAppEvent(uint8_t event, uint8_t key, uint8_t value) {
  AppEvent e = {event, key, value};
  if (xQueueSend(appQueue, &e, 0) != pdTRUE) {
    // Release/stop are urgent. Drop stale queued performance work rather than
    // silently losing them; the event is then appended to the queue.
    if (event == kEvReleaseAll || event == kEvAllOff) {
      xQueueReset(appQueue);
      (void)xQueueSend(appQueue, &e, 0);
      writeLog("QUEUE: reset for urgent release/stop\n");
    } else {
      appQueueFull.store(true);
    }
  }
}

static uint32_t rd32(const uint8_t *p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}
static void wr32(uint8_t *p, uint32_t v) {
  p[0] = v & 0xff; p[1] = (v >> 8) & 0xff;
  p[2] = (v >> 16) & 0xff; p[3] = (v >> 24) & 0xff;
}
static uint32_t musicEventMs(uint32_t samples) {
  return static_cast<uint32_t>((static_cast<uint64_t>(samples) * 1000ULL * kMusicFsDen) / kMusicFsNum);
}

void logMusicTx(const char *phase, const char *result, uint32_t elapsedMs, uint32_t seq) {
  char b[160];
  snprintf(b, sizeof(b),
           "MUSIC TX seq=%lu phase=%s result=%s uart_free=%d elapsed_ms=%lu next_event=%lu/%lu\n",
           static_cast<unsigned long>(seq), phase, result,
           FpgaSerial.availableForWrite(), static_cast<unsigned long>(elapsedMs),
           static_cast<unsigned long>(musicNextEvent), static_cast<unsigned long>(musicEventCount));
  writeLog(b);
  musicTxLastLogMs = millis();
}

void sendMusicStatus(uint8_t seq, uint8_t state, uint8_t code, uint32_t received, uint32_t stored) {
  uint8_t f[15];
  f[0] = kMusicMagic; f[1] = kMusicStatusRsp; f[2] = seq; f[3] = 10;
  f[4] = state; f[5] = code;
  wr32(&f[6], received); wr32(&f[10], stored);
  f[14] = crc8(f + 1, 13);
  sendBleBinary(f, 15);
}

void sendMusicProgress(uint8_t seq, const uint8_t *payload, uint8_t len) {
  uint8_t f[3 + 16 + 1];
  if (len > 16) return;
  f[0] = kMusicMagic; f[1] = kMusicProgress; f[2] = seq; f[3] = len;
  memcpy(&f[4], payload, len);
  f[4 + len] = crc8(f + 1, 3 + len);
  sendBleBinary(f, 5 + len);
}

void sendMusicError(uint8_t seq, uint8_t code) {
  uint8_t f[6] = {kMusicMagic, kMusicError, seq, 1, code, 0};
  f[5] = crc8(f + 1, 4);
  sendBleBinary(f, 6);
}

void requestMusicStop(uint8_t reason, bool notify, uint8_t seq) {
  // Cancel any in-flight start or streaming immediately. The STOP frame is
  // queued, not lost when the UART is busy; the status is sent only after it
  // has actually been accepted by the UART driver.
  musicStreaming = false;
  musicPrepared = false;
  musicStopReason = reason;
  musicStopNotify = notify;
  musicStopSeq = seq;
  musicStopUartSeq = appSeq;
  musicStopDeadlineMs = millis() + kMusicStopTimeoutMs;
  wr32(musicStopPayload, musicPlayId);
  musicStopPayload[4] = reason;
  musicTxPhase = kMusicTxStop;
  logMusicTx("STOP", "queued", 0, seq);
}

void stopMusicStreaming(uint8_t reason) {
  requestMusicStop(reason, false, 0);
}

bool parseMusicHeader() {
  if (musicPerf == nullptr || musicTotal < 32) return false;
  if (memcmp(musicPerf, "FPGS", 4) != 0 || musicPerf[4] != 1 || musicPerf[5] != 32 ||
      musicPerf[6] != 8) return false;
  musicEventCount = rd32(musicPerf + 16);
  musicDurationSamples = rd32(musicPerf + 20);
  if (musicEventCount > (kMusicMaxBytes - 32) / 8) return false;
  if (musicTotal < 32 + musicEventCount * 8) return false;
  return true;
}

bool writeMusicToStorage(const uint8_t *data, size_t length) {
  if (data == nullptr || length < 32 || length > kMusicMaxBytes) return false;
  if (!SPIFFS.begin(true)) {
    writeLog("STORAGE: SPIFFS mount failed\n");
    return false;
  }
  File file = SPIFFS.open(kMusicStorageTempPath, FILE_WRITE);
  if (!file) {
    writeLog("STORAGE: temp open failed\n");
    return false;
  }
  size_t wrote = file.write(data, length);
  file.close();
  if (wrote != length) {
    SPIFFS.remove(kMusicStorageTempPath);
    writeLog("STORAGE: short write\n");
    return false;
  }
  if (SPIFFS.exists(kMusicStoragePath)) {
    SPIFFS.remove(kMusicStoragePath);
  }
  if (!SPIFFS.rename(kMusicStorageTempPath, kMusicStoragePath)) {
    SPIFFS.remove(kMusicStorageTempPath);
    writeLog("STORAGE: rename failed\n");
    return false;
  }
  return true;
}

void clearLegacyNvsPerformance() {
  musicPrefs.begin("music", false);
  musicPrefs.remove("perf");
  musicPrefs.end();
}

void loadMusicFromStorage() {
  if (musicPerf != nullptr) return;
  if (!SPIFFS.begin(true)) {
    writeLog("STORAGE: SPIFFS mount failed\n");
  } else {
    File file = SPIFFS.open(kMusicStoragePath, FILE_READ);
    if (file) {
      size_t n = file.size();
      if (n >= 32 && n <= kMusicMaxBytes) {
        uint8_t *p = static_cast<uint8_t *>(malloc(n));
        if (p != nullptr && file.read(p, n) == n) {
          musicPerf = p; musicTotal = n; musicWritten = n;
          musicStorageLoaded = true;
          musicReady = parseMusicHeader();
          file.close();
          if (musicReady) {
            writeLog("STORAGE: performance loaded\n");
            return;
          }
          free(p);
          musicPerf = nullptr;
          musicTotal = 0;
          musicWritten = 0;
          musicReady = false;
        } else {
          free(p);
        }
      }
      file.close();
    }
  }

  musicPrefs.begin("music", true);
  size_t n = musicPrefs.getBytesLength("perf");
  if (n >= 32 && n <= kMusicMaxBytes) {
    uint8_t *p = static_cast<uint8_t *>(malloc(n));
    if (p != nullptr && musicPrefs.getBytes("perf", p, n) == n) {
      musicPerf = p; musicTotal = n; musicWritten = n;
      musicReady = parseMusicHeader();
      if (musicReady) {
        if (writeMusicToStorage(p, n)) {
          writeLog("STORAGE: migrated legacy NVS performance\n");
          clearLegacyNvsPerformance();
        }
        writeLog("NVS: legacy performance loaded\n");
        musicPrefs.end();
        return;
      }
      free(p);
      musicPerf = nullptr;
      musicTotal = 0;
      musicWritten = 0;
    } else {
      free(p);
    }
  }
  musicPrefs.end();
  writeLog("STORAGE: no cached performance\n");
}

bool sendSongEvent(uint32_t idx) {
  if (idx >= musicEventCount || musicPerf == nullptr) return false;
  if (FpgaSerial.availableForWrite() < 14) return false;
  const uint8_t *e = musicPerf + 32 + idx * 8;
  if (!sendUartFrame(0x31, appSeq, e, 8)) return false;
  appSeq++;
  return true;
}

void failMusicStart(uint8_t code) {
  const uint8_t seq = musicStartSeq;
  musicTxPhase = kMusicTxIdle;
  musicStreaming = false;
  musicPrepared = false;
  logMusicTx("START", "error", musicStartAtMs ? millis() - musicStartAtMs : 0, seq);
  sendMusicError(seq, code);
}

void requestMusicStart(uint8_t requestSeq) {
  if (musicTxPhase != kMusicTxIdle) {
    logMusicTx("START", "busy", millis() - musicStartAtMs, requestSeq);
    sendMusicError(requestSeq, 3);
    return;
  }
  if (!musicReady) loadMusicFromStorage();
  if (!musicReady || !parseMusicHeader()) { sendMusicError(requestSeq, 2); return; }
  if (!musicPrepared) { sendMusicError(requestSeq, 11); return; }

  musicStartSeq = requestSeq;
  musicStartUartSeq = appSeq;
  musicPlayUartSeq = 0;
  musicNextEvent = 0;
  musicStartAtMs = millis();
  musicStartDeadlineMs = musicStartAtMs + kMusicStartTimeoutMs;
  wr32(&musicBeginPayload[0], musicPlayId);
  wr32(&musicBeginPayload[4], musicEventCount);
  wr32(&musicBeginPayload[8], musicDurationSamples);
  wr32(&musicBeginPayload[12], 0);
  wr32(&musicPlayPayload[0], musicPlayId);
  wr32(&musicPlayPayload[4], 24127); // 500 ms at 52500000/1088
  wr32(&musicPlayPayload[8], 0);
  musicTxPhase = kMusicTxBegin;
  logMusicTx("START", "queued", 0, requestSeq);
}

void pollMusicStreaming() {
  if (musicTxPhase != kMusicTxStreaming) return;
  int32_t elapsed = static_cast<int32_t>(millis() - musicStartMs);
  while (musicNextEvent < musicEventCount) {
    uint32_t t = rd32(musicPerf + 32 + musicNextEvent * 8);
    if (elapsed + 1500 < static_cast<int32_t>(musicEventMs(t))) break;
    if (!sendSongEvent(musicNextEvent)) {
      if (millis() - musicTxLastLogMs >= 500)
        logMusicTx("STREAM", "uart_busy", elapsed > 0 ? static_cast<uint32_t>(elapsed) : 0, musicStartSeq);
      return;
    }
    musicNextEvent++;
  }
  if (musicNextEvent >= musicEventCount &&
      elapsed > static_cast<int32_t>(musicEventMs(musicDurationSamples) + 2500)) {
    musicStreaming = false;
    musicPrepared = false;
    musicTxPhase = kMusicTxIdle;
    logMusicTx("END", "sent_all", elapsed > 0 ? static_cast<uint32_t>(elapsed) : 0, musicStartSeq);
    sendMusicStatus(0, 4, 0, musicWritten, musicTotal);
  }
}

void pollMusicTx() {
  if (musicTxPhase == kMusicTxIdle) return;
  const uint32_t now = millis();

  if (musicTxPhase == kMusicTxStop) {
    if (sendUartFrame(0x33, musicStopUartSeq, musicStopPayload, 5)) {
      appSeq++;
      musicTxPhase = kMusicTxIdle;
      logMusicTx("STOP", "sent", now - (musicStopDeadlineMs - kMusicStopTimeoutMs), musicStopSeq);
      if (musicStopNotify) sendMusicStatus(musicStopSeq, 0, 0, musicWritten, musicTotal);
    } else if (static_cast<int32_t>(now - musicStopDeadlineMs) >= 0) {
      musicTxPhase = kMusicTxIdle;
      logMusicTx("STOP", "timeout", now - (musicStopDeadlineMs - kMusicStopTimeoutMs), musicStopSeq);
      if (musicStopNotify) sendMusicError(musicStopSeq, 3);
    } else if (now - musicTxLastLogMs >= 500) {
      logMusicTx("STOP", "uart_busy", now - (musicStopDeadlineMs - kMusicStopTimeoutMs), musicStopSeq);
    }
    return;
  }

  if (musicTxPhase == kMusicTxStreaming) { pollMusicStreaming(); return; }

  if (static_cast<int32_t>(now - musicStartDeadlineMs) >= 0) {
    failMusicStart(3);
    return;
  }

  if (musicTxPhase == kMusicTxBegin) {
    if (sendUartFrame(0x30, musicStartUartSeq, musicBeginPayload, 16)) {
      appSeq++;
      musicTxPhase = kMusicTxPreload;
      logMusicTx("BEGIN", "sent", now - musicStartAtMs, musicStartSeq);
    } else if (now - musicTxLastLogMs >= 500) {
      logMusicTx("BEGIN", "uart_busy", now - musicStartAtMs, musicStartSeq);
    }
    return;
  }

  if (musicTxPhase == kMusicTxPreload) {
    while (musicNextEvent < musicEventCount) {
      uint32_t t = rd32(musicPerf + 32 + musicNextEvent * 8);
      if (musicEventMs(t) > kMusicPreloadMs) break;
      if (!sendSongEvent(musicNextEvent)) {
        if (now - musicTxLastLogMs >= 500)
          logMusicTx("PRELOAD", "uart_busy", now - musicStartAtMs, musicStartSeq);
        return;
      }
      musicNextEvent++;
    }
    musicPlayUartSeq = appSeq;
    musicTxPhase = kMusicTxPlay;
    logMusicTx("PRELOAD", "done", now - musicStartAtMs, musicStartSeq);
    return;
  }

  if (musicTxPhase == kMusicTxPlay) {
    if (sendUartFrame(0x32, musicPlayUartSeq, musicPlayPayload, 12)) {
      appSeq++;
      musicStartMs = millis() + kMusicLeadMs;
      musicStreaming = true;
      musicTxPhase = kMusicTxStreaming;
      logMusicTx("PLAY", "sent", now - musicStartAtMs, musicStartSeq);
      // ESP transport state only; this is not an FPGA execution acknowledgement.
      sendMusicStatus(musicStartSeq, 2, 0, musicWritten, musicTotal);
    } else if (now - musicTxLastLogMs >= 500) {
      logMusicTx("PLAY", "uart_busy", now - musicStartAtMs, musicStartSeq);
    }
  }
}

void handleMusicCommand(const MusicCommand &cmd) {
  if (cmd.len < 5 || cmd.data[0] != kMusicMagic) return;
  uint8_t type = cmd.data[1], seq = cmd.data[2], len = cmd.data[3];
  if (static_cast<size_t>(len) + 5 > cmd.len) { sendMusicError(seq, 1); return; }
  if (crc8(cmd.data + 1, 3 + len) != cmd.data[4 + len]) { sendMusicError(seq, 1); return; }
  const uint8_t *p = cmd.data + 4;
  if (type == kMusicCapsReq) {
    uint8_t f[4 + 10] = {kMusicMagic, kMusicCapsRsp, seq, 9};
    f[4] = 3; f[5] = 0xff; f[6] = 0xff; f[7] = 0x03; f[8] = 0x00;
    wr32(&f[9], kMusicMaxBytes); f[13] = crc8(f + 1, 12);
    sendBleBinary(f, 14);
    return;
  }
  if (type == kMusicBegin && len != 40) { sendMusicError(seq, 1); return; }
  if (type == kMusicBegin && len == 40) {
    if (musicTxPhase != kMusicTxIdle) { sendMusicError(seq, 3); return; }
    musicSession = rd32(p); musicTotal = rd32(p + 4);
    if (musicTotal < 32 || musicTotal > kMusicMaxBytes) { sendMusicError(seq, 4); return; }
    if (musicPerf != nullptr) free(musicPerf);
    musicPerf = static_cast<uint8_t *>(malloc(musicTotal));
    if (musicPerf == nullptr) { sendMusicError(seq, 5); return; }
    memcpy(musicHash, p + 8, 32);
    musicHashValid = true;
    musicWritten = 0; musicReady = false; musicPrepared = false;
    musicPlayId = musicSession;
    char mlog[96];
    snprintf(mlog, sizeof(mlog), "MUSIC: begin total=%u free_heap=%u\n", musicTotal, ESP.getFreeHeap());
    writeLog(mlog);
    sendMusicStatus(seq, 1, 0, 0, musicTotal);
    return;
  }
  if (type == kMusicData && len >= 4) {
    uint32_t off = rd32(p);
    uint32_t n = len - 4;
    if (musicPerf == nullptr || off > musicTotal || n > musicTotal - off) { sendMusicError(seq, 6); return; }
    memcpy(musicPerf + off, p + 4, n);
    if (off + n > musicWritten) musicWritten = off + n;
    sendMusicStatus(seq, 1, 0, musicWritten, musicTotal);
    return;
  }
  if (type == kMusicCommit && len == 32) {
    if (musicPerf == nullptr || musicWritten != musicTotal || !musicHashValid) { sendMusicError(seq, 7); return; }
    if (memcmp(musicHash, p, 32) != 0) { sendMusicError(seq, 8); return; }
    uint8_t digest[32];
    mbedtls_sha256_context sha;
    mbedtls_sha256_init(&sha);
    mbedtls_sha256_starts(&sha, 0);
    mbedtls_sha256_update(&sha, musicPerf, musicTotal);
    mbedtls_sha256_finish(&sha, digest);
    mbedtls_sha256_free(&sha);
    if (memcmp(digest, p, 32) != 0) { sendMusicError(seq, 8); return; }
    memcpy(musicHash, digest, 32);
    musicHashValid = false;
    bool stored = writeMusicToStorage(musicPerf, musicTotal);
    if (stored) clearLegacyNvsPerformance();
    char mlog[96];
    snprintf(mlog, sizeof(mlog), "STORAGE: write=%s total=%u free_heap=%u\n", stored ? "ok" : "failed", musicTotal, ESP.getFreeHeap());
    writeLog(mlog);
    if (!stored) { sendMusicError(seq, 9); return; }
    musicReady = parseMusicHeader(); musicPrepared = false;
    sendMusicStatus(seq, musicReady ? 3 : 10, 0, musicWritten, musicTotal);
    return;
  }
  if (type == kMusicPrepare) {
    loadMusicFromStorage();
    if (!parseMusicHeader()) { sendMusicError(seq, 11); return; }
    musicReady = true; musicPrepared = true; musicNextEvent = 0;
    sendMusicStatus(seq, 3, 0, musicWritten, musicTotal);
    return;
  }
  if (type == kMusicPlay) {
    if (!musicReady) loadMusicFromStorage();
    if (!parseMusicHeader()) { sendMusicError(seq, 11); return; }
    if (!musicPrepared) { sendMusicError(seq, 11); return; }
    requestMusicStart(seq);
    return;
  }
  if (type == kMusicStop) {
    requestMusicStop(1, true, seq);
    return;
  }
  if (type == kMusicStatusReq) {
    sendMusicStatus(seq, musicStreaming ? 2 : 0, 0, musicWritten, musicTotal);
    return;
  }
  sendMusicError(seq, 12);
}

void pollMusicCommands() {
  MusicCommand c;
  while (musicCommands != nullptr && xQueueReceive(musicCommands, &c, 0) == pdTRUE) {
    handleMusicCommand(c);
  }
}
void pollMusicCommands();
void pollMusicTx();

void pollAppEvents() {
  AppEvent e;
  while (xQueueReceive(appQueue, &e, 0) == pdTRUE) {
    if (!bleConnected.load() && !usbTestMode && e.event != kEvReleaseAll && e.event != kEvAllOff) continue;
    if (!validAppEvent(e)) {
      sendBle("ERR:BAD_EVENT");
      continue;
    }
    if (FpgaSerial.availableForWrite() < 9) {
      xQueueSendToFront(appQueue, &e, 0);
      break;
    }
    if (!sendAppEventFrame(e.event, e.key, e.value)) {
      sendBle("ERR:UART_TX");
      break;
    }
  }
}

void pollFpgaUart() {
  while (FpgaSerial.available() > 0) feedUartByte(static_cast<uint8_t>(FpgaSerial.read()));

  if (rxState != RX_WAIT_A5 &&
      static_cast<uint32_t>(millis() - rxLastByteMs) > kPartialFrameTimeoutMs) {
    resetUartParser();
  }

  if (fpgaPending && static_cast<int32_t>(millis() - fpgaDeadlineMs) >= 0) {
    fpgaPending = false;
    resetUartParser();
    sendBle("ERR:FPGA_TIMEOUT");
  }
  if (queryPending && static_cast<int32_t>(millis() - queryDeadlineMs) >= 0) {
    queryPending = false;
    resetUartParser();
    sendBle("ERR:FPGA_TIMEOUT");
  }
}

char usbTestLine[80];
uint8_t usbTestLineLen = 0;

void logTestEvent(const char *what, int a, int b, int c) {
  char buf[80];
  snprintf(buf, sizeof(buf), "USB TEST: %s %d %d %d\n", what, a, b, c);
  writeLog(buf);
}

void runTestCommand(const char *line) {
  if (!usbTestMode && !bleConnected.load()) {
    usbTestMode = true;
    lastHeartbeatMs = millis();
    enqueueAppEvent(kEvSessionStart, 0, 0);
    writeLog("USB TEST MODE: session start (no BLE required)\n");
  }
  unsigned a = 0, b = 0, c = 0;
  if (strcmp(line, "TEST HELP") == 0) {
    writeLog("TEST NOTE k v | TEST OFF k | TEST DRUM k v | TEST GTR s f v [palm]\n");
    writeLog("TEST CHS p | TEST CHT v | TEST CHORD p v | TEST OCT 0..2 | TEST BEND 0..2\n");
    writeLog("TEST VIB 0/1 | TEST GLIDE 0/1 | TEST SLIDE 1..15 | TEST OD 0/1 | TEST REV 0/1\n");
    writeLog("TEST DAMP 0/1 | TEST PEDAL 0/1 | TEST PEDREL | TEST REL | TEST STOP | TEST CAPS\n");
    return;
  }
  if (strcmp(line, "TEST CAPS") == 0) { startFpgaQuery(); return; }
  if (strcmp(line, "TEST REL") == 0) { enqueueAppEvent(kEvReleaseAll, 0, 0); logTestEvent("REL", 0, 0, 0); return; }
  if (strcmp(line, "TEST STOP") == 0) { enqueueAppEvent(kEvAllOff, 0, 0); logTestEvent("STOP", 0, 0, 0); return; }
  if (strcmp(line, "TEST PEDREL") == 0) { enqueueAppEvent(kEvPianoPedalRelease, 0, 0); logTestEvent("PEDREL", 0, 0, 0); return; }
  if (sscanf(line, "TEST NOTE %u %u", &a, &b) == 2 && a < 16 && b <= 15) {
    enqueueAppEvent(kEvNoteOn, a, b); logTestEvent("NOTE", a, b, 0); return;
  }
  if (sscanf(line, "TEST OFF %u", &a) == 1 && a < 16) {
    enqueueAppEvent(kEvNoteOff, a, 0); logTestEvent("OFF", a, 0, 0); return;
  }
  if (sscanf(line, "TEST DRUM %u %u", &a, &b) == 2 && a < 9 && b >= 1 && b <= 15) {
    enqueueAppEvent(kEvDrum, a, b); logTestEvent("DRUM", a, b, 0); return;
  }
  unsigned palm = 0;
  int n = sscanf(line, "TEST GTR %u %u %u %u", &a, &b, &c, &palm);
  if (n >= 2 && a < 6) {
    if (n == 2) {
      enqueueAppEvent(kEvGtrPluck, a, b); logTestEvent("GTR current-fret", a, b, 0); return;
    }
    if (b <= 12 && c >= 1 && c <= 15) {
      enqueueAppEvent(kEvGtrFret, b, 0);
      enqueueAppEvent(kEvGtrPalm, palm ? 1 : 0, 0);
      enqueueAppEvent(kEvGtrPluck, a, c);
      logTestEvent("GTR", a, b, c); return;
    }
  }
  if (sscanf(line, "TEST GTRM %u %u %u", &a, &b, &c) == 3 && a < 6 && b <= 12 && c >= 1 && c <= 15) {
    enqueueAppEvent(kEvGtrFret, b, 0); enqueueAppEvent(kEvGtrPalm, 1, 0);
    enqueueAppEvent(kEvGtrPluck, a, c); logTestEvent("GTRP", a, b, c); return;
  }
  if (sscanf(line, "TEST CHS %u", &a) == 1 && a < 4) {
    enqueueAppEvent(kEvChordSelect, a, 0); logTestEvent("CHS", a, 0, 0); return;
  }
  if (sscanf(line, "TEST CHT %u", &a) == 1 && a >= 1 && a <= 15) {
    enqueueAppEvent(kEvChordTrigger, 0, a); logTestEvent("CHT", a, 0, 0); return;
  }
  if (sscanf(line, "TEST CHORD %u %u", &a, &b) == 2 && a < 4 && b >= 1 && b <= 15) {
    enqueueAppEvent(kEvChordSelect, a, 0); enqueueAppEvent(kEvChordTrigger, 0, b);
    logTestEvent("CHORD", a, b, 0); return;
  }
  if (sscanf(line, "TEST OCT %u", &a) == 1 && a < 3) { enqueueAppEvent(kEvPianoOct, a, 0); return; }
  if (sscanf(line, "TEST BEND %u", &a) == 1 && a < 3) { enqueueAppEvent(kEvBend, a, 0); return; }
  if (sscanf(line, "TEST VIB %u", &a) == 1 && a < 2) { enqueueAppEvent(kEvVibrato, a, 0); return; }
  if (sscanf(line, "TEST GLIDE %u", &a) == 1 && a < 2) { enqueueAppEvent(kEvGlide, a, 0); return; }
  if (sscanf(line, "TEST SLIDE %u", &a) == 1 && a >= 1 && a <= 15) { enqueueAppEvent(kEvSlideTime, a, 0); return; }
  if (sscanf(line, "TEST OD %u", &a) == 1 && a < 2) { enqueueAppEvent(kEvOverdrive, a, 0); return; }
  if (sscanf(line, "TEST REV %u", &a) == 1 && a < 2) { enqueueAppEvent(kEvReverb, a, 0); return; }
  if (sscanf(line, "TEST DAMP %u", &a) == 1 && a < 2) { enqueueAppEvent(kEvPianoDamp, a, 0); return; }
  if (sscanf(line, "TEST PEDAL %u", &a) == 1 && a < 2) { enqueueAppEvent(kEvPianoPedalDelay, a, 0); return; }
  writeLog("USB TEST: unknown/invalid command; TEST HELP\n");
}

void pollUsbConsole() {
  while (Serial.available() > 0) {
    const int ch = Serial.read();
    if (ch == '\r') continue;
    if (ch == '\n') {
      usbTestLine[usbTestLineLen] = 0;
      if (usbTestLineLen > 0) runTestCommand(usbTestLine);
      usbTestLineLen = 0;
    } else if (usbTestLineLen < sizeof(usbTestLine) - 1) {
      usbTestLine[usbTestLineLen++] = static_cast<char>(ch);
    } else {
      usbTestLineLen = 0;
      writeLog("USB TEST: line too long\n");
    }
  }
}
void handleBleCommand(const char *raw) {
  String text(raw);
  text.trim();
  if (!bleConnected.load() || text.length() == 0) return;
  char log[96];
  snprintf(log, sizeof(log), "BLE RX: %s\n", text.c_str());
  writeLog(log);

  if (text == "PING") {
    sendBle("PONG");
  } else if (text == "FPGA_PING") {
    startFpgaPing();
  } else if (text == "FPGA_STATUS") {
    startFpgaQuery();
  } else if (text == "STATUS") {
    sendBle(fpgaPending ? "STATUS;B1;F1" : "STATUS;B1;F0");
  } else if (text == "BLE_RELEASE") {
    enqueueAppEvent(kEvReleaseAll, 0, 0);
  } else if (text == "ALL_OFF") {
    enqueueAppEvent(kEvAllOff, 0, 0);
  } else {
    sendBle("ERR:UNKNOWN_CMD");
  }
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    bleConnectEvent.store(true);
    bleConnected.store(true);
  }
  void onDisconnect(BLEServer *) override {
    bleConnected.store(false);
    bleRestart.store(true);
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    const auto value = characteristic->getValue();
    if (value.length() == 0) return;
    if (static_cast<uint8_t>(value[0]) == kMusicMagic) {
      if (value.length() > 200) {
        rxTooLong.store(true);
        return;
      }
      MusicCommand mc = {};
      mc.len = static_cast<uint8_t>(value.length());
      memcpy(mc.data, value.c_str(), value.length());
      if (xQueueSend(musicCommands, &mc, 0) != pdTRUE) appQueueFull.store(true);
      return;
    }
    if (value.length() == 4 && static_cast<uint8_t>(value[0]) == kAppMagic) {
      enqueueAppEvent(static_cast<uint8_t>(value[1]), static_cast<uint8_t>(value[2]),
                      static_cast<uint8_t>(value[3]));
      return;
    }
    if (value.length() == 2 && static_cast<uint8_t>(value[0]) == kQueryMagic) {
      queryRequested.store(true);
      return;
    }
    if (value.length() >= 32) {
      rxTooLong.store(true);
      return;
    }
    BleCommand command = {};
    command.len = static_cast<uint8_t>(value.length());
    memcpy(command.data, value.c_str(), value.length());
    if (xQueueSend(bleCommands, &command, 0) != pdTRUE) appQueueFull.store(true);
  }
};

void startBle() {
  bleCommands = xQueueCreate(4, sizeof(BleCommand));
  appQueue = xQueueCreate(32, sizeof(AppEvent));
  musicCommands = xQueueCreate(8, sizeof(MusicCommand));
  if (bleCommands == nullptr || appQueue == nullptr || musicCommands == nullptr) {
    writeLog("ERROR: BLE queue allocation failed\n");
    while (true) delay(1000);
  }
  BLEDevice::init(kDeviceName);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(kServiceUuid);
  bleTx = service->createCharacteristic(
      kTxUuid, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  bleTx->addDescriptor(new BLE2902());
  bleTx->setValue("READY");
  BLECharacteristic *rx = service->createCharacteristic(
      kRxUuid, BLECharacteristic::PROPERTY_WRITE);
  rx->setCallbacks(new RxCallbacks());
  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUuid);
  advertising->setScanResponse(true);
  advertising->start();
  writeLog("BLE advertising: FPGA-Instrument\n");
}

void handleBleLifecycle() {
  if (bleConnectEvent.exchange(false)) {
    usbTestMode = false;
    fpgaPending = false;
    queryPending = false;
    xQueueReset(bleCommands);
    xQueueReset(appQueue);
    resetUartParser();
    lastHeartbeatMs = millis();
    enqueueAppEvent(kEvSessionStart, 0, 0);
    writeLog("BLE connected\n");
    if (bleTx != nullptr) {
      bleTx->setValue("READY");
      bleTx->notify();
    }
  }

  if (bleRestart.exchange(false)) {
    writeLog("BLE disconnected; BLE release\n");
    stopMusicStreaming(3);
    fpgaPending = false;
    queryPending = false;
    xQueueReset(bleCommands);
    xQueueReset(appQueue);
    resetUartParser();
    uint8_t payload[3] = {kEvReleaseAll, 0, 0};
    (void)sendUartFrame(kTypeEvent, appSeq++, payload, 3);
    delay(100);
    if (bleTx != nullptr) bleTx->setValue("READY");
    BLEDevice::startAdvertising();
    writeLog("BLE advertising restarted\n");
  }

  if ((bleConnected.load() || usbTestMode) && static_cast<uint32_t>(millis() - lastHeartbeatMs) >= kHeartbeatMs) {
    lastHeartbeatMs = millis();
    enqueueAppEvent(kEvHeartbeat, 0, 0);
  }
}

void pollBleCommands() {
  if (rxTooLong.exchange(false)) {
    sendBle("ERR:TOO_LONG");
  }
  if (appQueueFull.exchange(false)) {
    sendBle("ERR:BUSY");
  }
  if (queryRequested.exchange(false)) startFpgaQuery();

  BleCommand command;
  while (xQueueReceive(bleCommands, &command, 0) == pdTRUE) {
    if (!bleConnected.load()) continue;
    char text[33] = {};
    memcpy(text, command.data, command.len);
    handleBleCommand(text);
  }
}

}  // namespace

#if !defined(CONFIG_IDF_TARGET_ESP32C3)
#error "Select ESP32C3 Dev Module in Tools > Board."
#endif

#if !defined(ARDUINO_USB_CDC_ON_BOOT) || !ARDUINO_USB_CDC_ON_BOOT
#error "Enable USB CDC On Boot in the Tools menu."
#endif

void setup() {
  Serial.begin(115200);
  Serial.setTxTimeoutMs(0);
  delay(1200);
  if (!SPIFFS.begin(true)) {
    writeLog("STORAGE: SPIFFS mount failed at boot\n");
  }
  writeLog("\nFPGA UART bridge v0.5.3 start-tx\n");
  writeLog("BLE name=FPGA-Instrument; ASCII PING/FPGA_PING/STATUS/FPGA_STATUS; app E0 EVENT KEY VALUE\n");
  FpgaSerial.begin(kFpgaBaud, SERIAL_8N1, kFpgaRxPin, kFpgaTxPin);
  resetUartParser();
  startBle();
}

void loop() {
  handleBleLifecycle();
  pollBleCommands();
  pollMusicCommands();
  pollMusicTx();
  pollUsbConsole();
  pollAppEvents();
  pollFpgaUart();
  delay(1);
}







