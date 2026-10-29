import NavigationCore
import SwiftUI

/// Індикатор режиму вгорі: великий кольоровий маркер GPS / Розрахункова позиція і таймер «без GPS».
/// Тап відкриває вибір режиму, тож перемкнутися можна і зі згорнутою панеллю.
struct ModeIndicatorView: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        let engine = session.engine
        let isDeadReckoning = engine.mode == .deadReckoning
        let color = Palette.color(for: engine.mode)

        HStack(spacing: 12) {
            Image(systemName: isDeadReckoning ? "diamond.fill" : "location.fill")
                .font(.title.bold())
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(engine.mode.title)
                        .font(.title2.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("mode.indicator")
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.title3)
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(subtitle(engine))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .accessibilityIdentifier("mode.subtitle")
                    Spacer(minLength: 4)
                    if isDeadReckoning {
                        Text("без GPS \(UkrainianFormat.timer(engine.timeWithoutGPS(at: session.now) ?? 0))")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(color)
                            .fixedSize()
                            .accessibilityIdentifier("mode.timer")
                    } else if let status = Self.gpsStatus(engine, now: session.now) {
                        Text(status)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
        .background(Palette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { app.showModeOptions = true }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Змінити режим") { app.showModeOptions = true }
    }

    private func subtitle(_ engine: NavigationEngine) -> String {
        switch engine.mode {
        case .gps:
            if engine.offRoute != nil { return "GPS поза маршрутом" }
            return engine.control == .manualGPS ? "увімкнено вручну" : "прив'язано до дороги"
        case .deadReckoning:
            return engine.control == .manualDeadReckoning ? "увімкнено вручну" : engine.modeReason.title
        }
    }

    /// Точність GPS, а в ручному GPS без свіжих точок скільки їх немає
    /// (в автоматичному режимі на цей випадок уже вмикається розрахункова).
    static func gpsStatus(_ engine: NavigationEngine, now: Date) -> String? {
        if engine.control == .manualGPS {
            switch engine.gpsAvailability(at: now) {
            case .stale(let age): return "без точок \(UkrainianFormat.timer(age))"
            case .noSignal: return "немає сигналу"
            default: break
            }
        }
        guard let fix = engine.lastGoodFix else { return nil }
        return fix.hasValidAccuracy ? "±\(Int(fix.horizontalAccuracy.rounded())) м" : "точність невідома"
    }
}
