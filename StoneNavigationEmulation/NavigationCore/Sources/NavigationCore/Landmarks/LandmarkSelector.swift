import Foundation

/// Лишає лише місця в коридорі від лінії маршруту і рахує бік дороги та відстань від неї.
public enum LandmarkSelector {
    public static func select(
        _ candidates: [PlaceCandidate],
        polyline: RoutePolyline,
        range: ClosedRange<Double>? = nil,
        corridor: Double
    ) -> [Landmark] {
        // Спершу дешева перевірка прямокутником навколо маршруту: місць у пам'яті можуть бути тисячі.
        let bounds = GeoRegion(covering: polyline.points, padding: corridor)
        var seen = Set<String>()
        var result: [Landmark] = []
        for candidate in candidates where seen.insert(candidate.id).inserted {
            guard bounds.contains(candidate.coordinate),
                  let projection = polyline.project(candidate.coordinate, in: range),
                  projection.offset <= corridor else { continue }
            result.append(Landmark(place: candidate, along: projection.along, offset: projection.offset, side: projection.side))
        }
        return result.sorted { $0.along < $1.along }
    }

    /// Орієнтир біля повороту шукаємо за стільки метрів до точки маневру…
    public static let turnBefore = 120.0
    /// …і стільки після неї.
    public static let turnAfter = 40.0

    /// Орієнтир, за яким видно поворот: найближчий до точки маневру вздовж дороги і до самої дороги.
    public static func nearTurn(_ landmarks: [Landmark], maneuver: Maneuver) -> Landmark? {
        let span = (maneuver.along - turnBefore)...(maneuver.along + turnAfter)
        return landmarks
            .filter { span.contains($0.along) }
            .min { score($0, maneuver) < score($1, maneuver) }
    }

    static func score(_ landmark: Landmark, _ maneuver: Maneuver) -> Double {
        abs(landmark.along - maneuver.along) + landmark.offset
    }

    /// З якого боку від значка на екрані писати підпис: з того, куди орієнтир відходить від дороги, щоб підпис
    /// не закривав лінію маршруту. Бік на екрані залежить від курсу дороги біля орієнтира і повороту карти.
    /// Якщо дорога на екрані йде майже горизонтально, орієнтир над або під лінією і підпис збоку її не закриває:
    /// тоді лишається бік дороги, як у списку.
    public static func labelSide(of landmark: Landmark, polyline: RoutePolyline, cameraHeading: Double) -> RoadSide {
        let outward = polyline.bearing(at: landmark.along) + (landmark.side == .left ? -90 : 90)
        let screenX = sin((outward - cameraHeading) * .pi / 180)
        guard abs(screenX) >= 0.25 else { return landmark.side }
        return screenX < 0 ? .left : .right
    }

    /// Значки на карті без накладання: спершу орієнтири біля поворотів (`priority`), далі найближчі попереду.
    /// Сусід ближчий за `spacing` метрів ховається (він є в списку орієнтирів).
    /// `sticky`: значки, що вже на карті, лишаються перед новими, доки не зостануться позаду:
    /// інакше значки мінялись би місцями щоразу, як сусід позаду зникає чи підвантажується нове місце.
    public static func pins(_ landmarks: [Landmark], along: Double, spacing: Double, maxCount: Int, priority: [Landmark] = [], sticky: Set<String> = []) -> [Landmark] {
        var shown: [Landmark] = []
        let kept = landmarks.filter { sticky.contains($0.id) }
        for landmark in priority + kept + landmarks where landmark.along >= along - 30 {
            guard shown.count < maxCount else { break }
            guard !shown.contains(where: { $0.id == landmark.id || Geo.distance($0.place.coordinate, landmark.place.coordinate) < spacing }) else { continue }
            shown.append(landmark)
        }
        return shown
    }
}
