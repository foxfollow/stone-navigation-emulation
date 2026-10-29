import Foundation

/// Шматок маршруту, для якого запитуємо орієнтири окремим запитом до MapKit.
public enum LandmarkArea: Hashable, Sendable {
    /// Вікно `LandmarkPlanner.windowLength` метрів від початку маршруту.
    case window(Int)
    /// Половина вікна (0 або 1): вікно, де MapKit віддав повну відповідь, запитуємо ще й половинами.
    case half(Int, Int)
    /// Підʼїзд до маневру з цим `Maneuver.id` і сам поворот.
    case turn(Int)
}

/// Один запит орієнтирів: ділянка, її межі вздовж маршруту і типи, яких там ще немає.
public struct LandmarkRequest: Sendable, Equatable {
    public let area: LandmarkArea
    public let range: ClosedRange<Double>
    public let categories: Set<PlaceCategory>
}

/// Планує запити орієнтирів. MapKit на один запит віддає обмежену кількість місць на весь регіон,
/// тож маршрут запитуємо невеликими шматками, по одному запиту за раз, найважливіші першими:
/// 1. вікно, де я зараз, і підʼїзд до найближчого повороту;
/// 2. усе в межах `nearHorizon` попереду (вікна і повороти, ближчі першими), тож поруч орієнтири оновлюються весь час;
/// 3. вікно позаду: якщо розрахункова точка забігла вперед, орієнтир позаду допоможе її виправити;
/// 4. ділянка наперед за специфікацією: поточна ділянка, а наступна, коли пройдено половину поточної.
///    Так орієнтири вже є, коли в тунелі зникнуть GPS і мережа.
public enum LandmarkPlanner {
    /// Довжина вікна одного запиту, метри.
    public static let windowLength = 500.0
    /// Скільки метрів попереду тримати завантаженими весь час.
    public static let nearHorizon = 2000.0
    /// Підʼїзд до повороту: стільки метрів до нього…
    public static let turnApproach = 250.0
    /// …і стільки після.
    public static let turnExit = 100.0
    /// Від стількох місць у відповіді вважаємо, що MapKit обрізав список, і запитуємо вікно половинами.
    public static let denseThreshold = 20
    /// Шматок коротший за це в кінці маршруту не запитуємо: це похибка обчислення довжини, а не дорога.
    static let minimumLength = 1.0

    public static func tile(for along: Double, segmentLength: Double) -> Int {
        guard segmentLength > 0 else { return 0 }
        return max(0, Int((along / segmentLength).rounded(.down)))
    }

    public static func range(of tile: Int, segmentLength: Double, routeLength: Double) -> ClosedRange<Double> {
        let start = min(Double(tile) * segmentLength, routeLength)
        return start...min(start + segmentLength, routeLength)
    }

    /// Ділянки наперед за специфікацією: поточна, і наступна, коли пройдено половину поточної.
    public static func prefetchTiles(along: Double, routeLength: Double, segmentLength: Double) -> [Int] {
        guard routeLength > 0, segmentLength > 0 else { return [] }
        let current = tile(for: min(along, routeLength), segmentLength: segmentLength)
        let halfway = Double(current) * segmentLength + segmentLength / 2
        let next = current + 1
        guard along >= halfway, Double(next) * segmentLength < routeLength else { return [current] }
        return [current, next]
    }

    /// Вікна ділянки (номери від початку маршруту): спершу від поточної позиції вперед, потім ті, що позаду.
    public static func windows(of tile: Int, segmentLength: Double, routeLength: Double, along: Double, windowLength: Double = windowLength) -> [Int] {
        guard windowLength > 0 else { return [] }
        let segment = range(of: tile, segmentLength: segmentLength, routeLength: routeLength)
        let first = Int((segment.lowerBound / windowLength).rounded(.up))
        var all: [Int] = []
        var window = first
        while Double(window) * windowLength < segment.upperBound - minimumLength {
            all.append(window)
            window += 1
        }
        let current = Int((along / windowLength).rounded(.down))
        return all.filter { $0 >= current } + all.filter { $0 < current }
    }

    public static func range(ofWindow window: Int, routeLength: Double, windowLength: Double = windowLength) -> ClosedRange<Double> {
        let start = min(Double(window) * windowLength, routeLength)
        return start...min(start + windowLength, routeLength)
    }

    public static func window(at along: Double) -> Int {
        max(0, Int((along / windowLength).rounded(.down)))
    }

    /// Межі ділянки вздовж маршруту.
    public static func range(of area: LandmarkArea, route: Route) -> ClosedRange<Double> {
        let length = route.polyline.length
        switch area {
        case .window(let window):
            return range(ofWindow: window, routeLength: length)
        case let .half(window, part):
            let half = windowLength / 2
            let start = min(Double(window) * windowLength + Double(part) * half, length)
            return start...min(start + half, length)
        case .turn(let id):
            let along = route.maneuvers.first { $0.id == id }?.along ?? 0
            return max(0, along - turnApproach)...min(length, along + turnExit)
        }
    }

    /// Маневри, біля яких варто знати орієнтири: повороти і пункт призначення.
    static func turns(of route: Route) -> [Maneuver] {
        route.maneuvers.filter { $0.isTurn || $0.isArrival }
    }

    /// Усі ділянки, які мають бути завантажені зараз, найважливіші першими.
    /// `denseWindows`: вікна, де MapKit віддав повну відповідь; після них ідуть їхні половини.
    public static func areas(along: Double, route: Route, segmentLength: Double, denseWindows: Set<Int> = []) -> [LandmarkArea] {
        let length = route.polyline.length
        guard length > 0 else { return [] }
        var result: [LandmarkArea] = []
        var seen = Set<LandmarkArea>()
        func add(_ area: LandmarkArea) {
            guard seen.insert(area).inserted else { return }
            result.append(area)
            if case .window(let window) = area, denseWindows.contains(window) {
                add(.half(window, 0))
                add(.half(window, 1))
            }
        }
        let current = window(at: min(along, length))
        let turnsAhead = turns(of: route).filter { $0.along + turnExit > along }

        // 1. Де я зараз і найближчий поворот.
        add(.window(current))
        if let next = turnsAhead.first { add(.turn(next.id)) }

        // 2. Усе в межах nearHorizon попереду, ближчі першими.
        let nearEnd = min(along + nearHorizon, length)
        var near: [(start: Double, area: LandmarkArea)] = []
        var window = current + 1
        while Double(window) * windowLength < nearEnd - minimumLength {
            near.append((Double(window) * windowLength, .window(window)))
            window += 1
        }
        for turn in turnsAhead where turn.along - turnApproach < nearEnd {
            near.append((turn.along - turnApproach, .turn(turn.id)))
        }
        near.sorted { $0.start < $1.start }.forEach { add($0.area) }

        // 3. Вікно позаду.
        if current > 0 { add(.window(current - 1)) }

        // 4. Ділянка наперед: повороти, потім вікна (без тих, що вже далеко позаду).
        for tile in prefetchTiles(along: along, routeLength: length, segmentLength: segmentLength) {
            let tileRange = range(of: tile, segmentLength: segmentLength, routeLength: length)
            turnsAhead.filter { tileRange.contains($0.along) }.forEach { add(.turn($0.id)) }
            windows(of: tile, segmentLength: segmentLength, routeLength: length, along: along)
                .filter { $0 >= current - 1 }
                .forEach { add(.window($0)) }
        }
        return result
    }

    /// Наступний запит: перша за важливістю ділянка, де ще немає якогось із потрібних типів.
    public static func next(
        along: Double,
        route: Route,
        segmentLength: Double,
        categories: Set<PlaceCategory>,
        loaded: [LandmarkArea: Set<PlaceCategory>],
        denseWindows: Set<Int> = []
    ) -> LandmarkRequest? {
        guard !categories.isEmpty else { return nil }
        for area in areas(along: along, route: route, segmentLength: segmentLength, denseWindows: denseWindows) {
            let missing = categories.subtracting(loaded[area] ?? [])
            if !missing.isEmpty {
                return LandmarkRequest(area: area, range: range(of: area, route: route), categories: missing)
            }
        }
        return nil
    }

    /// Скільки метрів попереду завантажено суцільно для всіх `categories` (вікнами), до кінця маршруту.
    public static func coverageAhead(along: Double, route: Route, categories: Set<PlaceCategory>, loaded: [LandmarkArea: Set<PlaceCategory>]) -> Double {
        let length = route.polyline.length
        var window = window(at: min(along, length))
        while Double(window) * windowLength < length - minimumLength, categories.isSubset(of: loaded[.window(window)] ?? []) {
            window += 1
        }
        return max(0, min(Double(window) * windowLength, length) - along)
    }
}
