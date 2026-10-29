import XCTest

/// Верхня панель згортається до одного рядка на записаному маршруті без мережі.
@MainActor
final class TopBarUITests: XCTestCase {
    func testTopBarCollapsesToOneRowAndKeepsModeSwitch() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 20))
        let fullHeight = app.staticTexts["mode.timer"].frame.maxY - app.staticTexts["maneuver.distance"].frame.minY

        // Шеврон на банері згортає банер і індикатор в один рядок.
        app.buttons["topbar.toggle"].tap()
        let compact = app.otherElements["topbar.compact"]
        XCTAssertTrue(compact.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["mode.subtitle"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["topbar.toggle"].exists)
        XCTAssertLessThan(compact.frame.height, 90)
        XCTAssertLessThan(compact.frame.height * 2, fullHeight, "рядок щонайменше вдвічі нижчий за повну панель")

        // У рядку лишаються маневр, режим і таймер «без GPS», навігація йде далі.
        XCTAssertTrue(app.staticTexts["maneuver.instruction"].exists)
        XCTAssertEqual(mode.label, "Розрахункова позиція")
        XCTAssertTrue(app.staticTexts["mode.timer"].label.hasPrefix("без GPS"))
        guard let before = UITest.remaining(app) else { return XCTFail("немає залишку") }
        UITest.pause(3)
        XCTAssertLessThan(UITest.remaining(app) ?? .max, before)

        // Тап по режиму в рядку відкриває вибір режиму, панель лишається згорнутою.
        mode.tap()
        let force = app.buttons.matching(identifier: "mode.option.forceGPS").firstMatch
        XCTAssertTrue(force.waitForExistence(timeout: 5))
        force.tap()
        XCTAssertTrue(UITest.wait(mode, label: "GPS", timeout: 5))
        XCTAssertTrue(app.staticTexts["mode.status"].label.hasPrefix("вручну"))
        XCTAssertTrue(compact.exists)

        // Свайп униз розгортає, свайп угору по банеру згортає, тап по рядку знову розгортає.
        compact.swipeDown()
        XCTAssertTrue(app.buttons["topbar.toggle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["mode.subtitle"].label, "увімкнено вручну")
        // Банер біля верхнього краю: тягнемо пальцем на 90 точок угору, не виходячи за екран.
        let instruction = app.staticTexts["maneuver.instruction"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        instruction.press(forDuration: 0.05, thenDragTo: instruction.withOffset(CGVector(dx: 0, dy: -90)))
        XCTAssertTrue(compact.waitForExistence(timeout: 3))
        compact.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["topbar.toggle"].waitForExistence(timeout: 3))
        XCTAssertFalse(compact.exists)
    }
}
