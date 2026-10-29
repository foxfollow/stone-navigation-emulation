import Foundation
import NavigationCore

enum ScenarioName: String, CaseIterable {
    case gps, lost, spoof, poi, settings, turn
}

/// Аргументи запуску:
/// `-scenario gps|lost|spoof|poi|settings|turn`: фейкова геолокація і записаний маршрут, без мережі
/// (`turn`: перед поворотом з орієнтиром біля нього);
/// `-loadRoute test`: справжні порти, але одразу записаний тестовий маршрут (живий прогін із simctl);
/// `-resetState`: стерти збережений стан і налаштування;
/// `-motion stationary|automotive`: у сценарії датчики руху одразу повідомляють цей стан;
/// `-set ключ=значення` (можна кілька разів): числове налаштування в сценарії, наприклад `-set shiftStepMeters=120`.
struct LaunchConfiguration {
    var scenario: ScenarioName?
    var loadRoute: String?
    var resetState: Bool
    var motion: MotionActivity?
    var settings: [SettingKey: Double]

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        scenario = value(after: "-scenario").flatMap(ScenarioName.init(rawValue:))
        loadRoute = value(after: "-loadRoute")
        resetState = arguments.contains("-resetState")
        motion = value(after: "-motion").flatMap(MotionActivity.init(rawValue:))
        settings = [:]
        for (index, flag) in arguments.enumerated() where flag == "-set" && index + 1 < arguments.count {
            let parts = arguments[index + 1].split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let key = SettingKey(rawValue: parts[0]), let number = Double(parts[1]) else { continue }
            settings[key] = number
        }
    }
}
