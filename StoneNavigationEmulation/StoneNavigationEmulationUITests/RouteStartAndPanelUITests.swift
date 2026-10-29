import XCTest

/// Вибір точки відправлення і згортання нижньої панелі на записаному маршруті без мережі.
@MainActor
final class RouteStartAndPanelUITests: XCTestCase {
    func testControlPanelCollapsesAndExpands() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 20))
        let toggle = app.buttons["panel.toggle"]
        XCTAssertTrue(app.buttons["speed.plus"].exists)
        XCTAssertEqual(toggle.label, "Згорнути панель")

        // Компактна панель: швидкість, − і +, Пауза в одному ряду, зсув і GPS у другому.
        let plus = app.buttons["speed.plus"].frame
        XCTAssertEqual(app.buttons["speed.minus"].frame.midY, plus.midY, accuracy: 2)
        XCTAssertEqual(app.buttons["pause.toggle"].frame.midY, plus.midY, accuracy: 2)
        XCTAssertEqual(app.staticTexts["speed.value"].frame.midX, (app.buttons["speed.minus"].frame.maxX + plus.minX) / 2, accuracy: 3)
        XCTAssertEqual(app.buttons["shift.back"].frame.midY, app.buttons["mode.switch"].frame.midY, accuracy: 2)
        let height = app.buttons["mode.switch"].frame.maxY - toggle.frame.minY
        XCTAssertLessThan(height, 230, "панель нижча, ніж була (≈270 точок)")
        // Стандартно під праву руку: швидкість і зсув біля правого краю, Пауза і GPS ліворуч.
        XCTAssertGreaterThan(app.buttons["speed.minus"].frame.minX, app.buttons["pause.toggle"].frame.maxX)
        XCTAssertGreaterThan(app.buttons["shift.back"].frame.minX, app.buttons["mode.switch"].frame.maxX)

        // Згорнута панель: лише час прибуття, залишок і «Завершити».
        toggle.tap()
        XCTAssertTrue(app.buttons["speed.plus"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["pause.toggle"].exists)
        XCTAssertFalse(app.buttons["shift.forward"].exists)
        XCTAssertFalse(app.buttons["mode.switch"].exists)
        XCTAssertTrue(app.staticTexts["remaining.label"].exists)
        XCTAssertTrue(app.buttons["navigation.end"].exists)
        XCTAssertEqual(toggle.label, "Розгорнути панель")

        // Навігація при цьому йде далі: точка рухається.
        guard let before = UITest.remaining(app) else { return XCTFail("немає залишку") }
        UITest.pause(3)
        XCTAssertLessThan(UITest.remaining(app) ?? .max, before)

        // Свайп угору розгортає, свайп униз згортає, тап знову розгортає.
        toggle.swipeUp()
        XCTAssertTrue(app.buttons["speed.plus"].waitForExistence(timeout: 3))
        toggle.swipeDown()
        XCTAssertTrue(app.buttons["speed.plus"].waitForNonExistence(timeout: 3))
        toggle.tap()
        XCTAssertTrue(app.buttons["speed.plus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["pause.toggle"].exists)
    }

    func testPanelForRightAndLeftHandWithLargeText() {
        continueAfterFailure = false
        // Найдовші підписи: крок 10 км/год, зсув 120 м, ручна швидкість (є ↺), збільшений системний шрифт.
        let app = UITest.launch(scenario: "lost", arguments: [
            "-set", "shiftStepMeters=120", "-set", "speedStepKmh=10",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL",
        ])
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 20))
        let minus = app.buttons["speed.minus"]
        let plus = app.buttons["speed.plus"]
        let pause = app.buttons["pause.toggle"]
        let back = app.buttons["shift.back"]
        let forward = app.buttons["shift.forward"]
        let gps = app.buttons["mode.switch"]
        XCTAssertEqual(minus.label, "Мінус 10 кілометрів на годину")
        XCTAssertEqual(back.label, "← 120 м")
        plus.tap()
        let reset = app.buttons["speed.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))

        // Усе в два ряди, «прибуття» в один рядок, панель не виросла від шрифту.
        let caption = app.staticTexts["arrival.caption"]
        XCTAssertLessThan(caption.frame.height, 22, "«прибуття» не переноситься")
        for button in [minus, plus] { XCTAssertEqual(button.frame.midY, pause.frame.midY, accuracy: 2) }
        for button in [back, forward, reset] { XCTAssertEqual(button.frame.midY, gps.frame.midY, accuracy: 2) }
        XCTAssertEqual(gps.frame.height, back.frame.height, accuracy: 1)
        let height = gps.frame.maxY - app.buttons["panel.toggle"].frame.minY
        XCTAssertLessThan(height, 230)
        let source = app.staticTexts["speed.source"]
        XCTAssertEqual(source.label, "вручну")
        XCTAssertLessThanOrEqual(source.frame.width, ControlPanelGeometry.subtitleWidth + 1)

        // Під праву руку: − і + біля правого краю, ↺ між GPS і зсувом.
        XCTAssertGreaterThan(minus.frame.minX, pause.frame.maxX)
        XCTAssertGreaterThan(back.frame.minX, reset.frame.maxX)
        XCTAssertGreaterThan(reset.frame.minX, gps.frame.maxX)

        // Лівша: те саме дзеркально.
        app.buttons["settings.button"].tap()
        let hand = app.segmentedControls["settings.hand"]
        XCTAssertTrue(hand.waitForExistence(timeout: 5))
        hand.buttons["Лівша"].tap()
        app.buttons["settings.done"].tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        XCTAssertLessThan(plus.frame.maxX, pause.frame.minX)
        XCTAssertLessThan(forward.frame.maxX, reset.frame.minX)
        XCTAssertLessThan(reset.frame.maxX, gps.frame.minX)
        XCTAssertLessThan(back.frame.maxX, forward.frame.minX, "← лишається ліворуч від →")
    }

    func testStationaryCanBeOverriddenToDriveOn() {
        continueAfterFailure = false
        // Датчики руху весь час кажуть «стоянка», як телефон, що лежить на столі.
        let app = UITest.launch(scenario: "lost", arguments: ["-motion", "stationary"])
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 20))
        let source = app.staticTexts["speed.source"]
        XCTAssertEqual(source.label, "стоянка")
        let go = app.buttons["pause.toggle"]
        XCTAssertEqual(go.label, "Рушити")
        guard let parked = UITest.remaining(app) else { return XCTFail("немає залишку") }
        UITest.pause(3)
        XCTAssertEqual(UITest.remaining(app), parked, "на стоянці точка стоїть")

        // «Рушити»: точка їде, хоч датчики й далі бачать стоянку.
        go.tap()
        XCTAssertEqual(go.label, "Пауза")
        XCTAssertEqual(source.label, "з маршруту")
        UITest.pause(3)
        XCTAssertLessThan(UITest.remaining(app) ?? .max, parked)
    }

    func testChosenStartPointBeginsPausedAtRouteStart() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 20))
        // Точка вже проїхала частину маршруту, а панель згорнута.
        UITest.pause(3)
        guard let driven = UITest.remaining(app) else { return XCTFail("немає залишку") }
        app.buttons["panel.toggle"].tap()
        XCTAssertTrue(app.buttons["pause.toggle"].waitForNonExistence(timeout: 3))

        // «Звідки» → Майдан Незалежності, «Куди» → Дарницька площа.
        app.buttons["search.button"].tap()
        let origin = app.buttons["search.origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 5))
        XCTAssertTrue(origin.label.contains("Моя позиція"))
        origin.tap()
        XCTAssertTrue(app.navigationBars["Звідки їдемо?"].waitForExistence(timeout: 3))
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText("Майдан")
        let maidan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Майдан Незалежності")).firstMatch
        XCTAssertTrue(maidan.waitForExistence(timeout: 5))
        maidan.tap()
        XCTAssertTrue(app.navigationBars["Куди їдемо?"].waitForExistence(timeout: 3))
        XCTAssertTrue(origin.label.contains("Майдан Незалежності"))
        XCTAssertTrue(app.buttons["search.origin.reset"].exists)

        field.tap()
        field.typeText("Дарниц")
        let darnytsia = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Дарницька площа")).firstMatch
        XCTAssertTrue(darnytsia.waitForExistence(timeout: 5))
        darnytsia.tap()

        // Маршрут від вибраної точки: позиція на старті, на паузі, панель сама розгорнулася до «Далі».
        let pause = app.buttons["pause.toggle"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertEqual(pause.label, "Далі")
        XCTAssertEqual(app.staticTexts["speed.source"].label, "пауза")
        XCTAssertEqual(mode.label, "Розрахункова позиція")
        guard let atStart = UITest.remaining(app) else { return XCTFail("немає залишку") }
        XCTAssertGreaterThan(atStart, driven, "позиція повернулася на старт маршруту")
        UITest.pause(3)
        XCTAssertEqual(UITest.remaining(app), atStart, "до «Далі» точка стоїть на старті")

        pause.tap()
        UITest.pause(3)
        XCTAssertLessThan(UITest.remaining(app) ?? .max, atStart)
    }

    func testLongPressOnMapSetsStartPoint() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        app.buttons["navigation.end"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "Завершити")).firstMatch.tap()
        let search = app.buttons["search.button"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertFalse(search.label.contains("Звідки"))

        // Довгий тап → «Звідси»: старт видно в рядку пошуку, його можна скинути на мою позицію.
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        point.press(forDuration: 1.2)
        let fromHere = app.buttons["pending.origin"]
        XCTAssertTrue(fromHere.waitForExistence(timeout: 5))
        fromHere.tap()
        XCTAssertTrue(search.label.contains("Звідки: Вибрана точка"))
        let reset = app.buttons["origin.reset"]
        XCTAssertTrue(reset.exists)
        reset.tap()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 3))
        XCTAssertFalse(search.label.contains("Звідки"))

        // Знову «Звідси», потім інша точка → «Сюди»: маршрут від вибраної точки, точка чекає на старті.
        point.press(forDuration: 1.2)
        XCTAssertTrue(fromHere.waitForExistence(timeout: 5))
        fromHere.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.62)).press(forDuration: 1.2)
        let go = app.buttons["pending.go"]
        XCTAssertTrue(go.waitForExistence(timeout: 5))
        go.tap()
        let pause = app.buttons["pause.toggle"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertEqual(pause.label, "Далі")
        guard let atStart = UITest.remaining(app) else { return XCTFail("немає залишку") }
        UITest.pause(3)
        XCTAssertEqual(UITest.remaining(app), atStart, "до «Далі» точка стоїть на старті")
    }
}

/// Розміри панелі, що їх перевіряють тести (ControlPanel.speedDiameter × 0,62).
enum ControlPanelGeometry {
    static let subtitleWidth: CGFloat = 76 * 0.62
}
