import NavigationCore
import SwiftUI

/// Нижня панель: час прибуття і залишок, швидкість у колі з кнопками − і +, Пауза, Вперед/Назад, ручний перемикач.
/// Два ряди кнопок замість чотирьох, щоб карта лишалась на виду. Швидкість і зсув стоять біля краю під праву руку
/// (стандартно) або під ліву, як вибрано в Налаштуваннях.
/// Згортається до рядка з часом прибуття: тап по ручці або свайп униз, розгортається свайпом угору.
struct ControlPanel: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app
    @State private var confirmEnd = false

    /// Наскільки потягнути панель, щоб згорнути або розгорнути.
    static let swipeThreshold: CGFloat = 40
    /// Діаметр кола швидкості.
    static let speedDiameter: CGFloat = 76
    /// Висота кнопок у рядах панелі.
    static let rowHeight: CGFloat = 52
    /// Ширина вузьких кнопок: − і +, скидання швидкості.
    static let narrowWidth: CGFloat = 56
    /// Підписи кнопок панелі: дрібніші за великі кнопки на картках, в один рядок.
    static let buttonFont = Font.headline.weight(.bold)

    var body: some View {
        let engine = session.engine
        let settings = session.settings
        VStack(spacing: 0) {
            collapseHandle
            VStack(spacing: 8) {
                arrivalRow(engine)
                if !app.isPanelCollapsed {
                    controls(engine, settings: settings)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .background(Palette.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 24))
        // Великий системний шрифт не розсуває панель: підписи лишаються в один рядок, кнопки в два ряди.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height > Self.swipeThreshold {
                    app.isPanelCollapsed = true
                } else if value.translation.height < -Self.swipeThreshold {
                    app.isPanelCollapsed = false
                }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: app.isPanelCollapsed)
        .confirmationDialog("Завершити навігацію?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Завершити", role: .destructive) { app.endNavigation() }
            Button("Продовжити", role: .cancel) {}
        }
    }

    /// Кнопки під рядком прибуття: у розрахунковому режимі швидкість, пауза і зсув, на GPS перемикач.
    /// Під праву руку швидкість і зсув праворуч, Пауза і GPS ліворуч; під ліву навпаки.
    @ViewBuilder
    private func controls(_ engine: NavigationEngine, settings: NavigationSettings) -> some View {
        let isLeftHanded = app.isLeftHanded
        if engine.mode == .deadReckoning {
            let step = Int(settings[.speedStepKmh])
            let shift = Int(settings[.shiftStepMeters])
            HStack(spacing: 8) {
                if isLeftHanded {
                    speedButtons(engine, step: step)
                    motionButton(engine)
                } else {
                    motionButton(engine)
                    speedButtons(engine, step: step)
                }
            }
            HStack(spacing: 8) {
                if isLeftHanded {
                    shiftButtons(shift)
                    resetButton(engine)
                    gpsButton(engine)
                } else {
                    gpsButton(engine)
                    resetButton(engine)
                    shiftButtons(shift)
                }
            }
        } else {
            HStack(spacing: 8) {
                let circle = speedCircle(value: engine.currentGPSSpeed, subtitle: "з GPS", isManual: false)
                let button = Button("Розрахунковий режим") { session.selectDeadReckoning() }
                    .buttonStyle(panelStyle())
                    .accessibilityIdentifier("mode.switch")
                if isLeftHanded {
                    circle
                    button
                } else {
                    button
                    circle
                }
            }
        }
    }

    private func panelStyle(background: Color = Palette.surfaceRaised, foreground: Color = .white) -> BigButtonStyle {
        BigButtonStyle(background: background, foreground: foreground, height: Self.rowHeight, font: Self.buttonFont, lineLimit: 1)
    }

    /// −, швидкість у колі, +.
    @ViewBuilder
    private func speedButtons(_ engine: NavigationEngine, step: Int) -> some View {
        Button("−\(step)") { session.speedDown() }
            .buttonStyle(panelStyle())
            .frame(width: Self.narrowWidth)
            .accessibilityLabel("Мінус \(step) кілометрів на годину")
            .accessibilityIdentifier("speed.minus")
        speedCircle(
            value: engine.speedInfo.speed,
            subtitle: speedSubtitle(engine.speedInfo.source, engine: engine),
            isManual: engine.speedInfo.source == .manual
        )
        Button("+\(step)") { session.speedUp() }
            .buttonStyle(panelStyle())
            .frame(width: Self.narrowWidth)
            .accessibilityLabel("Плюс \(step) кілометрів на годину")
            .accessibilityIdentifier("speed.plus")
    }

    /// Назад і вперед по маршруту на крок зсуву.
    @ViewBuilder
    private func shiftButtons(_ shift: Int) -> some View {
        Button("← \(shift) м") { session.moveBack() }
            .buttonStyle(panelStyle())
            .accessibilityIdentifier("shift.back")
        Button("\(shift) м →") { session.moveForward() }
            .buttonStyle(panelStyle())
            .accessibilityIdentifier("shift.forward")
    }

    /// Скинути ручну швидкість: видно, лише коли швидкість задано кнопками.
    @ViewBuilder
    private func resetButton(_ engine: NavigationEngine) -> some View {
        if engine.reckoner.manualSpeed != nil {
            Button {
                session.resetSpeed()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(panelStyle())
            .frame(width: Self.narrowWidth)
            .accessibilityLabel("Скинути швидкість")
            .accessibilityIdentifier("speed.reset")
        }
    }

    private func gpsButton(_ engine: NavigationEngine) -> some View {
        Button {
            app.requestGPS()
        } label: {
            Label("GPS", systemImage: "location.fill")
        }
        .buttonStyle(panelStyle(background: Palette.gps.opacity(0.3)))
        .accessibilityLabel(engine.control == .manualDeadReckoning ? "Повернутися на GPS" : "Перейти на GPS")
        .accessibilityIdentifier("mode.switch")
    }

    /// Швидкість у колі: число, км/год і джерело (з маршруту, вручну, стоянка, пауза).
    private func speedCircle(value: Double?, subtitle: String, isManual: Bool) -> some View {
        let color = Palette.color(for: session.engine.mode)
        return VStack(spacing: -1) {
            Text(value.map { String(Int(($0 * 3.6).rounded())) } ?? "—")
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(value.map(UkrainianFormat.speed) ?? "невідомо")
                .accessibilityIdentifier("speed.value")
            Text("км/год")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .accessibilityHidden(true)
            // Нижній рядок коротший за діаметр: коло там вужче.
            Text(subtitle)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: Self.speedDiameter * 0.62)
                .foregroundStyle(isManual ? Palette.deadReckoning : Palette.secondaryText)
                .accessibilityIdentifier("speed.source")
        }
        .frame(width: Self.speedDiameter, height: Self.speedDiameter)
        .background(Color.black.opacity(0.45), in: Circle())
        .overlay(Circle().stroke(color.opacity(isManual ? 1 : 0.6), lineWidth: isManual ? 4 : 3))
    }

    /// Ручка на всю ширину: велика ціль для тапу за кермом.
    private var collapseHandle: some View {
        Button {
            app.isPanelCollapsed.toggle()
        } label: {
            Image(systemName: app.isPanelCollapsed ? "chevron.compact.up" : "chevron.compact.down")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.isPanelCollapsed ? "Розгорнути панель" : "Згорнути панель")
        .accessibilityIdentifier("panel.toggle")
    }

    private func arrivalRow(_ engine: NavigationEngine) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(session.estimatedArrival.map { UkrainianFormat.clockTime($0) } ?? "—")
                    .font(.title3.bold().monospacedDigit())
                    .fixedSize()
                Text("прибуття")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize()
                    .accessibilityIdentifier("arrival.caption")
            }
            Spacer(minLength: 4)
            // Довгий залишок дрібнішає, а не переносить «прибуття» на другий рядок.
            Text("\(UkrainianFormat.duration(engine.remainingTime ?? 0)) · \(UkrainianFormat.distance(engine.remainingDistance))")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("remaining.label")
                .accessibilityValue(String(Int(engine.remainingDistance.rounded())))
            Button {
                confirmEnd = true
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .frame(width: 36, height: 36)
                    .background(Palette.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Завершити навігацію")
            .accessibilityIdentifier("navigation.end")
        }
        .padding(.horizontal, 4)
    }

    /// «Пауза», «Далі» після паузи або «Рушити», коли датчики бачать стоянку і точка стоїть.
    private func motionButton(_ engine: NavigationEngine) -> some View {
        let reckoner = engine.reckoner
        let isStopped = reckoner.isPaused || reckoner.isStationary
        return Button(reckoner.isPaused ? "Далі" : reckoner.isStationary ? "Рушити" : "Пауза") {
            if !reckoner.isPaused, reckoner.isStationary {
                session.ignoreStationary()
            } else {
                session.togglePause()
            }
        }
        .buttonStyle(panelStyle(
            background: isStopped ? Palette.gps : Palette.deadReckoning,
            foreground: isStopped ? .white : .black
        ))
        .accessibilityHint(!reckoner.isPaused && reckoner.isStationary ? "Датчики бачать стоянку. Точка поїде, доки датчики не побачать рух" : "")
        .accessibilityIdentifier("pause.toggle")
    }

    private func speedSubtitle(_ source: SpeedSource, engine: NavigationEngine) -> String {
        if engine.reckoner.isPaused { return "пауза" }
        if engine.reckoner.isStationary { return "стоянка" }
        return source.title
    }
}
