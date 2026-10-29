import XCTest

/// Сценарії -scenario gps, lost, spoof, poi, settings на записаному маршруті без мережі.
@MainActor
final class ScenarioUITests: XCTestCase {
    func testGPSScenarioShowsGPSIndicator() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "gps")
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "GPS", timeout: 10))
        // Сигнал добрий: режим не змінюється.
        UITest.pause(5)
        XCTAssertEqual(mode.label, "GPS")
        XCTAssertFalse(app.staticTexts["mode.timer"].exists)
        // Кнопки розрахункового режиму сховані, є ручний перемикач.
        XCTAssertFalse(app.buttons["speed.plus"].exists)
        XCTAssertTrue(app.buttons["mode.switch"].exists)
        XCTAssertTrue(app.staticTexts["maneuver.instruction"].exists)
        let remaining = try? XCTUnwrap(UITest.remaining(app))
        XCTAssertNotNil(remaining)

        // Ручний перемикач вмикає розрахункову позицію.
        app.buttons["mode.switch"].tap()
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 5))
    }

    func testLostScenarioSwitchesToDeadReckoningAndControlsWork() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 20))
        let timer = app.staticTexts["mode.timer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        XCTAssertTrue(timer.label.hasPrefix("без GPS "))

        // Швидкість: плюс і мінус на крок 5 км/год, ручна діє до «Скинути».
        let speed = app.staticTexts["speed.value"]
        let source = app.staticTexts["speed.source"]
        let initial = try? XCTUnwrap(UITest.speed(speed))
        guard let initial else { return XCTFail("немає швидкості") }
        XCTAssertEqual(source.label, "з маршруту")
        app.buttons["speed.plus"].tap()
        XCTAssertEqual(UITest.speed(speed), initial + 5)
        XCTAssertEqual(source.label, "вручну")
        app.buttons["speed.minus"].tap()
        app.buttons["speed.minus"].tap()
        XCTAssertEqual(UITest.speed(speed), initial - 5)
        UITest.pause(2)
        XCTAssertEqual(UITest.speed(speed), initial - 5, "ручна швидкість не скидається сама")
        app.buttons["speed.reset"].tap()
        XCTAssertEqual(UITest.speed(speed), initial)
        XCTAssertEqual(source.label, "з маршруту")
        XCTAssertFalse(app.buttons["speed.reset"].exists)

        // Пауза зупиняє точку, Вперед і Назад зсувають її на 50 м.
        app.buttons["pause.toggle"].tap()
        XCTAssertEqual(app.buttons["pause.toggle"].label, "Далі")
        guard let paused = UITest.remaining(app) else { return XCTFail("немає залишку") }
        UITest.pause(2)
        XCTAssertEqual(UITest.remaining(app), paused, "на паузі точка стоїть")
        app.buttons["shift.forward"].tap()
        XCTAssertEqual(UITest.remaining(app), paused - 50)
        app.buttons["shift.back"].tap()
        app.buttons["shift.back"].tap()
        XCTAssertEqual(UITest.remaining(app), paused + 50)

        // Після «Далі» точка знову рухається.
        app.buttons["pause.toggle"].tap()
        UITest.pause(3)
        XCTAssertLessThan(UITest.remaining(app) ?? .max, paused + 50)
    }

    func testSpoofScenarioAsksWithKeepDeadReckoningAsDefault() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "spoof")
        let prompt = app.staticTexts["spoof.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 30))
        XCTAssertEqual(prompt.label, "GPS показує інше місце. Перейти на GPS?")
        let keep = app.buttons["spoof.keep"]
        let switchToGPS = app.buttons["spoof.switch"]
        XCTAssertTrue(keep.exists)
        XCTAssertTrue(switchToGPS.exists)
        // Варіант за замовчуванням перший і більший.
        XCTAssertLessThan(keep.frame.minY, switchToGPS.frame.minY)
        XCTAssertGreaterThan(keep.frame.height, switchToGPS.frame.height)
        XCTAssertEqual(app.staticTexts["mode.indicator"].label, "Розрахункова позиція")

        keep.tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mode.indicator"].label, "Розрахункова позиція")
        // Протягом паузи запит не повертається.
        UITest.pause(8)
        XCTAssertFalse(prompt.exists)
    }

    func testSpoofScenarioSwitchToGPS() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "spoof")
        let prompt = app.staticTexts["spoof.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 30))
        app.buttons["spoof.switch"].tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "GPS", timeout: 5))
    }

    func testPOIScenarioOpensLandmarkCardAndConfirmsPosition() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "poi")
        let list = app.buttons["landmarks.list.button"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        let row = app.buttons["landmark.row.0"]
        // Орієнтири завантажуються на першому оновленні.
        var attempts = 0
        repeat {
            list.tap()
            if row.waitForExistence(timeout: 4) { break }
            app.buttons["landmarks.done"].tap()
            attempts += 1
        } while attempts < 3
        XCTAssertTrue(row.exists)
        row.tap()

        let name = app.staticTexts["landmark.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(name.label.isEmpty)
        let distance = app.staticTexts["landmark.distance"].label
        XCTAssertTrue(distance.contains("по маршруту"), distance)
        let side = app.staticTexts["landmark.side"].label
        XCTAssertTrue(side.hasPrefix("Ліворуч") || side.hasPrefix("Праворуч"), side)
        XCTAssertTrue(side.hasSuffix("м від дороги"), side)
        XCTAssertTrue(app.buttons["landmark.addStop"].exists)
        XCTAssertTrue(app.buttons["landmark.details"].exists)

        // «Я біля нього» переставляє позицію на орієнтир: GPS вважається хибним.
        app.buttons["landmark.confirm"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 5))
    }

    func testPOIFiltersHideCategories() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "poi")
        let list = app.buttons["landmarks.list.button"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        UITest.pause(3)
        list.tap()
        XCTAssertTrue(app.buttons["landmark.row.0"].waitForExistence(timeout: 5))
        guard let before = UITest.landmarksAhead(app) else { return XCTFail("немає заголовка «Попереду»") }
        app.buttons["list.filters"].tap()
        app.buttons["list.filter.store"].tap()
        app.buttons["list.filter.foodMarket"].tap()
        app.buttons["landmarks.refresh"].tap()  // закрити меню
        XCTAssertLessThan(UITest.landmarksAhead(app) ?? .max, before)
    }

    func testSettingsThresholdChangeChangesBehavior() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "settings")
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        done.tap()

        // Точність 80 м при стандартному порозі 100 м: лишаємося на GPS.
        let mode = app.staticTexts["mode.indicator"]
        XCTAssertTrue(UITest.wait(mode, label: "GPS", timeout: 10))
        UITest.pause(4)
        XCTAssertEqual(mode.label, "GPS")

        // Поріг 50 м: та сама точність тепер вмикає розрахунковий режим.
        app.buttons["settings.button"].tap()
        let value = app.staticTexts["settings.enterAccuracy.value"]
        UITest.scroll(to: value, in: app)
        XCTAssertEqual(value.label, "100 м")
        let minus = app.buttons["settings.enterAccuracy.minus"]
        for _ in 0..<5 { minus.tap() }
        XCTAssertEqual(value.label, "50 м")
        done.tap()
        XCTAssertTrue(UITest.wait(mode, label: "Розрахункова позиція", timeout: 10))
    }

    func testSettingsBoundsAndReset() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "settings")
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 20))
        let value = app.staticTexts["settings.defaultSpeedKmh.value"]
        XCTAssertEqual(value.label, "50 км/год")
        let plus = app.buttons["settings.defaultSpeedKmh.plus"]
        for _ in 0..<20 where plus.isEnabled { plus.tap() }
        XCTAssertEqual(value.label, "130 км/год", "верхня межа")
        XCTAssertFalse(plus.isEnabled)

        let reset = app.buttons["settings.reset"]
        UITest.scroll(to: reset, in: app, maxSwipes: 30)
        reset.tap()
        // confirmationDialog показує кнопку у двох представленнях одночасно, тому беремо перший збіг.
        let confirm = app.buttons.matching(identifier: "settings.reset.confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        for _ in 0..<30 where !value.isHittable { app.swipeDown() }
        XCTAssertEqual(value.label, "50 км/год")
    }
}
