import Foundation
import NavigationCore
import Observation

/// Стан екрана Налаштувань: редагування з межами і збереження між запусками.
@MainActor
@Observable
final class SettingsModel {
    private(set) var settings: NavigationSettings

    @ObservationIgnored private let repository: SettingsRepository
    @ObservationIgnored var onChange: ((NavigationSettings) -> Void)?

    init(repository: SettingsRepository) {
        self.repository = repository
        self.settings = repository.load()
    }

    func increment(_ key: SettingKey) {
        set(key, settings[key] + key.spec.step)
    }

    func decrement(_ key: SettingKey) {
        set(key, settings[key] - key.spec.step)
    }

    func set(_ key: SettingKey, _ value: Double) {
        var updated = settings
        updated[key] = value
        commit(updated)
    }

    func set(_ toggle: SettingToggle, _ value: Bool) {
        var updated = settings
        updated[toggle] = value
        commit(updated)
    }

    func resetToDefaults() {
        commit(repository.reset())
    }

    static func format(_ value: Double, for key: SettingKey) -> String {
        "\(number(value, for: key)) \(key.spec.unit)"
    }

    /// Межі одним рядком: «10–130 км/год».
    static func formatRange(for key: SettingKey) -> String {
        let range = key.spec.range
        return "\(number(range.lowerBound, for: key))–\(number(range.upperBound, for: key)) \(key.spec.unit)"
    }

    private static func number(_ value: Double, for key: SettingKey) -> String {
        key.spec.step < 1 ? UkrainianFormat.decimal(value, digits: 1) : String(Int(value.rounded()))
    }

    private func commit(_ updated: NavigationSettings) {
        settings = updated
        repository.save(updated)
        onChange?(updated)
    }
}
