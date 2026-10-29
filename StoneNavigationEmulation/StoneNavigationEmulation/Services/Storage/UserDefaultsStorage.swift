import Foundation
import NavigationCore

/// Налаштування в UserDefaults. Ядро бачить лише протокол KeyValueStorage.
final class UserDefaultsStorage: KeyValueStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func double(forKey key: String) -> Double? { defaults.object(forKey: key) as? Double }
    func bool(forKey key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
    func set(_ value: Double, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func set(_ value: Data, forKey key: String) { defaults.set(value, forKey: key) }
    func removeValue(forKey key: String) { defaults.removeObject(forKey: key) }
}
