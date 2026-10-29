import Foundation
import os

/// Журнал режимів в os.Logger: subsystem дорівнює bundle ID, категорія Mode.
/// Рівень notice зберігається в журналі, тому видно і в `log show`, і в Console на телефоні.
public struct OSModeLog: ModeLog {
    public static let category = "Mode"

    private let logger: Logger

    public init(subsystem: String) {
        logger = Logger(subsystem: subsystem, category: Self.category)
    }

    public func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
