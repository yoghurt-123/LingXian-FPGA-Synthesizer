import Foundation
import SwiftUI

struct FPGAPianoKey: Identifiable, Equatable {
    let id: Int
    let noteName: String
    let keyboardKey: String
    let isBlack: Bool
    let midiNote: Int
    let whiteIndex: Int
    let blackAfterWhite: Int?

    var frequency: Double {
        440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }

    var keyboardLabel: String {
        "\(noteName) · \(keyboardKey)"
    }
}

struct FPGAGuitarString: Identifiable, Equatable {
    let id: Int
    let stringNumber: Int
    let noteName: String
    let keyboardKey: String
    let openMIDINote: Int

    var displayTitle: String {
        "\(stringNumber)弦 \(noteName)"
    }

    var keyboardLabel: String {
        "\(keyboardKey) · \(noteName)"
    }
}

struct FPGAGuitarChordTone: Equatable {
    let stringIndex: Int
    let fret: Int
    let midiNote: Int

    var stringNumber: Int {
        FPGAKeyMap.guitarStrings[stringIndex].stringNumber
    }

    var positionText: String {
        "\(stringNumber)弦\(fret)品"
    }
}

struct FPGAGuitarChord: Identifiable, Equatable {
    let id: Int
    let keyboardKey: String
    let name: String
    let fullName: String
    let tones: [FPGAGuitarChordTone]

    var summary: String {
        tones.map { "\($0.stringNumber)弦\($0.fret == 0 ? "空" : "\($0.fret)品")" }
            .joined(separator: " · ")
    }

    var shortSummary: String {
        tones.map { "\($0.fret == 0 ? "空" : "\($0.fret)")" }.joined(separator: "/")
    }
}

struct FPGAFretKey: Identifiable, Equatable {
    let id: Int
    let fret: Int
    let keyboardKey: String
    let compactKey: String

    var title: String {
        fret == 0 ? "空弦" : "\(fret)品"
    }

    var keyboardLabel: String {
        "\(title) · \(keyboardKey)"
    }
}

struct FPGADrumPad: Identifiable, Equatable {
    let id: Int
    let instrument: DrumKitInstrument
    let keypadNumber: Int
    let gridRow: Int
    let gridColumn: Int
    let gridIndex: Int

    var keyLabel: String {
        "小键盘\(keypadNumber)"
    }

    var title: String {
        instrument.displayName
    }

    var subtitle: String {
        "\(keyLabel) · \(instrument.shortLabel)"
    }
}

struct FPGAControlRow: Identifiable, Equatable {
    let id: String
    let name: String
    let key: String
    let detail: String
    let localPreview: String

    var keyLabel: String {
        key.isEmpty ? "无" : key
    }
}

struct FPGAControlGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [FPGAControlRow]
}

enum FPGAKeyMap {
    static let sourceNote = "依据 GowinProjects/text4 当前 RTL：usb_hid_zones.v、top.v、guitar_expression_keys.v、usb_guitar_keys.v、guitar_chord_engine.v"

    static let pianoKeys: [FPGAPianoKey] = [
        FPGAPianoKey(id: 0, noteName: "C4", keyboardKey: "A", isBlack: false, midiNote: 60, whiteIndex: 0, blackAfterWhite: nil),
        FPGAPianoKey(id: 1, noteName: "D4", keyboardKey: "S", isBlack: false, midiNote: 62, whiteIndex: 1, blackAfterWhite: nil),
        FPGAPianoKey(id: 2, noteName: "E4", keyboardKey: "D", isBlack: false, midiNote: 64, whiteIndex: 2, blackAfterWhite: nil),
        FPGAPianoKey(id: 3, noteName: "F4", keyboardKey: "F", isBlack: false, midiNote: 65, whiteIndex: 3, blackAfterWhite: nil),
        FPGAPianoKey(id: 4, noteName: "G4", keyboardKey: "G", isBlack: false, midiNote: 67, whiteIndex: 4, blackAfterWhite: nil),
        FPGAPianoKey(id: 5, noteName: "A4", keyboardKey: "H", isBlack: false, midiNote: 69, whiteIndex: 5, blackAfterWhite: nil),
        FPGAPianoKey(id: 6, noteName: "B4", keyboardKey: "J", isBlack: false, midiNote: 71, whiteIndex: 6, blackAfterWhite: nil),
        FPGAPianoKey(id: 7, noteName: "C5", keyboardKey: "K", isBlack: false, midiNote: 72, whiteIndex: 7, blackAfterWhite: nil),
        FPGAPianoKey(id: 8, noteName: "D5", keyboardKey: "L", isBlack: false, midiNote: 74, whiteIndex: 8, blackAfterWhite: nil),
        FPGAPianoKey(id: 9, noteName: "C#4", keyboardKey: "Z", isBlack: true, midiNote: 61, whiteIndex: 0, blackAfterWhite: 0),
        FPGAPianoKey(id: 10, noteName: "D#4", keyboardKey: "X", isBlack: true, midiNote: 63, whiteIndex: 1, blackAfterWhite: 1),
        FPGAPianoKey(id: 11, noteName: "F#4", keyboardKey: "C", isBlack: true, midiNote: 66, whiteIndex: 3, blackAfterWhite: 3),
        FPGAPianoKey(id: 12, noteName: "G#4", keyboardKey: "V", isBlack: true, midiNote: 68, whiteIndex: 4, blackAfterWhite: 4),
        FPGAPianoKey(id: 13, noteName: "A#4", keyboardKey: "B", isBlack: true, midiNote: 70, whiteIndex: 5, blackAfterWhite: 5),
        FPGAPianoKey(id: 14, noteName: "C#5", keyboardKey: "N", isBlack: true, midiNote: 73, whiteIndex: 7, blackAfterWhite: 7),
        FPGAPianoKey(id: 15, noteName: "D#5", keyboardKey: "M", isBlack: true, midiNote: 75, whiteIndex: 8, blackAfterWhite: 8)
    ]

    static let whitePianoKeys: [FPGAPianoKey] = pianoKeys
        .filter { !$0.isBlack }
        .sorted { $0.whiteIndex < $1.whiteIndex }

    static let blackPianoKeys: [FPGAPianoKey] = pianoKeys
        .filter { $0.isBlack }
        .sorted { ($0.blackAfterWhite ?? 0) < ($1.blackAfterWhite ?? 0) }

    static func pianoKey(forMidi midi: Int) -> FPGAPianoKey? {
        pianoKeys.first { $0.midiNote == midi }
    }

    static let guitarStrings: [FPGAGuitarString] = [
        FPGAGuitarString(id: 0, stringNumber: 6, noteName: "E2", keyboardKey: "Q", openMIDINote: 40),
        FPGAGuitarString(id: 1, stringNumber: 5, noteName: "A2", keyboardKey: "W", openMIDINote: 45),
        FPGAGuitarString(id: 2, stringNumber: 4, noteName: "D3", keyboardKey: "E", openMIDINote: 50),
        FPGAGuitarString(id: 3, stringNumber: 3, noteName: "G3", keyboardKey: "R", openMIDINote: 55),
        FPGAGuitarString(id: 4, stringNumber: 2, noteName: "B3", keyboardKey: "T", openMIDINote: 59),
        FPGAGuitarString(id: 5, stringNumber: 1, noteName: "E4", keyboardKey: "Y", openMIDINote: 64)
    ]

    static let guitarChords: [FPGAGuitarChord] = [
        FPGAGuitarChord(
            id: 0,
            keyboardKey: "U",
            name: "C",
            fullName: "C 大三和弦",
            tones: [
                FPGAGuitarChordTone(stringIndex: 1, fret: 3, midiNote: 48),
                FPGAGuitarChordTone(stringIndex: 2, fret: 2, midiNote: 52),
                FPGAGuitarChordTone(stringIndex: 3, fret: 0, midiNote: 55)
            ]
        ),
        FPGAGuitarChord(
            id: 1,
            keyboardKey: "I",
            name: "G",
            fullName: "G 大三和弦",
            tones: [
                FPGAGuitarChordTone(stringIndex: 0, fret: 3, midiNote: 43),
                FPGAGuitarChordTone(stringIndex: 1, fret: 2, midiNote: 47),
                FPGAGuitarChordTone(stringIndex: 2, fret: 0, midiNote: 50)
            ]
        ),
        FPGAGuitarChord(
            id: 2,
            keyboardKey: "O",
            name: "Dm",
            fullName: "D 小三和弦",
            tones: [
                FPGAGuitarChordTone(stringIndex: 2, fret: 0, midiNote: 50),
                FPGAGuitarChordTone(stringIndex: 2, fret: 3, midiNote: 53),
                FPGAGuitarChordTone(stringIndex: 3, fret: 2, midiNote: 57)
            ]
        ),
        FPGAGuitarChord(
            id: 3,
            keyboardKey: "P",
            name: "Am",
            fullName: "A 小三和弦",
            tones: [
                FPGAGuitarChordTone(stringIndex: 1, fret: 0, midiNote: 45),
                FPGAGuitarChordTone(stringIndex: 2, fret: 2, midiNote: 52),
                FPGAGuitarChordTone(stringIndex: 4, fret: 1, midiNote: 60)
            ]
        )
    ]

    static let frets: [FPGAFretKey] = [
        FPGAFretKey(id: 0, fret: 0, keyboardKey: "1", compactKey: "1"),
        FPGAFretKey(id: 1, fret: 1, keyboardKey: "2", compactKey: "2"),
        FPGAFretKey(id: 2, fret: 2, keyboardKey: "3", compactKey: "3"),
        FPGAFretKey(id: 3, fret: 3, keyboardKey: "4", compactKey: "4"),
        FPGAFretKey(id: 4, fret: 4, keyboardKey: "5", compactKey: "5"),
        FPGAFretKey(id: 5, fret: 5, keyboardKey: "6", compactKey: "6"),
        FPGAFretKey(id: 6, fret: 6, keyboardKey: "7", compactKey: "7"),
        FPGAFretKey(id: 7, fret: 7, keyboardKey: "8", compactKey: "8"),
        FPGAFretKey(id: 8, fret: 8, keyboardKey: "9", compactKey: "9"),
        FPGAFretKey(id: 9, fret: 9, keyboardKey: "0", compactKey: "0"),
        FPGAFretKey(id: 10, fret: 10, keyboardKey: "-", compactKey: "-"),
        FPGAFretKey(id: 11, fret: 11, keyboardKey: "=", compactKey: "="),
        FPGAFretKey(id: 12, fret: 12, keyboardKey: "Backspace", compactKey: "⌫")
    ]

    static let drumPads: [FPGADrumPad] = [
        FPGADrumPad(id: 4, instrument: .crash, keypadNumber: 6, gridRow: 0, gridColumn: 0, gridIndex: 0),
        FPGADrumPad(id: 2, instrument: .closedHat, keypadNumber: 3, gridRow: 0, gridColumn: 1, gridIndex: 1),
        FPGADrumPad(id: 5, instrument: .ride, keypadNumber: 9, gridRow: 0, gridColumn: 2, gridIndex: 2),
        FPGADrumPad(id: 6, instrument: .highTom, keypadNumber: 7, gridRow: 1, gridColumn: 0, gridIndex: 3),
        FPGADrumPad(id: 7, instrument: .midTom, keypadNumber: 5, gridRow: 1, gridColumn: 1, gridIndex: 4),
        FPGADrumPad(id: 8, instrument: .lowTom, keypadNumber: 8, gridRow: 1, gridColumn: 2, gridIndex: 5),
        FPGADrumPad(id: 1, instrument: .snare, keypadNumber: 2, gridRow: 2, gridColumn: 0, gridIndex: 6),
        FPGADrumPad(id: 0, instrument: .kick, keypadNumber: 1, gridRow: 2, gridColumn: 1, gridIndex: 7),
        FPGADrumPad(id: 3, instrument: .openHat, keypadNumber: 4, gridRow: 2, gridColumn: 2, gridIndex: 8)
    ]

    static func drumPad(for instrument: DrumKitInstrument) -> FPGADrumPad {
        drumPads.first { $0.instrument == instrument } ??
            FPGADrumPad(id: instrument.rawValue, instrument: instrument, keypadNumber: instrument.rawValue + 1, gridRow: 0, gridColumn: 0, gridIndex: 0)
    }

    static let velocityCodes: [(name: String, code: Int, key: String)] = [
        ("轻", 8, "F1 降档"),
        ("中", 11, "默认"),
        ("强", 15, "F2 升档")
    ]

    static let controlGroups: [FPGAControlGroup] = [
        FPGAControlGroup(
            id: "velocity",
            title: "力度与音区",
            rows: [
                FPGAControlRow(id: "vel-down", name: "力度降档", key: "F1", detail: "轻=8，中=11，强=15；边界不回绕。", localPreview: "本地生效"),
                FPGAControlRow(id: "vel-up", name: "力度升档", key: "F2", detail: "连续按档；与 F1 同持不处理。", localPreview: "本地生效"),
                FPGAControlRow(id: "accent", name: "重音", key: "左Shift", detail: "当前力度码 +2，最高 15。", localPreview: "本地生效"),
                FPGAControlRow(id: "oct-down", name: "钢琴降八度", key: "Home", detail: "低/原/高三个八度，只作用于钢琴。", localPreview: "本地生效"),
                FPGAControlRow(id: "oct-up", name: "钢琴升八度", key: "End", detail: "低/原/高三个八度，只作用于钢琴。", localPreview: "本地生效")
            ]
        ),
        FPGAControlGroup(
            id: "guitar",
            title: "吉他左手与表情",
            rows: [
                FPGAControlRow(id: "fret", name: "品位选择 0–12", key: "主键 1–9,0,-,=,退格", detail: "1..9=0..8品，0=9品，-=10品，==11品，Backspace=12品。", localPreview: "本地生效（改变下一次拨弦）"),
                FPGAControlRow(id: "chord", name: "和弦", key: "U I O P", detail: "U=C，I=G，O=Dm，P=Am；按下即三音齐奏。", localPreview: "本地生效（三音）"),
                FPGAControlRow(id: "glide", name: "连奏滑音开关", key: "F11", detail: "与滑音时间、弯音分开；只切换开关。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "slide-time", name: "滑音时间", key: "PageUp / PageDown", detail: "15 档，20–300 ms，默认 80 ms（第4档）。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "bend", name: "弯音", key: "← / →", detail: "按住 ±2 半音，松开回中；不是滑音开关。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "vibrato", name: "颤音", key: "F10（按住）", detail: "5 Hz / ±50 音分，按住开启。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "palm-mute", name: "吉他掌根闷音", key: "左Ctrl", detail: "左Ctrl 只作用吉他；与右Ctrl 钢琴踏板分开。", localPreview: "仅键位参考")
            ]
        ),
        FPGAControlGroup(
            id: "piano",
            title: "钢琴",
            rows: [
                FPGAControlRow(id: "pedal-mode", name: "钢琴踏板模式", key: "F7", detail: "切换踏板模式，上电关闭。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "pedal", name: "延音踏板", key: "右Ctrl（按住）", detail: "按住时延迟释放已松键；松开后释放。左Ctrl 不参与钢琴。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "release", name: "普通松键", key: "松开琴键", detail: "无踏板时不额外释放，按声部自然衰减。", localPreview: "本地自然衰减")
            ]
        ),
        FPGAControlGroup(
            id: "tone",
            title: "音色与总输出",
            rows: [
                FPGAControlRow(id: "fx", name: "清音 / 过载", key: "F3", detail: "切换吉他清音与过载音色。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "reverb", name: "混响", key: "F4", detail: "切换吉他混响，默认旁路。", localPreview: "仅键位参考"),
                FPGAControlRow(id: "vol-down", name: "总音量减", key: "F8", detail: "17 档，每档 1/16，按下沿一步。", localPreview: "本地音量滑杆"),
                FPGAControlRow(id: "vol-up", name: "总音量加", key: "F9", detail: "17 档，每档 1/16，按下沿一步。", localPreview: "本地音量滑杆"),
                FPGAControlRow(id: "space", name: "制音", key: "Space", detail: "停止当前本地声音；FPGA 侧为全局制音。", localPreview: "本地停止声音"),
                FPGAControlRow(id: "esc", name: "全部停止", key: "Esc", detail: "紧急停止全部声音并清理，不重放旧事件。", localPreview: "本地全部停止"),
                FPGAControlRow(id: "demo", name: "吉他演示2", key: "F6", detail: "FPGA 内部演示；本 App 自由演奏不提供该入口。", localPreview: "未接入本地")
            ]
        )
    ]

    static let localPreviewNote = "键位来自当前 FPGA RTL，用于触屏对照；本机未实现 iPad 实体 USB 键盘输入。"
}