import XCTest

/// Плавний рух точки між оновленнями рушія і стеження за позицією на будь-якому масштабі.
@MainActor
final class MapFollowUITests: XCTestCase {
    func testPositionMovesSmoothlyBetweenUpdates() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        let position = app.otherElements["map.position"]
        XCTAssertTrue(UITest.wait(position, valuePrefix: "стежу", timeout: 5))

        // Перетягування вимикає стеження: камера стоїть, і видно, як точка їде екраном.
        let map = app.maps.firstMatch
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        XCTAssertTrue(UITest.wait(position, valuePrefix: "без стеження", timeout: 3))
        UITest.pause(1)

        // Рушій рахує позицію раз на секунду. Раніше точка між оновленнями стояла, тож більшість замірів
        // через ~0,2 с збігалися. Тепер вона зсувається майже між кожними двома замірами.
        var frames: [CGRect] = []
        for _ in 0..<16 {
            frames.append(position.frame)
            UITest.pause(0.15)
        }
        let pairs = zip(frames, frames.dropFirst())
        let moves = pairs.filter { abs($0.midX - $1.midX) + abs($0.midY - $1.midY) > 0.3 }.count
        XCTAssertGreaterThanOrEqual(moves, 12, "заміри: \(frames.map { "(\(Int($0.midX)), \(Int($0.midY)))" })")
        // І без великих стрибків: найбільший крок не більший за кілька середніх.
        let steps = pairs.map { hypot($0.midX - $1.midX, $0.midY - $1.midY) }
        let mean = steps.reduce(0, +) / Double(steps.count)
        XCTAssertLessThan(steps.max() ?? 0, mean * 3 + 2, "кроки: \(steps.map { Int($0) })")
    }

    func testFollowAtAnyZoom() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "gps")
        let position = app.otherElements["map.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(position, valuePrefix: "стежу, висота камери 900 м", timeout: 10))
        let map = app.maps.firstMatch
        let recenter = app.buttons["map.recenter"]
        XCTAssertFalse(recenter.exists)

        // «−» у стеженні віддаляє вдвічі, а стеження лишається, з новою висотою.
        app.buttons["map.zoomOut"].tap()
        XCTAssertTrue(UITest.wait(position, valuePrefix: "стежу, висота камери 1800 м", timeout: 3))
        let higher = 1800
        XCTAssertFalse(recenter.exists)
        UITest.pause(3)
        XCTAssertEqual(position.frame.midX, map.frame.midX, accuracy: 15)
        XCTAssertEqual(position.frame.midY, map.frame.midY, accuracy: 15)
        XCTAssertEqual(Self.cameraHeight(position), higher, "висота стеження не скидається на 900 м")
        app.buttons["map.zoomIn"].tap()
        XCTAssertTrue(UITest.wait(position, valuePrefix: "стежу, висота камери 900 м", timeout: 3))
        app.buttons["map.zoomOut"].tap()
        XCTAssertTrue(UITest.wait(position, valuePrefix: "стежу, висота камери 1800 м", timeout: 3))

        // Перетягування вимикає стеження, і карта їде під пальцем: позиція зсувається разом із нею.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        XCTAssertTrue(UITest.wait(position, valuePrefix: "без стеження", timeout: 3))
        XCTAssertTrue(recenter.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["map.zoomOut"].exists, "кнопки масштабу лише в стеженні: без нього карта звичайна")
        XCTAssertEqual(position.frame.midX, map.frame.midX - map.frame.width * 0.3, accuracy: 40, "позиція \(position.frame)")

        // Без стеження карта звичайна: тап двома пальцями віддаляє ще.
        map.twoFingerTap()
        let zoomedOut = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH 'без стеження' AND NOT (value CONTAINS 'камери %d м')", higher),
            object: position
        )
        XCTAssertEqual(XCTWaiter().wait(for: [zoomedOut], timeout: 5), .completed, position.value as? String ?? "")
        guard let zoomed = Self.cameraHeight(position) else { return XCTFail(position.value as? String ?? "") }
        XCTAssertGreaterThan(zoomed, higher)

        // «Центрувати» стежить далі з цим масштабом, а не скидає на 900 м.
        recenter.tap()
        XCTAssertTrue(UITest.wait(position, valuePrefix: "стежу", timeout: 3))
        XCTAssertEqual(Double(Self.cameraHeight(position) ?? 0), Double(zoomed), accuracy: Double(zoomed) * 0.05)
        XCTAssertTrue(recenter.waitForNonExistence(timeout: 3))
        // Позиція рухається, а камера тримає її посередині з тією самою висотою.
        let following = Self.cameraHeight(position)
        UITest.pause(3)
        XCTAssertEqual(position.frame.midX, map.frame.midX, accuracy: 15)
        XCTAssertEqual(position.frame.midY, map.frame.midY, accuracy: 15)
        XCTAssertEqual(Self.cameraHeight(position), following, "висота стеження не скидається")
    }

    /// Висота камери з «стежу, висота камери 2250 м».
    static func cameraHeight(_ position: XCUIElement) -> Int? {
        guard let value = position.value as? String, let range = value.range(of: "висота камери ") else { return nil }
        return Int(value[range.upperBound...].prefix { $0.isNumber })
    }
}
