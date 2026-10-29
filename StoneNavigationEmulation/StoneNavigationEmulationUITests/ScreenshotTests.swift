import XCTest

/// Скріншоти екранів gps, lost, spoof, poi, landmarks (список орієнтирів зі станом завантаження), settings, collapsed (згорнута панель), compact (згорнуті обидві панелі),
/// search (рядок пошуку на карті), saved (дім і останні адреси), start (вибір точки відправлення),
/// panel (нижня панель під праву руку з великим шрифтом), pins (значки орієнтирів на карті),
/// point (точка з довгого тапу під час навігації).
/// З `TEST_RUNNER_SCREENSHOTS_DIR=<шлях>` PNG записуються в цю папку (docs/screenshots), інакше лише у вкладення xcresult.
@MainActor
final class ScreenshotTests: XCTestCase {
    func testScreenshotGPS() throws {
        let app = UITest.launch(scenario: "gps")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "GPS", timeout: 20))
        UITest.pause(4)
        try save(app, "gps")
    }

    func testScreenshotLost() throws {
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        UITest.pause(6)
        try save(app, "lost")
    }

    func testScreenshotSpoof() throws {
        let app = UITest.launch(scenario: "spoof")
        XCTAssertTrue(app.staticTexts["spoof.prompt"].waitForExistence(timeout: 30))
        UITest.pause(1)
        try save(app, "spoof")
    }

    func testScreenshotPOI() throws {
        let app = UITest.launch(scenario: "poi")
        let list = app.buttons["landmarks.list.button"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        UITest.pause(4)
        list.tap()
        XCTAssertTrue(app.buttons["landmark.row.0"].waitForExistence(timeout: 10))
        // Третій попереду: перші можуть уже лишитися позаду, поки картка відкривається.
        let row = app.buttons["landmark.row.2"].exists ? app.buttons["landmark.row.2"] : app.buttons["landmark.row.0"]
        row.tap()
        XCTAssertTrue(app.staticTexts["landmark.name"].waitForExistence(timeout: 5))
        UITest.pause(1)
        try save(app, "poi")
    }

    func testScreenshotLandmarkList() throws {
        let app = UITest.launch(scenario: "poi")
        let list = app.buttons["landmarks.list.button"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        UITest.pause(4)
        list.tap()
        XCTAssertTrue(app.staticTexts["landmarks.coverage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["landmark.row.0"].waitForExistence(timeout: 5))
        UITest.pause(1)
        try save(app, "landmarks")
    }

    func testScreenshotSettings() throws {
        let app = UITest.launch(scenario: "settings")
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 20))
        UITest.pause(1)
        try save(app, "settings")
    }

    func testScreenshotCollapsedPanel() throws {
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        app.buttons["panel.toggle"].tap()
        XCTAssertTrue(app.buttons["speed.plus"].waitForNonExistence(timeout: 3))
        UITest.pause(2)
        try save(app, "collapsed")
    }

    func testScreenshotCompactTopBar() throws {
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        app.buttons["topbar.toggle"].tap()
        app.buttons["panel.toggle"].tap()
        XCTAssertTrue(app.otherElements["topbar.compact"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["speed.plus"].waitForNonExistence(timeout: 3))
        UITest.pause(2)
        try save(app, "compact")
    }

    func testScreenshotSearchBar() throws {
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        app.buttons["navigation.end"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Завершити")).firstMatch.tap()
        XCTAssertTrue(app.buttons["search.button"].waitForExistence(timeout: 5))
        UITest.pause(2)
        try save(app, "search")
    }

    func testScreenshotSavedPlaces() throws {
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        app.buttons["search.button"].tap()
        XCTAssertTrue(app.buttons["saved.home.add"].waitForExistence(timeout: 5))
        app.buttons["saved.home.add"].tap()
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText("Майдан")
        let maidan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Майдан Незалежності")).firstMatch
        XCTAssertTrue(maidan.waitForExistence(timeout: 5))
        maidan.tap()
        field.tap()
        field.typeText("Дарниц")
        let darnytsia = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Дарницька площа")).firstMatch
        XCTAssertTrue(darnytsia.waitForExistence(timeout: 5))
        darnytsia.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.buttons["search.button"].tap()
        XCTAssertTrue(app.buttons["saved.recent.0"].waitForExistence(timeout: 5))
        UITest.pause(1)
        try save(app, "saved")
    }

    func testScreenshotStartPoint() throws {
        let app = UITest.launch(scenario: "gps")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "GPS", timeout: 20))
        app.buttons["search.button"].tap()
        app.buttons["search.origin"].tap()
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText("Майдан")
        let maidan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Майдан Незалежності")).firstMatch
        XCTAssertTrue(maidan.waitForExistence(timeout: 5))
        maidan.tap()
        field.tap()
        field.typeText("Дарниц")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Дарницька площа")).firstMatch.waitForExistence(timeout: 5))
        UITest.pause(1)
        try save(app, "start")
    }

    /// Нижня панель під праву руку з найдовшими підписами: крок 10 км/год, зсув 120 м, ручна швидкість, великий шрифт.
    func testScreenshotPanel() throws {
        let app = UITest.launch(scenario: "lost", arguments: [
            "-set", "shiftStepMeters=120", "-set", "speedStepKmh=10",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL",
        ])
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        app.buttons["speed.plus"].tap()
        XCTAssertTrue(app.buttons["speed.reset"].waitForExistence(timeout: 3))
        UITest.pause(1)
        try save(app, "panel")
    }

    /// Значки орієнтирів на карті: трикутник на місці, підпис збоку, довга назва скорочена.
    func testScreenshotMapLandmarks() throws {
        let app = UITest.launch(scenario: "lost")
        UITest.standAtLongNamePlace(app)
        XCTAssertTrue(app.buttons["landmark.label.scenario.longName"].waitForExistence(timeout: 10))
        app.buttons["panel.toggle"].tap()
        UITest.pause(1)
        try save(app, "pins")
    }

    /// Довгий тап по маршруту під час навігації: «Я тут», «Маршрут звідси», «Сюди».
    func testScreenshotMapPoint() throws {
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        app.buttons["pause.toggle"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["pending.here"].waitForExistence(timeout: 5))
        UITest.pause(1)
        try save(app, "point")
    }

    private func save(_ app: XCUIApplication, _ name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] {
            let url = URL(fileURLWithPath: directory).appending(path: "\(name).png")
            try screenshot.pngRepresentation.write(to: url)
        }
    }
}
