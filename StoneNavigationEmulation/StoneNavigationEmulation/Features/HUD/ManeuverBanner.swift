import NavigationCore
import SwiftUI

/// Наступний маневр: стрілка, відстань і вказівка MapKit.
/// Кнопка-шеврон або свайп угору згортає верхню панель до одного рядка (`CompactTopBar`).
struct ManeuverBanner: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        let engine = session.engine
        HStack(spacing: 14) {
            if engine.hasArrived {
                icon("flag.checkered")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ви прибули").font(.title.bold())
                    Text(session.destination?.name ?? "Пункт призначення").font(.headline).foregroundStyle(Palette.secondaryText)
                }
            } else if let next = engine.nextManeuver {
                icon(next.maneuver.direction.symbolName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(UkrainianFormat.distance(next.distance))
                        .font(.largeTitle.bold().monospacedDigit())
                        .accessibilityIdentifier("maneuver.distance")
                    Text(next.maneuver.spokenInstruction)
                        .font(.headline)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("maneuver.instruction")
                    if let landmark = session.nextTurnLandmark {
                        TurnLandmarkLabel(landmark: landmark)
                    }
                }
            } else {
                icon("arrow.up")
                Text("Рухайтеся маршрутом").font(.title3.bold())
            }
            Spacer(minLength: 0)
            Button {
                app.isTopBarCompact = true
            } label: {
                Image(systemName: "chevron.up")
                    .font(.headline.bold())
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Згорнути верхню панель")
            .accessibilityIdentifier("topbar.toggle")
        }
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .padding(.trailing, 4)
        .background(Palette.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height < -ControlPanel.swipeThreshold { app.isTopBarCompact = true }
            }
        )
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 30, weight: .bold))
            .frame(width: 58, height: 58)
            .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Значок, головний текст і пояснення наступного маневру для згорнутої панелі.
    static func summary(_ session: NavigationSession) -> (symbol: String, title: String, detail: String?) {
        let engine = session.engine
        if engine.hasArrived {
            return ("flag.checkered", "Ви прибули", session.destination?.name)
        }
        if let next = engine.nextManeuver {
            return (next.maneuver.direction.symbolName, UkrainianFormat.distance(next.distance), next.maneuver.spokenInstruction)
        }
        return ("arrow.up", "Рухайтеся маршрутом", nil)
    }
}

/// Орієнтир біля наступного повороту: за ним видно, де повертати.
struct TurnLandmarkLabel: View {
    let landmark: Landmark

    var body: some View {
        let category = landmark.place.category
        HStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Palette.color(for: category), in: Circle())
            Text("біля: \(landmark.place.shortName)")
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Орієнтир біля повороту: \(landmark.place.name)")
        .accessibilityIdentifier("maneuver.landmark")
    }
}

/// Згорнута верхня панель: один рядок із маневром і режимом позиції замість банера та індикатора.
/// Тап по рядку режиму відкриває вибір режиму, тап по решті, шеврон або свайп униз розгортає.
struct CompactTopBar: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        let engine = session.engine
        let color = Palette.color(for: engine.mode)
        let summary = ManeuverBanner.summary(session)
        HStack(spacing: 10) {
            Image(systemName: summary.symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 42, height: 42)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary.title)
                        .font(.title3.bold().monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityIdentifier("maneuver.distance")
                    if let detail = summary.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
                            .accessibilityIdentifier("maneuver.instruction")
                    }
                }
                modeLine(engine, color: color)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.headline.bold())
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .padding(.trailing, 4)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        .background(Palette.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { app.isTopBarCompact = false }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height > ControlPanel.swipeThreshold { app.isTopBarCompact = false }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Розгорнути верхню панель") { app.isTopBarCompact = false }
        .accessibilityIdentifier("topbar.compact")
    }

    /// Маркер режиму, назва і таймер «без GPS» або стан GPS. Тап відкриває вибір режиму.
    private func modeLine(_ engine: NavigationEngine, color: Color) -> some View {
        let isDeadReckoning = engine.mode == .deadReckoning
        return HStack(spacing: 5) {
            Image(systemName: isDeadReckoning ? "diamond.fill" : "location.fill")
                .font(.caption.bold())
            Text(isDeadReckoning ? "Розрахункова" : "GPS")
                .font(.subheadline.weight(.heavy))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(engine.mode.title)
                .accessibilityIdentifier("mode.indicator")
            if let status = status(engine) {
                Text(status)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isDeadReckoning ? color : Palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier(isDeadReckoning ? "mode.timer" : "mode.status")
            }
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
                .accessibilityHidden(true)
        }
        .foregroundStyle(color)
        .contentShape(Rectangle())
        .onTapGesture { app.showModeOptions = true }
        .accessibilityAction(named: "Змінити режим") { app.showModeOptions = true }
    }

    private func status(_ engine: NavigationEngine) -> String? {
        switch engine.mode {
        case .deadReckoning:
            let timer = "без GPS \(UkrainianFormat.timer(engine.timeWithoutGPS(at: session.now) ?? 0))"
            return engine.reckoner.isPaused ? "\(timer) · пауза" : timer
        case .gps:
            let status = ModeIndicatorView.gpsStatus(engine, now: session.now)
            guard engine.control == .manualGPS else { return status }
            return ["вручну", status].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
