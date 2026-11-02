import Foundation
import SwiftUI

enum ConcertStagePets {
    static func drawSpotlights(
        context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        floorY: CGFloat,
        section: ConcertSection,
        time: TimeInterval,
        pianoActive: Bool,
        guitarActive: Bool,
        drumsActive: Bool,
        latestPiano: ConcertEvent?,
        latestGuitar: ConcertEvent?,
        latestDrums: ConcertEvent?,
        reduceMotion: Bool
    ) {
        let groupXs: [CGFloat] = [width * 0.18, width * 0.50, width * 0.82]
        let colors: [Color] = [PaperPalette.red, PaperPalette.green, PaperPalette.blue]
        let active: [Bool] = [pianoActive, guitarActive, drumsActive]
        let latest: [ConcertEvent?] = [latestPiano, latestGuitar, latestDrums]
        let sectionBoost: Double = section.id >= 3 ? 0.10 : (section.id == 2 ? 0.05 : 0.02)
        let elapsed: Double = time - section.start

        for index in 0..<3 {
            var intensity: Double = 0.035 + sectionBoost
            if active[index] { intensity += 0.055 }
            if let event = latest[index] { intensity += event.velocity * 0.035 }
            if !reduceMotion && elapsed >= 0 && elapsed < 0.7 {
                intensity += (1.0 - elapsed / 0.7) * 0.04
            }
            intensity = min(max(intensity, 0.02), 0.14)

            let x: CGFloat = groupXs[index]
            var beam = Path()
            beam.move(to: CGPoint(x: x - width * 0.026, y: 0))
            beam.addLine(to: CGPoint(x: x + width * 0.026, y: 0))
            beam.addLine(to: CGPoint(x: x + width * 0.12, y: floorY))
            beam.addLine(to: CGPoint(x: x - width * 0.12, y: floorY))
            beam.closeSubpath()
            context.fill(beam, with: .color(colors[index].opacity(intensity)))

            let pool = CGRect(
                x: x - width * 0.105,
                y: floorY - height * 0.012,
                width: width * 0.21,
                height: height * 0.024
            )
            context.fill(
                Path(ellipseIn: pool),
                with: .color(colors[index].opacity(intensity * 0.95))
            )
        }
    }

    static func drawPets(
        context: inout GraphicsContext,
        width: CGFloat,
        height: CGFloat,
        floorY: CGFloat,
        scale: CGFloat,
        time: TimeInterval,
        pianoActive: Bool,
        guitarActive: Bool,
        drumsActive: Bool,
        latestPiano: ConcertEvent?,
        latestGuitar: ConcertEvent?,
        latestDrums: ConcertEvent?,
        reduceMotion: Bool,
        finished: Bool
    ) {
        let bob: CGFloat = reduceMotion ? 0 : CGFloat(sin(time * 1.7)) * scale * 0.004
        drawInstrument(
            context: &context,
            imageName: "piano-line",
            centerX: width * 0.18,
            floorY: floorY + bob,
            width: min(width * 0.22, scale * 0.28),
            active: pianoActive,
            latest: latestPiano,
            time: time,
            reduceMotion: reduceMotion,
            finished: finished
        )
        drawInstrument(
            context: &context,
            imageName: "guitar-line",
            centerX: width * 0.50,
            floorY: floorY + bob,
            width: min(width * 0.19, scale * 0.24),
            active: guitarActive,
            latest: latestGuitar,
            time: time,
            reduceMotion: reduceMotion,
            finished: finished
        )
        drawInstrument(
            context: &context,
            imageName: "drums-line",
            centerX: width * 0.82,
            floorY: floorY + bob,
            width: min(width * 0.22, scale * 0.28),
            active: drumsActive,
            latest: latestDrums,
            time: time,
            reduceMotion: reduceMotion,
            finished: finished
        )
    }

    private static func drawInstrument(
        context: inout GraphicsContext,
        imageName: String,
        centerX: CGFloat,
        floorY: CGFloat,
        width: CGFloat,
        active: Bool,
        latest: ConcertEvent?,
        time: TimeInterval,
        reduceMotion: Bool,
        finished: Bool
    ) {
        guard width > 1 else { return }
        let height = width * 0.656
        let pulse: CGFloat = active && !reduceMotion
            ? CGFloat(0.5 + 0.5 * sin(time * 5.5))
            : 0
        let eventLift: CGFloat = latest.map { CGFloat($0.velocity) * width * 0.012 } ?? 0
        let rect = CGRect(
            x: centerX - width / 2,
            y: floorY - height + 8 - eventLift,
            width: width,
            height: height
        )

        let pool = CGRect(
            x: centerX - width * 0.42,
            y: floorY - 2,
            width: width * 0.84,
            height: width * 0.055
        )
        context.fill(
            Path(ellipseIn: pool),
            with: .color(PaperPalette.pencil.opacity(0.20 + Double(pulse) * 0.10))
        )

        context.opacity = 0.90 + Double(pulse) * 0.10
        if let image = PaperOrbitMedia.image(named: imageName) {
            context.draw(image, in: rect)
        }
        context.opacity = 1.0

        if finished {
            let dot = CGRect(
                x: centerX - 3,
                y: rect.minY - 13,
                width: 6,
                height: 6
            )
            context.fill(Path(ellipseIn: dot), with: .color(PaperPalette.red.opacity(0.72)))
        }
    }
}