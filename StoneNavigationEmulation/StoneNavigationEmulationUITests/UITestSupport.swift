import XCTest

@MainActor
enum UITest {
    /// Запуск у відтворюваному сценарії: фейкова геолокація і записаний маршрут, без мережі MapKit.
    static func launch(scenario: String, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-scenario", scenario, "-AppleLanguages", "(uk)", "-AppleLocale", "uk_UA"] + arguments
        app.launch()
        return app
    }

    /// Дочекатися, поки підпис елемента стане `label`.
    @discardableResult
    static func wait(_ element: XCUIElement, label: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Дочекатися, поки значення елемента (accessibilityValue) почнеться з `prefix`.
    @discardableResult
    static func wait(_ element: XCUIElement, valuePrefix prefix: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", prefix), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Пауза без перевірок, щоб переконатися, що стан не змінюється.
    static func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "пауза")], timeout: seconds)
    }

    /// Прокрутити список, доки елемент не з'явиться і не стане доступним для тапу.
    static func scroll(to element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    /// Сценарій `lost`: позиція точно на вигаданому місці з довгою назвою і на паузі, тож його значок посеред карти.
    /// «Пауза» → список орієнтирів → картка → «Я біля нього». Пауза спершу: інакше, поки закривається картка,
    /// точка від'їжджає на кілька десятків метрів і місце в списку переходить у «Позаду».
    static func standAtLongNamePlace(_ app: XCUIApplication) {
        XCTAssertTrue(wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        let toggle = app.buttons["pause.toggle"]
        toggle.tap()
        XCTAssertEqual(toggle.label, "Далі")
        app.buttons["landmarks.list.button"].tap()
        let row = longNameRow(app)
        XCTAssertTrue(row.exists)
        row.tap()
        let confirm = app.buttons["landmark.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Далі", "підтвердження позиції не знімає паузу")
        // Камера доїжджає до нової позиції.
        pause(1.5)
    }

    /// Рядок вигаданого місця з довгою назвою у відкритому списку орієнтирів. Список лінивий:
    /// рядки нижче екрана ще не існують, тож за потреби прокручуємо.
    static func longNameRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'landmark.row.' AND label BEGINSWITH %@", "Товари для художників…")).firstMatch
        XCTAssertTrue(app.staticTexts["landmarks.ahead"].waitForExistence(timeout: 10))
        if !row.waitForExistence(timeout: 2) { scroll(to: row, in: app) }
        return row
    }

    /// Скільки орієнтирів попереду в списку: число із заголовка «Попереду · 12».
    /// Рядки лінивого списку рахувати не можна: на половині екрана існують лише видимі.
    static func landmarksAhead(_ app: XCUIApplication) -> Int? {
        let header = app.staticTexts["landmarks.ahead"]
        guard header.waitForExistence(timeout: 5) else { return nil }
        return Int(header.label.components(separatedBy: "· ").last ?? "")
    }

    /// Ціле значення швидкості з підпису «45 км/год».
    static func speed(_ element: XCUIElement) -> Int? {
        Int(element.label.components(separatedBy: " ").first ?? "")
    }

    /// Залишок маршруту в метрах з accessibilityValue.
    static func remaining(_ app: XCUIApplication) -> Int? {
        (app.staticTexts["remaining.label"].value as? String).flatMap(Int.init)
    }
}
