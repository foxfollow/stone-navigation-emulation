import Foundation

/// Коротка назва орієнтира для карти, списку і банера: довга назва обрізається до `maxWords` слів із «…».
/// Повну назву видно після тапу по підпису і в картці орієнтира.
public enum LandmarkName {
    public static let maxWords = 3

    /// Що прибрати в кінці обрізаної назви перед «…»: розділові знаки і відкриті лапки без пари.
    static let trailingJunk: Set<Character> = [",", ";", ":", "-", "–", "—", "(", "«", "„", "“", "/", "&", "|", "·", "+"]

    /// Перші `maxWords` слів і «…», якщо слів більше. Словом вважається частина з літерою або цифрою,
    /// тож « - » чи « & » між словами не рахуються.
    public static func short(_ name: String, maxWords: Int = maxWords) -> String {
        var kept: [Substring] = []
        var words = 0
        for token in name.split(whereSeparator: \.isWhitespace) {
            if token.contains(where: { $0.isLetter || $0.isNumber }) {
                guard words < maxWords else {
                    var text = kept.joined(separator: " ")
                    while let last = text.last, last.isWhitespace || trailingJunk.contains(last) {
                        text.removeLast()
                    }
                    return text + "…"
                }
                words += 1
            }
            kept.append(token)
        }
        return name
    }

    public static func isShortened(_ name: String, maxWords: Int = maxWords) -> Bool {
        short(name, maxWords: maxWords) != name
    }
}

extension PlaceCandidate {
    /// Назва для карти, списку і банера: не довше `LandmarkName.maxWords` слів.
    public var shortName: String { LandmarkName.short(name) }
}
