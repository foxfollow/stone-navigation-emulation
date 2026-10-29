import Foundation

/// Сховище пар ключ-значення. У додатку це UserDefaults, у тестах пам'ять.
public protocol KeyValueStorage: AnyObject, Sendable {
    func double(forKey key: String) -> Double?
    func bool(forKey key: String) -> Bool?
    func set(_ value: Double, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func data(forKey key: String) -> Data?
    func set(_ value: Data, forKey key: String)
    func removeValue(forKey key: String)
}

public final class InMemoryKeyValueStorage: KeyValueStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    public init() {}

    public func double(forKey key: String) -> Double? { lock.withLock { storage[key] as? Double } }
    public func bool(forKey key: String) -> Bool? { lock.withLock { storage[key] as? Bool } }
    public func set(_ value: Double, forKey key: String) { lock.withLock { storage[key] = value } }
    public func set(_ value: Bool, forKey key: String) { lock.withLock { storage[key] = value } }
    public func data(forKey key: String) -> Data? { lock.withLock { storage[key] as? Data } }
    public func set(_ value: Data, forKey key: String) { lock.withLock { storage[key] = value } }
    public func removeValue(forKey key: String) { _ = lock.withLock { storage.removeValue(forKey: key) } }
}

/// Читає і пише NavigationSettings у KeyValueStorage, кожне значення окремим ключем.
public struct SettingsRepository: Sendable {
    public static let prefix = "settings."

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage) {
        self.storage = storage
    }

    public func load() -> NavigationSettings {
        var settings = NavigationSettings()
        for key in SettingKey.allCases {
            if let value = storage.double(forKey: Self.prefix + key.rawValue) {
                settings[key] = value
            }
        }
        for toggle in SettingToggle.allCases {
            if let value = storage.bool(forKey: Self.prefix + toggle.rawValue) {
                settings[toggle] = value
            }
        }
        return settings
    }

    public func save(_ settings: NavigationSettings) {
        for key in SettingKey.allCases {
            storage.set(settings[key], forKey: Self.prefix + key.rawValue)
        }
        for toggle in SettingToggle.allCases {
            storage.set(settings[toggle], forKey: Self.prefix + toggle.rawValue)
        }
    }

    /// Скинути до стандартних: прибрати збережені значення.
    @discardableResult
    public func reset() -> NavigationSettings {
        for key in SettingKey.allCases {
            storage.removeValue(forKey: Self.prefix + key.rawValue)
        }
        for toggle in SettingToggle.allCases {
            storage.removeValue(forKey: Self.prefix + toggle.rawValue)
        }
        return .standard
    }
}
