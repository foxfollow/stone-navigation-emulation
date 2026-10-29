import Foundation

/// Форматування чисел для інтерфейсу і голосу українською.
public enum UkrainianFormat {
    /// Форма слова після числа: 1 метр, 2 метри, 5 метрів, 11 метрів, 21 метр.
    public static func plural(_ number: Int, one: String, few: String, many: String) -> String {
        let n100 = abs(number) % 100
        let n10 = abs(number) % 10
        if (11...14).contains(n100) { return many }
        if n10 == 1 { return one }
        if (2...4).contains(n10) { return few }
        return many
    }

    /// Відстань словами для голосу: «300 метрів», «1 кілометр», «1,5 кілометра».
    public static func spokenDistance(_ meters: Double) -> String {
        if meters < 1000 {
            let value = Int(meters.rounded())
            return "\(value) \(plural(value, one: "метр", few: "метри", many: "метрів"))"
        }
        let kilometers = (meters / 100).rounded() / 10
        if kilometers == kilometers.rounded() {
            let value = Int(kilometers)
            return "\(value) \(plural(value, one: "кілометр", few: "кілометри", many: "кілометрів"))"
        }
        return "\(decimal(kilometers, digits: 1)) кілометра"
    }

    /// Коротка відстань для екрана: «80 м», «350 м», «1,2 км», «12 км».
    public static func distance(_ meters: Double) -> String {
        let meters = max(0, meters)
        if meters < 1000 {
            let rounded = meters < 100 ? (meters / 10).rounded() * 10 : (meters / 50).rounded() * 50
            if rounded >= 1000 { return "1,0 км" }
            return "\(Int(rounded)) м"
        }
        if meters < 10_000 { return "\(decimal(meters / 1000, digits: 1)) км" }
        return "\(Int((meters / 1000).rounded())) км"
    }

    public static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Швидкість у км/год з м/с.
    public static func speed(_ metersPerSecond: Double) -> String {
        "\(Int((metersPerSecond * 3.6).rounded())) км/год"
    }

    /// Тривалість у дорозі: «12 хв», «1 год 05 хв».
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) хв" }
        return "\(minutes / 60) год \(String(format: "%02d", minutes % 60)) хв"
    }

    /// Таймер «без GPS»: 02:14 або 1:02:14.
    public static func timer(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Час доби «21:58».
    public static func clockTime(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    public static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
