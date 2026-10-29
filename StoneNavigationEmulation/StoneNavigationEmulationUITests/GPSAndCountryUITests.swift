import XCTest

/// Перехід на GPS за бажанням водія і вимкнені адреси в Росії та Білорусі, без мережі.
@MainActor
final class GPSAndCountryUITests: XCTestCase {
    func testForceGPSWhenSignalIsBad() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 20))
        // Остання точка GPS уже застаріла: одним тапом на GPS не перейти, тож застосунок питає.
        UITest.pause(5)
        app.buttons["mode.switch"].tap()
        let force = app.buttons.matching(identifier: "mode.option.forceGPS").firstMatch
        XCTAssertTrue(force.waitForExistence(timeout: 5))
        force.tap()

        XCTAssertTrue(UITest.wait(mode, label: "GPS", timeout: 5))
        XCTAssertEqual(app.staticTexts["mode.subtitle"].label, "увімкнено вручну")
        // Точок GPS немає: точка не їде розрахунком і режим сам не повертається.
        guard let held = UITest.remaining(app) else { return XCTFail("немає залишку") }
        UITest.pause(4)
        XCTAssertEqual(mode.label, "GPS")
        XCTAssertEqual(UITest.remaining(app), held)

        // «Автоматичне перемикання»: без сигналу знову вмикається розрахункова.
        mode.tap()
        let auto = app.buttons.matching(identifier: "mode.option.auto").firstMatch
        XCTAssertTrue(auto.waitForExistence(timeout: 5))
        auto.tap()
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 10))
    }

    func testModeIndicatorSwitchesModeWithCollapsedPanel() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "gps")
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "GPS", timeout: 10))
        app.buttons["panel.toggle"].tap()
        XCTAssertTrue(app.buttons["mode.switch"].waitForNonExistence(timeout: 3))

        mode.tap()
        let deadReckoning = app.buttons.matching(identifier: "mode.option.deadReckoning").firstMatch
        XCTAssertTrue(deadReckoning.waitForExistence(timeout: 5))
        deadReckoning.tap()
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 5))

        // GPS добрий: «Перейти на GPS» перемикає одразу.
        mode.tap()
        let gps = app.buttons.matching(identifier: "mode.option.gps").firstMatch
        XCTAssertTrue(gps.waitForExistence(timeout: 5))
        gps.tap()
        XCTAssertTrue(UITest.wait(mode, label: "GPS", timeout: 5))
        XCTAssertEqual(app.staticTexts["mode.subtitle"].label, "прив'язано до дороги")
        XCTAssertFalse(app.buttons["speed.plus"].exists, "панель лишилася згорнутою")
    }

    func testRussianAndBelarusianAddressesAreBlocked() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "gps")
        let search = app.buttons["search.button"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        // «Москва, Росія» у підказках немає, українська площа є.
        field.typeText("площа")
        let darnytsia = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Дарницька площа")).firstMatch
        XCTAssertTrue(darnytsia.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Червона площа")).firstMatch.exists)

        // Країни немає в підказці, але MapKit каже BY: вибрати не можна.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        field.typeText("вокзал")
        let gomel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Залізничний вокзал")).firstMatch
        XCTAssertTrue(gomel.waitForExistence(timeout: 5))
        gomel.tap()
        let error = app.staticTexts["search.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Адреси в Росії та Білорусі вимкнено")
        XCTAssertTrue(app.navigationBars["Куди їдемо?"].exists, "пошук лишається відкритим")
    }
}
