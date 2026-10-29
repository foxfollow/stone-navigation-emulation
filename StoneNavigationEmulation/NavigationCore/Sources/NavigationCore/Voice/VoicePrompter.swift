import Foundation

/// Голосові тригери: кожен маневр озвучується один раз на кожній дистанції і на самому повороті.
public struct VoicePrompter: Sendable, Equatable {
    public static let arrivalPhrase = "Ви прибули до пункту призначення"

    private var spoken: Set<String> = []
    private var routeID: String?

    public init() {}

    public mutating func reset() {
        spoken.removeAll()
        routeID = nil
    }

    /// Фрази, які треба сказати зараз. `landmark` дає орієнтир біля повороту: його називаємо в попередніх підказках,
    /// щоб поворот було легше впізнати.
    public mutating func update(
        along: Double,
        route: Route,
        settings: NavigationSettings,
        landmark: (Maneuver) -> Landmark? = { _ in nil }
    ) -> [String] {
        let atTurn = settings[.voiceAtTurnDistance]
        let thresholds = Array(Set([settings[.voiceFarDistance], settings[.voiceNearDistance]].filter { $0 > atTurn })).sorted(by: >)

        if routeID != route.id {
            reset()
            routeID = route.id
            // Те, що вже позаду, не озвучуємо.
            for maneuver in route.maneuvers where maneuver.along <= along {
                markSpoken(maneuver, thresholds: thresholds)
            }
        }

        if route.polyline.length - along <= atTurn {
            return spoken.insert("arrival").inserted ? [Self.arrivalPhrase] : []
        }
        guard let maneuver = route.nextManeuver(after: along) else { return [] }

        let distance = maneuver.along - along
        if distance <= atTurn {
            let isNew = spoken.insert(key(maneuver, "now")).inserted
            markSpoken(maneuver, thresholds: thresholds)
            return isNew && !maneuver.isArrival ? [maneuver.spokenInstruction] : []
        }

        let crossed = thresholds.filter { distance <= $0 }
        guard let nearest = crossed.min(), !spoken.contains(key(maneuver, nearest)) else { return [] }
        for threshold in crossed { spoken.insert(key(maneuver, threshold)) }
        // Якщо точку пересунули всередину порогу, кажемо справжню відстань.
        let say = distance >= nearest - 25 ? nearest : max(10, (distance / 10).rounded() * 10)
        let phrase = "Через \(UkrainianFormat.spokenDistance(say)) \(UkrainianFormat.lowercasedFirst(maneuver.spokenInstruction))"
        guard maneuver.isTurn, let landmark = landmark(maneuver) else { return [phrase] }
        return ["\(phrase). Орієнтир: \(Self.name(of: landmark))"]
    }

    /// «АЗС WOG», або просто «Аптека», якщо в місця немає власної назви.
    static func name(of landmark: Landmark) -> String {
        let name = landmark.place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = landmark.place.category.singular
        if name.isEmpty || name.localizedCaseInsensitiveContains(kind) { return name.isEmpty ? kind : name }
        return "\(kind) \(name)"
    }

    private mutating func markSpoken(_ maneuver: Maneuver, thresholds: [Double]) {
        spoken.insert(key(maneuver, "now"))
        for threshold in thresholds { spoken.insert(key(maneuver, threshold)) }
    }

    private func key(_ maneuver: Maneuver, _ suffix: String) -> String { "\(maneuver.id)-\(suffix)" }
    private func key(_ maneuver: Maneuver, _ threshold: Double) -> String { "\(maneuver.id)-\(Int(threshold))" }
}
