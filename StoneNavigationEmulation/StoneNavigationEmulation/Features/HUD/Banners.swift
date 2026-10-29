import NavigationCore
import SwiftUI

/// Контекстні підказки під індикатором: перебудова маршруту, поворот за гіроскопом, голос, помилки.
struct StatusBanners: View {
    @Environment(NavigationSession.self) private var session

    var body: some View {
        let engine = session.engine
        VStack(alignment: .leading, spacing: 8) {
            if session.isRouting {
                banner(icon: "arrow.triangle.turn.up.right.circle", text: "Будую маршрут…", color: Palette.gps)
            }
            if let error = session.routeError {
                banner(icon: "exclamationmark.triangle.fill", text: error, color: Palette.danger)
                    .accessibilityIdentifier("route.error")
            }
            if engine.offRoute != nil, session.destination != nil {
                Button {
                    Task { await session.rebuildFromCurrentGPS() }
                } label: {
                    Label("Перебудувати маршрут від моєї позиції", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(BigButtonStyle(background: Palette.gps))
                .accessibilityIdentifier("route.rebuild")
            }
            if let suggestion = engine.turnSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Гіроскоп бачить поворот, а точка ще за \(UkrainianFormat.distance(suggestion.distance)) до нього")
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        Button("Підтягнути до повороту") { session.applyTurnSuggestion() }
                            .buttonStyle(BigButtonStyle(background: Palette.deadReckoning, foreground: .black, height: 52))
                            .accessibilityIdentifier("turn.snap")
                        Button {
                            session.dismissTurnSuggestion()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(BigButtonStyle(height: 52))
                        .frame(width: 60)
                        .accessibilityIdentifier("turn.dismiss")
                    }
                }
                .padding(10)
                .background(Palette.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
            }
            if session.isNavigating, session.settings[.voiceEnabled], !session.isVoiceAvailable {
                banner(
                    icon: "speaker.slash.fill",
                    text: "Немає українського голосу. Завантажте: Параметри → Універсальний доступ → Вміст, що озвучується → Голоси → Українська.",
                    color: Palette.deadReckoning
                )
                .accessibilityIdentifier("voice.hint")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func banner(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Palette.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Висота стеження кнопками «+» і «−»: щипок у стеженні теж її змінює, а кнопки працюють і однією рукою за кермом.
struct FollowZoomButtons: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let range = AppModel.followDistanceRange
        VStack(spacing: 0) {
            Button {
                app.zoomFollow(by: 0.5)
            } label: {
                Image(systemName: "plus").frame(width: 50, height: 46).contentShape(Rectangle())
            }
            .disabled(app.followDistance <= range.lowerBound)
            .accessibilityLabel("Наблизити")
            .accessibilityIdentifier("map.zoomIn")
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 28, height: 1)
            Button {
                app.zoomFollow(by: 2)
            } label: {
                Image(systemName: "minus").frame(width: 50, height: 46).contentShape(Rectangle())
            }
            .disabled(app.followDistance >= range.upperBound)
            .accessibilityLabel("Віддалити")
            .accessibilityIdentifier("map.zoomOut")
        }
        .buttonStyle(.plain)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(.white)
        .background(Palette.surface.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 2))
    }
}

/// Кнопки праворуч від карти: фільтри орієнтирів, список, компас, центрування, налаштування.
struct SideButtons: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app
    @Environment(SettingsModel.self) private var settingsModel

    var body: some View {
        let enabled = settingsModel.settings.enabledCategories
        VStack(spacing: 8) {
            // Фільтри орієнтирів за типами (такі самі перемикачі є в списку і в Налаштуваннях).
            Menu {
                CategoryToggles(identifierPrefix: "filter")
            } label: {
                // Заповнений значок: фільтри змінено порівняно зі стандартними.
                Image(systemName: enabled == NavigationSettings.standard.enabledCategories
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .buttonStyle(RoundIconButtonStyle(tint: Palette.success))
            // Меню не закривається після кожного перемикача: можна вибрати кілька типів поспіль.
            .menuActionDismissBehavior(.disabled)
            .accessibilityLabel("Фільтри орієнтирів")
            .accessibilityIdentifier("filters.menu")
            if session.isNavigating {
                Button {
                    app.showLandmarkList = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(RoundIconButtonStyle())
                .overlay(alignment: .topTrailing) {
                    if !session.landmarks.isEmpty {
                        Text("\(session.landmarks.count)")
                            .font(.caption2.bold())
                            .padding(5)
                            .background(Palette.danger, in: Capsule())
                            .offset(x: 5, y: -5)
                    }
                }
                .accessibilityLabel("Орієнтири")
                .accessibilityIdentifier("landmarks.list.button")
            }
            CompassButton()
            if !app.isFollowing {
                Button {
                    app.recenter()
                } label: {
                    Image(systemName: "location.north.line.fill")
                }
                .buttonStyle(RoundIconButtonStyle(tint: Palette.gps))
                .accessibilityLabel("Центрувати")
                .accessibilityIdentifier("map.recenter")
            }
            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(RoundIconButtonStyle())
            .accessibilityLabel("Налаштування")
            .accessibilityIdentifier("settings.button")
            if session.isNavigating {
                Button {
                    app.showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(RoundIconButtonStyle())
                .accessibilityLabel("Новий пункт призначення")
                .accessibilityIdentifier("search.button")
            }
        }
    }
}

/// Компас: «N» з червоною стрілкою показує, де північ на карті. Тап перемикає карту
/// між «північ зверху» і поворотом за напрямком руху.
struct CompassButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let heading = Int(app.cameraHeading.rounded()) % 360
        Button {
            app.toggleNorthUp()
        } label: {
            ZStack {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.danger)
                    .offset(y: -15)
                Text("N").font(.system(size: 18, weight: .heavy))
            }
            .rotationEffect(.degrees(-app.cameraHeading))
        }
        .buttonStyle(RoundIconButtonStyle(tint: app.isNorthUp ? Palette.gps : .white))
        .accessibilityLabel("Компас")
        .accessibilityValue("\(app.isNorthUp ? "північ зверху" : "за напрямком руху"), \(heading)°")
        .accessibilityHint("Перемкнути: північ зверху або за напрямком руху")
        .accessibilityIdentifier("map.compass")
    }
}
