import Foundation
import Testing
@testable import NavigationCore

@Suite("Орієнтири в коридорі маршруту")
struct LandmarkTests {
    let route = TestRoute.make()

    func candidate(_ id: String, along: Double, offset: Double, category: PlaceCategory = .gasStation) -> PlaceCandidate {
        PlaceCandidate(id: id, name: "Місце \(id)", category: category, coordinate: TestRoute.point(along: along, offset: offset, route: route))
    }

    /// Межі збігаються з точністю до сантиметра: довжина маршруту рахується з координат.
    func close(_ range: ClosedRange<Double>, _ expected: ClosedRange<Double>) -> Bool {
        abs(range.lowerBound - expected.lowerBound) < 0.01 && abs(range.upperBound - expected.upperBound) < 0.01
    }

    var candidates: [PlaceCandidate] {
        [
            candidate("D", along: 1500, offset: 30, category: .store),
            candidate("A", along: 300, offset: -20),
            candidate("B", along: 600, offset: 45, category: .foodMarket),
            candidate("C", along: 700, offset: -80),
            PlaceCandidate(id: "E", name: "Далеко", category: .store, coordinate: Geo.destination(from: TestRoute.start, bearing: 270, distance: 1000)),
            candidate("A", along: 300, offset: -20),
        ]
    }

    @Test("Лишаються лише місця в коридорі 50 м, з боком дороги і відстанню від неї")
    func corridor() throws {
        let landmarks = LandmarkSelector.select(candidates, polyline: route.polyline, corridor: 50)
        #expect(landmarks.map(\.id) == ["A", "B", "D"])
        let a = try #require(landmarks.first { $0.id == "A" })
        #expect(a.side == .left)
        #expect(abs(a.offset - 20) < 0.5)
        #expect(abs(a.along - 300) < 0.5)
        let b = try #require(landmarks.first { $0.id == "B" })
        #expect(b.side == .right)
        #expect(abs(b.offset - 45) < 0.5)
        let d = try #require(landmarks.first { $0.id == "D" })
        #expect(d.side == .right)
        #expect(abs(d.along - 1500) < 0.5)
    }

    @Test("Ширший коридор додає дальші місця")
    func widerCorridor() {
        let landmarks = LandmarkSelector.select(candidates, polyline: route.polyline, corridor: 100)
        #expect(landmarks.map(\.id) == ["A", "B", "C", "D"])
    }

    @Test("Відбір у межах ділянки маршруту")
    func withinSegment() {
        let landmarks = LandmarkSelector.select(candidates, polyline: route.polyline, range: 0...1000, corridor: 50)
        #expect(landmarks.map(\.id) == ["A", "B"])
    }

    @Test("Ділянка наперед: поточна, а наступна, коли пройдено половину поточної")
    func prefetch() {
        let length = 25_000.0
        let segment = 10_000.0
        #expect(LandmarkPlanner.prefetchTiles(along: 0, routeLength: length, segmentLength: segment) == [0])
        #expect(LandmarkPlanner.prefetchTiles(along: 3000, routeLength: length, segmentLength: segment) == [0])
        #expect(LandmarkPlanner.prefetchTiles(along: 5000, routeLength: length, segmentLength: segment) == [0, 1])
        #expect(LandmarkPlanner.prefetchTiles(along: 9000, routeLength: length, segmentLength: segment) == [0, 1])
        #expect(LandmarkPlanner.prefetchTiles(along: 12_000, routeLength: length, segmentLength: segment) == [1])
        #expect(LandmarkPlanner.prefetchTiles(along: 15_000, routeLength: length, segmentLength: segment) == [1, 2])
        // Остання ділянка: наступної немає.
        #expect(LandmarkPlanner.prefetchTiles(along: 24_000, routeLength: length, segmentLength: segment) == [2])
    }

    @Test("Порядок запитів: де я, найближчий поворот, 2 км попереду, вікно позаду, далі ділянка наперед")
    func areaOrder() {
        // 6 км на північ, поворот праворуч (#1), 2 км на схід до пункту призначення (#2). Я на 1200 м.
        let route = TestRoute.turning(north: 6000, east: 2000)
        let areas = LandmarkPlanner.areas(along: 1200, route: route, segmentLength: 10_000)
        let expected: [LandmarkArea] = [.window(2), .turn(1), .window(3), .window(4), .window(5), .window(6), .window(1), .turn(2)]
            + (7...15).map { .window($0) }
        #expect(areas == expected)
        // Вікно, де MapKit віддав повну відповідь, далі запитуємо ще й половинами.
        let dense = LandmarkPlanner.areas(along: 1200, route: route, segmentLength: 10_000, denseWindows: [3])
        #expect(Array(dense.prefix(5)) == [.window(2), .turn(1), .window(3), .half(3, 0), .half(3, 1)])
        // Поворот позаду більше не запитуємо.
        #expect(!LandmarkPlanner.areas(along: 6200, route: route, segmentLength: 10_000).contains(.turn(1)))

        #expect(close(LandmarkPlanner.range(of: .turn(1), route: route), 5750...6100))
        #expect(close(LandmarkPlanner.range(of: .half(3, 1), route: route), 1750...2000))
        #expect(close(LandmarkPlanner.range(of: .turn(2), route: route), 7750...8000))
    }

    @Test("Наступний запит: перша ділянка, де бракує якогось типу, і лише ці типи")
    func nextRequest() throws {
        let route = TestRoute.turning(north: 6000, east: 2000)
        let all: Set<PlaceCategory> = [.gasStation, .store]
        var loaded: [LandmarkArea: Set<PlaceCategory>] = [.window(2): all]
        var next = try #require(LandmarkPlanner.next(along: 1200, route: route, segmentLength: 10_000, categories: all, loaded: loaded))
        #expect(next.area == .turn(1))
        #expect(close(next.range, 5750...6100))
        #expect(next.categories == all)

        // Водій увімкнув ще аптеки: там, де вже все є, просимо лише аптеки.
        next = try #require(LandmarkPlanner.next(along: 1200, route: route, segmentLength: 10_000, categories: all.union([.pharmacy]), loaded: loaded))
        #expect(next.area == .window(2))
        #expect(next.categories == [.pharmacy])

        #expect(LandmarkPlanner.next(along: 1200, route: route, segmentLength: 10_000, categories: [], loaded: loaded) == nil)
        for area in LandmarkPlanner.areas(along: 1200, route: route, segmentLength: 10_000) { loaded[area] = all }
        #expect(LandmarkPlanner.next(along: 1200, route: route, segmentLength: 10_000, categories: all, loaded: loaded) == nil)
    }

    @Test("Покриття попереду: до першого вікна, де бракує типів")
    func coverage() {
        let route = TestRoute.turning(north: 6000, east: 2000)
        let all: Set<PlaceCategory> = [.gasStation, .store]
        var loaded: [LandmarkArea: Set<PlaceCategory>] = [.window(2): all, .window(3): all, .window(4): [.gasStation]]
        #expect(LandmarkPlanner.coverageAhead(along: 1200, route: route, categories: all, loaded: loaded) == 800)
        #expect(LandmarkPlanner.coverageAhead(along: 1200, route: route, categories: [.gasStation], loaded: loaded) == 1300)
        for window in 0...15 { loaded[.window(window)] = all }
        #expect(abs(LandmarkPlanner.coverageAhead(along: 1200, route: route, categories: all, loaded: loaded) - 6800) < 0.01)
    }

    @Test("Орієнтир біля повороту: найближчий до точки маневру і до дороги")
    func nearTurn() throws {
        let route = TestRoute.turning(north: 6000, east: 2000)
        let turn = try #require(route.maneuvers.first { $0.isTurn })
        let landmarks = [
            Landmark(place: candidate("рано", along: 0, offset: 0), along: 5800, offset: 5, side: .right),
            Landmark(place: candidate("перед", along: 0, offset: 0), along: 5900, offset: 30, side: .right),
            Landmark(place: candidate("ріг", along: 0, offset: 0), along: 5990, offset: 10, side: .right),
            Landmark(place: candidate("після", along: 0, offset: 0), along: 6030, offset: 5, side: .left),
        ]
        #expect(LandmarkSelector.nearTurn(landmarks, maneuver: turn)?.id == "ріг")
        #expect(LandmarkSelector.nearTurn(Array(landmarks.prefix(1)), maneuver: turn) == nil)
    }

    @Test("Значки на карті: спершу біля поворотів, далі найближчі попереду, без накладання")
    func pins() {
        func landmark(_ id: String, _ along: Double) -> Landmark {
            Landmark(place: candidate(id, along: along, offset: 20), along: along, offset: 20, side: .right)
        }
        let all = [landmark("позаду", 100), landmark("a", 300), landmark("поруч-a", 320), landmark("b", 600), landmark("c", 900), landmark("поворот", 1950)]
        let pins = LandmarkSelector.pins(all, along: 250, spacing: 80, maxCount: 3, priority: [landmark("поворот", 1950)])
        #expect(pins.map(\.id) == ["поворот", "a", "b"])
        // Значок, що вже на карті, не поступається ближчому сусідові, який з'явився пізніше.
        let kept = LandmarkSelector.pins(all, along: 250, spacing: 80, maxCount: 3, sticky: ["поруч-a"])
        #expect(kept.map(\.id) == ["поруч-a", "b", "c"])
        // Позаду значок зникає, хоч і був на карті.
        #expect(!LandmarkSelector.pins(all, along: 400, spacing: 80, maxCount: 3, sticky: ["a"]).contains { $0.id == "a" })
    }

    @Test("Ділянку запитуємо вікнами по 500 м: спершу від позиції вперед, потім позаду")
    func windows() {
        #expect(LandmarkPlanner.windows(of: 0, segmentLength: 2000, routeLength: 25_000, along: 0) == [0, 1, 2, 3])
        #expect(LandmarkPlanner.windows(of: 1, segmentLength: 2000, routeLength: 25_000, along: 1500) == [4, 5, 6, 7])
        // Посеред ділянки: вікна попереду першими.
        #expect(LandmarkPlanner.windows(of: 0, segmentLength: 2000, routeLength: 25_000, along: 1200) == [2, 3, 0, 1])
        // Кінець маршруту обрізає останню ділянку і останнє вікно.
        #expect(LandmarkPlanner.windows(of: 12, segmentLength: 2000, routeLength: 25_000, along: 24_000) == [48, 49])
        #expect(LandmarkPlanner.range(ofWindow: 49, routeLength: 24_800) == 24_500...24_800)
        // Вікна всіх ділянок покривають маршрут без пропусків і повторів.
        let all = (0..<13).flatMap { LandmarkPlanner.windows(of: $0, segmentLength: 2000, routeLength: 25_000, along: 0) }
        #expect(all == Array(0..<50))
    }

    @Test("Регіон запиту покриває ділянку маршруту з запасом коридору")
    func region() {
        let region = route.polyline.region(for: 0...2000, padding: 50)
        #expect(region.contains(TestRoute.point(along: 300, offset: -45)))
        #expect(region.contains(TestRoute.end))
        #expect(!region.contains(Geo.destination(from: TestRoute.start, bearing: 270, distance: 200)))
    }

    @Test("Записані POI MapKit уздовж записаного маршруту")
    func recordedFixture() throws {
        let route = try Fixtures.route()
        let pois = try Fixtures.pois()
        #expect(!pois.isEmpty)
        let landmarks = LandmarkSelector.select(pois, polyline: route.polyline, corridor: NavigationSettings.standard[.landmarkCorridor])
        #expect(!landmarks.isEmpty)
        for landmark in landmarks {
            #expect(landmark.offset <= 50)
            #expect((0...route.polyline.length).contains(landmark.along))
        }
        #expect(landmarks.map(\.along) == landmarks.map(\.along).sorted())
        let wide = LandmarkSelector.select(pois, polyline: route.polyline, corridor: 2000)
        #expect(wide.count >= landmarks.count)
    }
}

@Suite("Орієнтири в сесії")
@MainActor
struct LandmarkSessionTests {
    /// Регіони запитів не повторюються.
    func uniqueRegions(_ regions: [GeoRegion]) -> Bool {
        regions.indices.allSatisfy { index in !regions[..<index].contains(regions[index]) }
    }

    @Test("Ділянка запитується один раз невеликими шматками, і в розрахунковому режимі")
    func requestsPerSegment() async {
        var settings = NavigationSettings()
        settings[.landmarkSegmentKm] = 2
        // 1000 м на північ і 1000 м на схід: 4 вікна по 500 м, поворот і пункт призначення.
        let candidates = [
            PlaceCandidate(id: "1", name: "АЗС", category: .gasStation, coordinate: TestRoute.point(along: 300, offset: 20)),
            PlaceCandidate(id: "2", name: "Магазин", category: .store, coordinate: TestRoute.point(along: 1500, offset: -30)),
        ]
        let h = SessionHarness(settings: settings, candidates: candidates)
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.location.send(.error(.locationUnknown))
        h.advance(1)
        await h.session.settle()
        #expect(h.places.poiRequests.count == 6)
        #expect(uniqueRegions(h.places.poiRequests))
        // Кожен регіон невеликий: вікно 500 м або підʼїзд до повороту плюс коридор, а не вся ділянка 1×1 км.
        for region in h.places.poiRequests {
            let diagonal = Geo.distance(
                Coordinate(latitude: region.minLatitude, longitude: region.minLongitude),
                Coordinate(latitude: region.maxLatitude, longitude: region.maxLongitude)
            )
            #expect(diagonal < 800)
        }
        // Другий запит: підʼїзд до повороту.
        #expect(h.places.poiRequests[1].contains(TestRoute.corner))
        #expect(h.session.landmarks.map(\.id) == ["1", "2"])
        #expect(h.session.engine.mode == .deadReckoning)
        for _ in 0..<60 { h.advance(1) }
        await h.session.settle()
        #expect(h.places.poiRequests.count == 6)
    }

    @Test("Орієнтири по всій ділянці, хоч MapKit на один запит віддає лише кілька місць")
    func landmarksAlongWholeSegment() async throws {
        let route = TestRoute.straight(length: 10_000)
        // АЗС кожні 250 м за 20 м від дороги: 40 місць на ділянці 10 км.
        let candidates = stride(from: 125.0, to: 10_000, by: 250).map { along in
            PlaceCandidate(id: "\(Int(along))", name: "АЗС \(Int(along))", category: .gasStation, coordinate: TestRoute.point(along: along, offset: 20, route: route))
        }
        let h = SessionHarness(route: route, candidates: candidates)
        // Один запит на всю ділянку дав би 3 місця біля її середини.
        h.places.maxResults = 3
        h.session.begin(route: route, destination: nil)
        h.advance(1)
        await h.session.settle()
        // 20 вікон і підʼїзд до пункту призначення.
        #expect(h.places.poiRequests.count == 21)
        #expect(uniqueRegions(h.places.poiRequests))
        #expect(h.session.landmarks.count == 40)
        let first = try #require(h.session.landmarks.first)
        let last = try #require(h.session.landmarks.last)
        #expect(first.along < 200)
        #expect(last.along > 9800)
        #expect(h.session.landmarkStatus.coverageAhead > 9900)
    }

    @Test("Поруч завжди завантажено 2 км попереду: запити йдуть услід за позицією, без повторів")
    func rollingHorizon() async {
        var settings = NavigationSettings()
        // Ділянка наперед лише 2 км, тож далі тримає саме горизонт 2 км.
        settings[.landmarkSegmentKm] = 2
        let route = TestRoute.straight(length: 10_000)
        let h = SessionHarness(settings: settings, route: route)
        h.session.begin(route: route, destination: nil)
        for along in stride(from: 0.0, through: 9000, by: 750) {
            h.session.setPosition(along: along)
            h.advance(1)
            await h.session.settle()
            let ahead = min(LandmarkPlanner.nearHorizon, route.polyline.length - h.session.engine.along)
            #expect(h.session.landmarkStatus.coverageAhead >= ahead - 1, "на \(Int(along)) м")
        }
        #expect(uniqueRegions(h.places.poiRequests))
        #expect(h.places.poiRequests.count <= 21)
    }

    @Test("Підʼїзд до найближчого повороту запитується одразу, навіть за 9 км, і орієнтир на ньому видно й чути")
    func turnLandmarkLoadedEarly() async throws {
        var settings = NavigationSettings()
        settings[.landmarkSegmentKm] = 2
        let route = TestRoute.turning(north: 9000, east: 1000)
        let corner = route.polyline.coordinate(at: 9000)
        let candidates = [
            PlaceCandidate(id: "ріг", name: "Біля повороту", category: .gasStation, coordinate: TestRoute.point(along: 8960, offset: 15, route: route)),
            PlaceCandidate(id: "далі", name: "Далеко від повороту", category: .gasStation, coordinate: TestRoute.point(along: 8500, offset: 15, route: route)),
        ]
        let h = SessionHarness(settings: settings, route: route, candidates: candidates)
        h.session.begin(route: route, destination: nil)
        h.advance(1)
        await h.session.settle()
        #expect(h.places.poiRequests.count >= 2)
        #expect(h.places.poiRequests[1].contains(corner))
        #expect(h.session.landmarks.map(\.id) == ["ріг"])
        #expect(h.session.nextTurnLandmark?.id == "ріг")

        // За 300 м до повороту голос називає орієнтир.
        h.session.setPosition(along: 8650)
        for _ in 0..<8 { h.advance(1) }
        let phrase = try #require(h.speech.spoken.last)
        #expect(phrase.hasPrefix("Через 300 метрів поверніть праворуч"), "\(phrase)")
        #expect(phrase.hasSuffix("Орієнтир: АЗС Біля повороту"), "\(phrase)")
    }

    @Test("Вікно з повною відповіддю MapKit дозапитується половинами")
    func denseWindowSplits() async {
        let route = TestRoute.straight(length: 2000)
        // 60 магазинів у першому вікні 500 м, а MapKit віддає 25 на запит.
        let candidates = (0..<60).map { index in
            let along = 4 + Double(index) * 8.2
            return PlaceCandidate(id: "\(index)", name: "Магазин \(index)", category: .store, coordinate: TestRoute.point(along: along, offset: index.isMultiple(of: 2) ? 15 : -15, route: route))
        }
        let h = SessionHarness(route: route, candidates: candidates)
        h.places.maxResults = 25
        h.session.begin(route: route, destination: nil)
        h.advance(1)
        await h.session.settle()
        #expect(uniqueRegions(h.places.poiRequests))
        // Одним запитом було б 25.
        #expect(h.session.landmarks.count >= 45)
    }

    @Test("Знайдені місця лишаються після перебудови маршруту, навіть без мережі")
    func candidatesSurviveRebuild() async {
        let candidates = [PlaceCandidate(id: "1", name: "АЗС", category: .gasStation, coordinate: TestRoute.point(along: 300, offset: 20))]
        let h = SessionHarness(candidates: candidates)
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.advance(1)
        await h.session.settle()
        #expect(h.session.landmarks.map(\.id) == ["1"])

        h.places.error = .failed("немає мережі")
        h.session.begin(route: TestRoute.make(id: "перебудований"), destination: nil)
        #expect(h.session.landmarks.map(\.id) == ["1"], "одразу, ще до запитів")
        h.advance(1)
        await h.session.settle()
        #expect(h.session.landmarks.map(\.id) == ["1"])
        #expect(h.session.landmarkStatus.lastError == "Немає відповіді: немає мережі")
        #expect(h.session.landmarkStatus.retryAt != nil)

        h.session.endNavigation()
        #expect(h.session.landmarks.isEmpty)
        #expect(h.session.landmarkCandidates.map(\.id) == ["1"])
    }

    @Test("«Оновити» заново запитує орієнтири поруч, а не весь маршрут; після збою мережі одразу, після обмеження MapKit ні")
    func manualRefresh() async throws {
        let route = TestRoute.straight(length: 10_000)
        let h = SessionHarness(route: route)
        h.session.begin(route: route, destination: nil)
        h.advance(1)
        await h.session.settle()
        #expect(h.places.poiRequests.count == 21)
        #expect(h.session.landmarkStatus.requests == 21)

        // Нове місце поруч з'явилося в MapKit.
        h.places.candidates = [PlaceCandidate(id: "нове", name: "АЗС", category: .gasStation, coordinate: TestRoute.point(along: 300, offset: 10, route: route))]
        h.session.refreshLandmarks()
        await h.session.settle()
        // Вікна 0–3 (2 км попереду) і підʼїзд до пункту призначення.
        #expect(h.places.poiRequests.count == 26)
        #expect(h.session.landmarks.map(\.id) == ["нове"])

        // Немає мережі: «Оновити» пробує одразу, не чекаючи backoff.
        h.places.error = .failed("немає мережі")
        h.session.refreshLandmarks()
        await h.session.settle()
        #expect(h.places.poiRequests.count == 27)
        #expect(h.session.landmarkStatus.retryAt != nil)
        h.places.error = nil
        h.session.refreshLandmarks()
        await h.session.settle()
        #expect(h.places.poiRequests.count == 32)
        #expect(h.session.landmarkStatus.lastError == nil)

        // MapKit обмежив запити: «Оновити» чекає, щоб не продовжити обмеження.
        h.places.error = .throttled(retryAfter: 30)
        h.session.refreshLandmarks()
        await h.session.settle()
        #expect(h.places.poiRequests.count == 33)
        h.places.error = nil
        h.session.refreshLandmarks()
        await h.session.settle()
        #expect(h.places.poiRequests.count == 33)
        #expect(h.session.notice?.text.hasPrefix("MapKit тимчасово обмежив запити") == true)
        h.advance(31)
        await h.session.settle()
        #expect(h.places.poiRequests.count == 38)
    }

    @Test("Після обмеження MapKit ділянка дозавантажується пізніше без повторних запитів готових шматків")
    func throttledSegmentResumes() async {
        var settings = NavigationSettings()
        settings[.landmarkSegmentKm] = 2
        let candidates = [
            PlaceCandidate(id: "1", name: "АЗС", category: .gasStation, coordinate: TestRoute.point(along: 300, offset: 20)),
            PlaceCandidate(id: "2", name: "Магазин", category: .store, coordinate: TestRoute.point(along: 1700, offset: -30)),
        ]
        let h = SessionHarness(settings: settings, candidates: candidates)
        h.places.error = .throttled(retryAfter: 5)
        h.places.errorFromRequest = 3
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.advance(1)
        await h.session.settle()
        // Вікно 0 і поворот відповіли, на третьому запиті (вікно 1) MapKit обмежив.
        #expect(h.places.poiRequests.count == 3)
        #expect(h.session.landmarks.map(\.id) == ["1"])
        #expect(h.session.landmarkStatus.lastError == "MapKit тимчасово обмежив запити")
        let throttledRegion = h.places.poiRequests[2]

        h.places.error = nil
        h.advance(2)
        await h.session.settle()
        #expect(h.places.poiRequests.count == 3, "до кінця очікування нових запитів немає")

        h.advance(4)
        await h.session.settle()
        // Повторюються лише вікна 1–3 і пункт призначення.
        #expect(h.places.poiRequests.count == 7)
        #expect(h.places.poiRequests[3] == throttledRegion)
        #expect(!h.places.poiRequests[3...].contains(h.places.poiRequests[0]))
        #expect(!h.places.poiRequests[3...].contains(h.places.poiRequests[1]))
        #expect(h.session.landmarks.map(\.id) == ["1", "2"])
        #expect(h.session.landmarkStatus.lastError == nil)
    }

    @Test("Запитуються лише увімкнені типи; увімкнений пізніше тип дозапитується, підтвердження ставить позицію на орієнтир")
    func filtersAndConfirm() async throws {
        let candidates = [
            PlaceCandidate(id: "1", name: "АЗС", category: .gasStation, coordinate: TestRoute.point(along: 300, offset: 20)),
            PlaceCandidate(id: "2", name: "Магазин", category: .store, coordinate: TestRoute.point(along: 800, offset: -30)),
        ]
        var settings = NavigationSettings()
        settings[.showStores] = false
        let h = SessionHarness(settings: settings, candidates: candidates)
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.advance(1)
        await h.session.settle()
        #expect(h.session.visibleLandmarks.map(\.id) == ["1"])
        #expect(h.places.poiCategories.allSatisfy { !$0.contains(.store) })
        let before = h.places.poiRequests.count

        settings[.showStores] = true
        h.session.apply(settings: settings)
        h.advance(1)
        await h.session.settle()
        #expect(h.session.visibleLandmarks.map(\.id) == ["1", "2"])
        // Дозапит лише магазинів, по одному на кожен шматок.
        #expect(h.places.poiCategories[before...].allSatisfy { $0 == [.store] })
        #expect(h.places.poiRequests.count == before * 2)

        let store = try #require(h.session.landmarks.first { $0.id == "2" })
        h.session.confirmLandmark(store)
        #expect(abs(h.session.engine.along - 800) < 0.5)
        #expect(h.session.notice?.text == "Позицію підтверджено орієнтиром")
    }

    @Test("Порожня відповідь MapKit («нічого не знайдено») не помилка: ділянка завантажена, повторів немає")
    func emptyAnswerIsNotFailure() async {
        var settings = NavigationSettings()
        settings[.landmarkSegmentKm] = 2
        let control = SessionHarness(settings: settings, candidates: [])
        control.session.begin(route: TestRoute.make(), destination: nil)
        control.advance(1)
        await control.session.settle()

        let h = SessionHarness(settings: settings, candidates: [])
        h.places.error = .notFound
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.advance(1)
        await h.session.settle()
        #expect(h.places.poiRequests.count == control.places.poiRequests.count)
        #expect(h.session.landmarkStatus.lastError == nil)
        #expect(h.session.landmarkStatus.failures == 0)
        #expect(h.session.landmarkStatus.retryAt == nil)
        #expect(h.session.landmarkStatus.coverageAhead == control.session.landmarkStatus.coverageAhead)
        #expect(h.session.landmarkStatus.coverageAhead > 1900)

        h.advance(30)
        await h.session.settle()
        #expect(h.places.poiRequests.count == control.places.poiRequests.count, "завантажені порожні ділянки не запитуються знову")
    }
}

@Suite("Коротка назва і підпис орієнтира на карті")
struct LandmarkLabelTests {
    @Test("Назва довша за три слова обрізається з «…», коротша лишається як є")
    func shortName() {
        #expect(LandmarkName.short("Товари для художників та творчості \"Майстриня\"") == "Товари для художників…")
        #expect(LandmarkName.short("Santechshara, Мир надежной сантехники") == "Santechshara, Мир надежной…")
        #expect(LandmarkName.short("Кафе, бар, ресторан, піцерія") == "Кафе, бар, ресторан…")
        // Тире і «&» між словами не рахуються словами.
        #expect(LandmarkName.short("Еко лавка - Натуральні продукти") == "Еко лавка - Натуральні…")
        #expect(LandmarkName.short("Сільпо & Ко - Центр") == "Сільпо & Ко - Центр")
        #expect(LandmarkName.short("Супер-пупер маркет Shket") == "Супер-пупер маркет Shket")
        #expect(LandmarkName.short("АЗС «WOG»") == "АЗС «WOG»")
        #expect(LandmarkName.short("АЗС «WOG» на Броварському проспекті") == "АЗС «WOG» на…")
        #expect(LandmarkName.isShortened("Sanahunt Luxury Concept Store"))
        #expect(!LandmarkName.isShortened("EVA.UA - EVA 315"))
        let place = PlaceCandidate(id: "1", name: "FLOWERS AND TEA SHOP", category: .store, coordinate: TestRoute.start)
        #expect(place.shortName == "FLOWERS AND TEA…")
    }

    func landmark(along: Double, offset: Double, route: Route) throws -> Landmark {
        let place = PlaceCandidate(id: "1", name: "Місце", category: .store, coordinate: TestRoute.point(along: along, offset: offset, route: route))
        return try #require(LandmarkSelector.select([place], polyline: route.polyline, corridor: 100).first)
    }

    @Test("Підпис з того боку екрана, куди орієнтир відходить від дороги, з урахуванням повороту карти")
    func labelSide() throws {
        // Маршрут: 1 км на північ, потім 1 км на схід.
        let route = TestRoute.make()
        let left = try landmark(along: 300, offset: -20, route: route)
        let right = try landmark(along: 600, offset: 30, route: route)
        #expect(left.side == .left && right.side == .right)
        // Карта за напрямком руху (на північ): бік на екрані збігається з боком дороги.
        #expect(LandmarkSelector.labelSide(of: left, polyline: route.polyline, cameraHeading: 0) == .left)
        #expect(LandmarkSelector.labelSide(of: right, polyline: route.polyline, cameraHeading: 0) == .right)
        // Карта повернута на південь: лівий орієнтир на екрані праворуч від лінії.
        #expect(LandmarkSelector.labelSide(of: left, polyline: route.polyline, cameraHeading: 180) == .right)
        #expect(LandmarkSelector.labelSide(of: right, polyline: route.polyline, cameraHeading: 180) == .left)

        // Після повороту на схід: за напрямком руху ліворуч лишається ліворуч.
        let eastLeft = try landmark(along: 1500, offset: -25, route: route)
        #expect(LandmarkSelector.labelSide(of: eastLeft, polyline: route.polyline, cameraHeading: 90) == .left)
        #expect(LandmarkSelector.labelSide(of: eastLeft, polyline: route.polyline, cameraHeading: 270) == .right)
        // Північ зверху: дорога на схід горизонтальна, орієнтир над лінією, лишається бік дороги.
        #expect(LandmarkSelector.labelSide(of: eastLeft, polyline: route.polyline, cameraHeading: 0) == .left)
    }
}
