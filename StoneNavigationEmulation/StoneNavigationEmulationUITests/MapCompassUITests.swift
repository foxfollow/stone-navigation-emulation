import XCTest

/// Компас на карті: північ зверху або за напрямком руху, на записаному маршруті без мережі.
@MainActor
final class MapCompassUITests: XCTestCase {
    func testCompassTogglesNorthUp() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "gps")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "GPS", timeout: 20))
        let compass = app.buttons["map.compass"]
        XCTAssertTrue(compass.waitForExistence(timeout: 5))
        // Спершу карта повернута за напрямком руху: курс маршруту тут не північ.
        XCTAssertTrue(UITest.wait(compass, valuePrefix: "за напрямком руху", timeout: 5))
        UITest.pause(3)
        XCTAssertNotEqual(compass.value as? String, "за напрямком руху, 0°")

        // Північ зверху: камера повертається на 0° і лишається так, поки позиція рухається.
        compass.tap()
        XCTAssertTrue(UITest.wait(compass, valuePrefix: "північ зверху, 0°", timeout: 5))
        guard let before = UITest.remaining(app) else { return XCTFail("немає залишку") }
        UITest.pause(3)
        XCTAssertLessThan(UITest.remaining(app) ?? .max, before)
        XCTAssertEqual(compass.value as? String, "північ зверху, 0°")

        // Знову за напрямком руху.
        compass.tap()
        XCTAssertTrue(UITest.wait(compass, valuePrefix: "за напрямком руху", timeout: 5))
        UITest.pause(2)
        XCTAssertNotEqual(compass.value as? String, "за напрямком руху, 0°")
    }
}
