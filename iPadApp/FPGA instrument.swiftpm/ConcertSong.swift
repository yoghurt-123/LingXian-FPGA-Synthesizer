import Foundation

enum ConcertInstrument: Equatable {
    case piano
    case guitar
    case drums
}

struct ConcertEvent: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let duration: TimeInterval
    let instrument: ConcertInstrument
    let value: Int
    let velocity: Double
}

struct ConcertSection: Identifiable, Equatable {
    let id: Int
    let start: TimeInterval
    let title: String
}

struct ConcertSong {
    let title: String
    let duration: TimeInterval
    let events: [ConcertEvent]
    let sections: [ConcertSection]

    static let builtIn = makeBuiltIn()

    func section(at time: TimeInterval) -> ConcertSection {
        var current: ConcertSection = sections.first ?? ConcertSection(id: 0, start: 0, title: "准备")
        for section in sections {
            if time >= section.start {
                current = section
            }
        }
        return current
    }

    private static func makeBuiltIn() -> ConcertSong {
        var events: [ConcertEvent] = []

        func add(
            time: TimeInterval,
            duration: TimeInterval,
            instrument: ConcertInstrument,
            value: Int,
            velocity: Double
        ) {
            events.append(
                ConcertEvent(
                    id: events.count,
                    time: time,
                    duration: duration,
                    instrument: instrument,
                    value: value,
                    velocity: velocity
                )
            )
        }

        let pianoPattern: [Int] = [0, 2, 4, 5, 4, 2, 1, 3]
        let guitarPattern: [Int] = [0, 2, 4, 5, 3, 1, 3, 5]
        let drumPattern: [Int] = [0, 2, 1, 2, 6, 2, 8, 4]

        for index in 0..<22 {
            let time: TimeInterval = 0.6 + Double(index) * 0.55
            let key: Int = pianoPattern[index % pianoPattern.count]
            let duration: TimeInterval = index % 7 == 0 ? 1.0 : 0.42
            let velocity: Double = 0.62 + Double(index % 4) * 0.09
            add(time: time, duration: duration, instrument: .piano, value: key, velocity: velocity)
        }

        for index in 0..<15 {
            let time: TimeInterval = 12.0 + Double(index) * 0.8
            let string: Int = guitarPattern[index % guitarPattern.count]
            let velocity: Double = 0.68 + Double(index % 3) * 0.10
            add(time: time, duration: 0.55, instrument: .guitar, value: string, velocity: velocity)
        }

        for index in 0..<20 {
            let time: TimeInterval = 24.0 + Double(index) * 0.6
            let drum: Int = drumPattern[index % drumPattern.count]
            let velocity: Double = 0.70 + Double(index % 4) * 0.07
            add(time: time, duration: 0.16, instrument: .drums, value: drum, velocity: velocity)
        }

        for index in 0..<22 {
            let time: TimeInterval = 36.0 + Double(index) * 0.5
            let key: Int = pianoPattern[(index + 2) % pianoPattern.count]
            let velocity: Double = 0.72 + Double(index % 4) * 0.07
            add(time: time, duration: 0.44, instrument: .piano, value: key, velocity: velocity)
        }

        for index in 0..<15 {
            let time: TimeInterval = 36.0 + Double(index) * 0.8
            let string: Int = guitarPattern[(index + 3) % guitarPattern.count]
            let velocity: Double = 0.72 + Double(index % 3) * 0.09
            add(time: time, duration: 0.50, instrument: .guitar, value: string, velocity: velocity)
        }

        for index in 0..<20 {
            let time: TimeInterval = 36.0 + Double(index) * 0.6
            let drum: Int = drumPattern[(index + 1) % drumPattern.count]
            let velocity: Double = 0.75 + Double(index % 4) * 0.06
            add(time: time, duration: 0.16, instrument: .drums, value: drum, velocity: velocity)
        }

        let finalPianoKeys: [Int] = [0, 2, 4]
        for key in finalPianoKeys {
            add(time: 48.2, duration: 5.2, instrument: .piano, value: key, velocity: 0.92)
        }
        add(time: 50.0, duration: 3.0, instrument: .piano, value: 7, velocity: 0.72)

        let finalGuitarStrings: [Int] = [0, 2, 4]
        for string in finalGuitarStrings {
            add(time: 48.8, duration: 4.5, instrument: .guitar, value: string, velocity: 0.88)
        }

        add(time: 48.2, duration: 0.16, instrument: .drums, value: DrumKitInstrument.crash.rawValue, velocity: 0.96)
        add(time: 50.0, duration: 0.16, instrument: .drums, value: DrumKitInstrument.kick.rawValue, velocity: 0.88)
        add(time: 53.0, duration: 0.16, instrument: .drums, value: DrumKitInstrument.crash.rawValue, velocity: 1.0)

        let sections: [ConcertSection] = [
            ConcertSection(id: 0, start: 0, title: "钢琴前奏"),
            ConcertSection(id: 1, start: 12, title: "电吉他加入"),
            ConcertSection(id: 2, start: 24, title: "鼓组进入"),
            ConcertSection(id: 3, start: 36, title: "三乐器合奏"),
            ConcertSection(id: 4, start: 48, title: "收尾")
        ]

        return ConcertSong(
            title: "橘色信号 · 纸上乐队练习曲",
            duration: 54.0,
            events: events,
            sections: sections
        )
    }
}