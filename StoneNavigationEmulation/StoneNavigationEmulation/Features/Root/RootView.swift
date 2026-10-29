import MapKit
import NavigationCore
import SwiftUI

struct RootView: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        ZStack {
            NavigationMapView()
                .ignoresSafeArea()
                // У стеженні MapKit лишається лише масштабування (`mapInteractions`): щипок тут теж змінює висоту
                // стеження, на випадок якщо жест MapKit не почнеться під камерою, що рухається; перетягування вимикає
                // стеження і зсуває карту. Без стеження ці жести нічого не роблять.
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in app.followPinchChanged(value.magnification) }
                        .onEnded { _ in app.followPinchEnded() }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: NavigationMapView.dragToUnfollow)
                        .onChanged { value in app.mapDragChanged(value.translation) }
                        .onEnded { _ in app.mapDragEnded() }
                )

            VStack(spacing: 8) {
                if session.isNavigating {
                    if app.isTopBarCompact {
                        CompactTopBar()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        ManeuverBanner()
                        ModeIndicatorView()
                    }
                } else {
                    SearchBarButton()
                }
                // Середня смуга забирає лише вільне місце: бічні кнопки прокручуються, якщо не влазять,
                // тож панель і банер ніколи не виходять за безпечну зону.
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusBanners()
                        Spacer(minLength: 0)
                        if session.isNavigating, app.isFollowing {
                            FollowZoomButtons()
                                .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 0)
                    ScrollView(.vertical, showsIndicators: false) {
                        SideButtons()
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 68)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                if let pending = app.pendingDestination {
                    PendingDestinationCard(place: pending)
                }
                if session.isNavigating {
                    ControlPanel()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            if let prompt = session.engine.spoofPrompt {
                SpoofPromptView(prompt: prompt)
                    .transition(.opacity)
            }
            if let toast = app.toast {
                ToastView(text: toast)
            }
            if app.isDimmed {
                DimmingOverlay()
            }
        }
        .background(TouchObserver { app.registerInteraction() })
        .animation(.easeInOut(duration: 0.25), value: session.engine.spoofPrompt != nil)
        .animation(.easeInOut(duration: 0.2), value: app.isTopBarCompact)
        .modeOptionsDialog()
        .sheet(item: $app.selectedLandmark) { landmark in
            LandmarkCardView(landmark: landmark)
        }
        .sheet(isPresented: $app.showLandmarkList) {
            LandmarkListView()
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $app.showSearch) {
            SearchView()
        }
        .onChange(of: scenePhase) { _, phase in
            app.scenePhaseChanged(phase)
        }
        .task {
            app.start()
        }
    }
}

/// Пошук пункту призначення, поки навігація не йде: капсула зі скла Liquid Glass.
/// Якщо вибрано точку відправлення, вона видна тут.
private struct SearchBarButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Button {
                app.showSearch = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Куди їдемо?").font(.title3.bold())
                        if let origin = app.plannedOrigin {
                            Label("Звідки: \(origin.name)", systemImage: "mappin.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(Palette.success)
                                .lineLimit(1)
                                .accessibilityIdentifier("origin.label")
                        } else {
                            Text("Або довгий тап на карті").font(.subheadline).foregroundStyle(Palette.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.button")
            if app.plannedOrigin != nil {
                Button {
                    app.plannedOrigin = nil
                } label: {
                    Image(systemName: "location.circle")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.gps)
                .accessibilityLabel("Від моєї позиції")
                .accessibilityIdentifier("origin.reset")
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, app.plannedOrigin == nil ? 22 : 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        // Системне напівпрозоре скло Liquid Glass: карту під рядком пошуку видно.
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Точка, вибрана довгим тапом: старт або пункт призначення.
/// Точка з довгого тапу по карті. Без навігації: «Звідси» або «Сюди». Під час навігації: «Я тут» (позиція на маршрут
/// навпроти точки), «Маршрут звідси» (звернув не туди) і «Сюди» (новий пункт призначення від моєї позиції).
private struct PendingDestinationCard: View {
    let place: Place
    @Environment(AppModel.self) private var app
    @Environment(NavigationSession.self) private var session

    var body: some View {
        let isNavigating = session.isNavigating && session.destination != nil
        let projection = isNavigating ? session.routeProjection(of: place.coordinate) : nil
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Точка на карті").font(.title3.bold())
                    Text(subtitle(projection))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityIdentifier("pending.where")
                }
                Spacer()
                Button {
                    app.pendingDestination = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.bold())
                        .frame(width: 44, height: 44)
                        .background(Palette.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Скасувати")
                .accessibilityIdentifier("pending.cancel")
            }
            if isNavigating {
                navigationActions(isNearRoute: projection.map { $0.offset <= NavigationSession.relocateTolerance } ?? false)
            } else {
                HStack(spacing: 10) {
                    Button {
                        app.plannedOrigin = place
                        app.pendingDestination = nil
                    } label: {
                        Label("Звідси", systemImage: "location.circle")
                    }
                    .buttonStyle(BigButtonStyle())
                    .accessibilityIdentifier("pending.origin")
                    goButton
                }
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private func navigationActions(isNearRoute: Bool) -> some View {
        Button {
            app.moveHere(place)
        } label: {
            Label("Я тут", systemImage: "location.fill")
        }
        .buttonStyle(BigButtonStyle(
            background: isNearRoute ? Palette.deadReckoning : Palette.surfaceRaised,
            foreground: isNearRoute ? .black : Palette.secondaryText,
            height: 52
        ))
        .disabled(!isNearRoute)
        .accessibilityHint(isNearRoute ? "Поставити позицію на маршрут навпроти цієї точки" : "Точка далеко від маршруту: прокладіть маршрут звідси")
        .accessibilityIdentifier("pending.here")
        HStack(spacing: 10) {
            Button {
                app.rebuildRoute(from: place)
            } label: {
                Label("Маршрут звідси", systemImage: "arrow.triangle.turn.up.right.diamond")
            }
            .buttonStyle(BigButtonStyle(height: 52))
            .accessibilityHint("Звернув не туди: перебудувати маршрут від цієї точки до того самого пункту призначення")
            .accessibilityIdentifier("pending.rebuild")
            goButton
        }
    }

    private var goButton: some View {
        Button {
            app.pendingDestination = nil
            Task { await app.go(to: place, remember: false) }
        } label: {
            Label("Сюди", systemImage: "flag.checkered")
        }
        .buttonStyle(BigButtonStyle(background: Palette.gps, height: session.isNavigating ? 52 : 60))
        .accessibilityIdentifier("pending.go")
    }

    /// Під час навігації: наскільки точка від маршруту і де вона вздовж нього; без навігації координати.
    private func subtitle(_ projection: RouteProjection?) -> String {
        guard let projection else {
            return String(format: "%.5f, %.5f", place.coordinate.latitude, place.coordinate.longitude)
        }
        let offset = UkrainianFormat.distance(projection.offset)
        guard projection.offset <= NavigationSession.relocateTolerance else {
            return "Далеко від маршруту: \(offset)"
        }
        let ahead = projection.along - session.engine.along
        let along = abs(ahead) < 10 ? "поруч" : ahead > 0 ? "через \(UkrainianFormat.distance(ahead))" : "позаду \(UkrainianFormat.distance(-ahead))"
        return projection.offset < 10 ? "На маршруті, \(along)" : "Біля маршруту, \(offset) від лінії, \(along)"
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Palette.success, in: Capsule())
                .padding(.bottom, 330)
                .accessibilityIdentifier("toast")
        }
        .allowsHitTesting(false)
    }
}
