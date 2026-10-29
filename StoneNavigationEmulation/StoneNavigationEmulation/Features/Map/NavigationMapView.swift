import MapKit
import NavigationCore
import SwiftUI

/// SwiftUI Map у темній темі без вбудованих POI. Маршрут через MapPolyline, моя позиція власною Annotation.
struct NavigationMapView: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app
    @State private var mapSize = CGSize(width: 400, height: 800)

    /// Наскільки близько до лінії (у точках екрана) треба тапнути, щоб переставити позицію.
    static let tapTolerance: CGFloat = 32
    /// Перетягування на стільки точок вимикає стеження: менший зсув це тремтіння пальця під час тапу чи щипка.
    static let dragToUnfollow: CGFloat = 24

    var body: some View {
        @Bindable var app = app
        let engine = session.engine
        // Плавна позиція з кадрів екрана; поки кадрів ще не було, позиція рушія.
        let along = app.displayAlong ?? engine.displayAlong(at: session.now)
        // Лінію ділимо на пройдене і попереду за позицією рушія (раз на оновлення): лінії, що змінюються
        // щокадру, MapKit не встигає намалювати. Різницю в кілька метрів ховає коло значка позиції.
        let split = engine.displayAlong(at: session.now)
        let isDeadReckoning = engine.mode == .deadReckoning
        let mapSize = mapSize

        MapReader { proxy in
            Map(position: $app.camera, interactionModes: app.mapInteractions) {
                if let route = engine.route {
                    // Лінія суцільна: пунктир MapKit малює товстими штрихами різної довжини на вигинах.
                    // Розрахунковий режим видно з кольору лінії, ромба позиції та індикатора вгорі.
                    MapPolyline(coordinates: route.polyline.slice(0...split).map(\.cl))
                        .stroke(Color(white: 0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: route.polyline.slice(split...route.polyline.length).map(\.cl))
                        .stroke(Palette.color(for: engine.mode), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    Annotation("Пункт призначення", coordinate: route.destination.cl, anchor: .bottom) {
                        Image(systemName: "flag.checkered.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white, Palette.danger)
                    }
                    .annotationTitles(.hidden)
                }

                let atTurns = session.turnLandmarks(within: LandmarkPlanner.nearHorizon)
                let turnIDs = Set(atTurns.map(\.id))
                ForEach(app.landmarkPins(along: along, priority: atTurns)) { landmark in
                    let isAtTurn = turnIDs.contains(landmark.id)
                    let placement = LandmarkMarker.placement(
                        at: proxy.convert(landmark.place.coordinate.cl, to: .local),
                        preferred: engine.route.map {
                            LandmarkSelector.labelSide(of: landmark, polyline: $0.polyline, cameraHeading: app.cameraHeading)
                        } ?? landmark.side,
                        mapWidth: mapSize.width,
                        isAtTurn: isAtTurn
                    )
                    let marker = LandmarkMarker(
                        landmark: landmark,
                        distanceAhead: landmark.along - along,
                        isAtTurn: isAtTurn,
                        labelSide: placement.side,
                        maxTextWidth: placement.maxTextWidth,
                        isExpanded: app.expandedLandmarkNames.contains(landmark.id),
                        onSelect: { app.selectedLandmark = landmark },
                        onToggleName: { app.toggleLandmarkName(landmark.id) }
                    )
                    // Вістря трикутника точно на місці, хоч підпис і збоку.
                    Annotation(landmark.place.name, coordinate: landmark.place.coordinate.cl, anchor: marker.anchor) {
                        marker
                    }
                    .annotationTitles(.hidden)
                }

                if isDeadReckoning, let gps = engine.rawGPSCoordinate {
                    Annotation("GPS", coordinate: gps.cl) {
                        GhostGPSMarker(isSuspicious: engine.spoofPrompt != nil)
                    }
                    .annotationTitles(.hidden)
                }

                if let pending = app.pendingDestination {
                    Marker("Сюди?", systemImage: "mappin", coordinate: pending.coordinate.cl)
                        .tint(Palette.danger)
                }

                if let origin = app.plannedOrigin {
                    Marker("Звідси", systemImage: "location.circle", coordinate: origin.coordinate.cl)
                        .tint(Palette.success)
                }

                if let position = app.displayPosition {
                    Annotation("Моя позиція", coordinate: position.cl) {
                        PositionMarker(
                            mode: engine.mode,
                            rotation: (app.displayHeading ?? session.heading ?? 0) - app.cameraHeading,
                            following: app.isFollowing
                                ? "стежу, висота камери \(Int(app.followDistance.rounded())) м"
                                : "без стеження, висота камери \(Int((app.cameraDistance ?? 0).rounded())) м"
                        )
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {
                // Камера сама повертається за курсом; компас під статус-баром лише заважав би.
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                app.cameraHeading = context.camera.heading
                let span = context.region.span
                let metersPerPoint = min(
                    span.latitudeDelta * Self.metersPerDegree / max(mapSize.height, 1),
                    span.longitudeDelta * Self.metersPerDegree * cos(context.region.center.latitude * .pi / 180) / max(mapSize.width, 1)
                )
                app.mapScaleChanged(metersPerPoint: metersPerPoint)
                app.cameraChanged(context.camera)
                // Масштаб посередині екрана для перетягування, що вимикає стеження.
                let mid = CGPoint(x: mapSize.width / 2, y: mapSize.height / 2)
                if let center = proxy.convert(mid, from: .local),
                   let side = proxy.convert(CGPoint(x: mid.x + 100, y: mid.y), from: .local),
                   let below = proxy.convert(CGPoint(x: mid.x, y: mid.y + 100), from: .local) {
                    app.centerScale = (
                        Geo.distance(Coordinate(center), Coordinate(side)) / 100,
                        Geo.distance(Coordinate(center), Coordinate(below)) / 100
                    )
                }
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                self.mapSize = size
            }
            .onTapGesture(coordinateSpace: .local) { point in
                handleTap(at: point, proxy: proxy)
            }
            .simultaneousGesture(longPress(proxy: proxy))
        }
    }

    /// Значки на карті: спершу орієнтири біля поворотів у межах 2 км, далі найближчі попереду, без накладання.
    /// Сусід ближчий за `spacing` метрів ховається (він є в списку орієнтирів);
    /// `spacing` росте, коли карту віддалено, щоб підписи не налазили один на одний.
    static let maxPins = 12
    static let minPinSpacing = 80.0
    /// Скільки точок екрана тримати між значками.
    static let pinSpacingPoints = 72.0
    static let metersPerDegree = 111_320.0

    /// Тап по лінії маршруту миттєво переставляє позицію туди.
    private func handleTap(at point: CGPoint, proxy: MapProxy) {
        guard session.isNavigating, let route = session.engine.route,
              let tapped = proxy.convert(point, from: .local),
              let edge = proxy.convert(CGPoint(x: point.x + Self.tapTolerance, y: point.y), from: .local) else { return }
        let tolerance = Geo.distance(Coordinate(tapped), Coordinate(edge))
        guard let projection = route.polyline.project(Coordinate(tapped)), projection.offset <= tolerance else { return }
        session.setPosition(along: projection.along)
    }

    /// Довгий тап вибирає точку: картка внизу пропонує «Звідси» або «Сюди».
    private func longPress(proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.6)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      let coordinate = proxy.convert(drag.location, from: .local) else { return }
                app.pendingDestination = Place(name: "Вибрана точка", coordinate: Coordinate(coordinate))
            }
    }
}
