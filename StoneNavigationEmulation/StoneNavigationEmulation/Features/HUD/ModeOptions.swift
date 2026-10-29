import NavigationCore
import SwiftUI

/// Вибір режиму позиції: тап по індикатору вгорі (працює і зі згорнутою панеллю) або «Перейти на GPS»,
/// коли GPS непридатний. Перейти на GPS можна завжди: якщо сигнал поганий, «Все одно вести за GPS».
struct ModeOptionsDialog: ViewModifier {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        @Bindable var app = app
        let engine = session.engine
        let availability = session.gpsAvailability
        content.confirmationDialog("Режим позиції", isPresented: $app.showModeOptions, titleVisibility: .visible) {
            switch engine.mode {
            case .deadReckoning:
                if availability == .usable {
                    Button("Перейти на GPS") { session.selectGPS() }
                        .accessibilityIdentifier("mode.option.gps")
                } else {
                    Button("Все одно вести за GPS") { session.forceGPS() }
                        .accessibilityIdentifier("mode.option.forceGPS")
                    if engine.control == .manualDeadReckoning {
                        Button("Повернутися на GPS, коли стане точним") { session.selectGPS() }
                            .accessibilityIdentifier("mode.option.autoGPS")
                    }
                }
            case .gps:
                Button("Розрахункова позиція") { session.selectDeadReckoning() }
                    .accessibilityIdentifier("mode.option.deadReckoning")
                if engine.control == .manualGPS {
                    Button("Автоматичне перемикання") { session.selectGPS() }
                        .accessibilityIdentifier("mode.option.auto")
                }
            }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text(message(engine, availability: availability))
        }
    }

    private func message(_ engine: NavigationEngine, availability: GPSAvailability) -> String {
        let status = Self.status(availability)
        switch engine.mode {
        case .deadReckoning where availability != .usable:
            return "\(status). «Все одно вести за GPS»: точка йде за GPS і сама на розрахункову не переходить, доки не перемкнете."
        case .gps where engine.control == .manualGPS:
            return "\(status). GPS увімкнено вручну. «Автоматичне перемикання» знову вмикає розрахункову, коли GPS зникне чи стане неточним."
        default:
            return status
        }
    }

    static func status(_ availability: GPSAvailability) -> String {
        switch availability {
        case .usable: "GPS точний"
        case .poorAccuracy(let accuracy?): "GPS неточний: ±\(Int(accuracy.rounded())) м"
        case .poorAccuracy(nil): "Точність GPS невідома"
        case .stale(let age): "Остання точка GPS \(age < 60 ? "\(Int(age)) с" : UkrainianFormat.timer(age)) тому"
        case .noSignal: "Немає жодної точки GPS"
        }
    }
}

extension View {
    func modeOptionsDialog() -> some View {
        modifier(ModeOptionsDialog())
    }
}
