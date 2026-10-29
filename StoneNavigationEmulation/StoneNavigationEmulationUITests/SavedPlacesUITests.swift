import XCTest

/// Дім, робота, збережені й останні адреси в пошуку, на записаних даних без мережі.
@MainActor
final class SavedPlacesUITests: XCTestCase {
    func testHomeRecentsAndSavedPlacesInSearch() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        let open = app.buttons["search.button"]
        open.tap()

        // Порожній пошук: місця для дому і роботи, останніх ще немає.
        let addHome = app.buttons["saved.home.add"]
        XCTAssertTrue(addHome.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saved.work.add"].exists)
        XCTAssertTrue(app.buttons["saved.favorite.add"].exists)
        XCTAssertFalse(app.buttons["saved.recent.0"].exists)
        // Своїх адрес ще немає: клавіатура одразу відкрита для введення.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        // Дім: адреса з підказок стає домом, маршрут не будується.
        addHome.tap()
        XCTAssertTrue(app.navigationBars["Адреса дому"].waitForExistence(timeout: 3))
        let field = app.textFields["search.field"]
        field.tap()
        field.typeText("Майдан")
        XCTAssertTrue(suggestion(app, "Майдан Незалежності").waitForExistence(timeout: 5))
        suggestion(app, "Майдан Незалежності").tap()
        let home = app.buttons["saved.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertTrue(home.label.contains("Майдан Незалежності"), home.label)
        XCTAssertFalse(addHome.exists)
        XCTAssertTrue(app.navigationBars["Куди їдемо?"].exists)

        // Поїздка до Дарницької площі потрапляє в останні.
        field.tap()
        field.typeText("Дарниц")
        XCTAssertTrue(suggestion(app, "Дарницька площа").waitForExistence(timeout: 5))
        suggestion(app, "Дарницька площа").tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        open.tap()
        let recent = app.buttons["saved.recent.0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertTrue(recent.label.contains("Дарницька площа"), recent.label)
        // Адреси вже є: пошук відкривається без клавіатури, щоб їх було видно.
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        // Довгий тап по останній адресі → «Зберегти»: вона переходить у збережені.
        recent.press(forDuration: 1.2)
        let saveItem = app.buttons["Зберегти"]
        XCTAssertTrue(saveItem.waitForExistence(timeout: 5))
        saveItem.tap()
        let favorite = app.buttons["saved.favorite.0"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertTrue(favorite.label.contains("Дарницька площа"), favorite.label)
        XCTAssertFalse(recent.exists, "збережена адреса не повторюється в останніх")

        // З текстом мої адреси стоять над підказками MapKit.
        field.tap()
        field.typeText("Майд")
        let fromMapKit = suggestion(app, "Майдан Незалежності")
        XCTAssertTrue(fromMapKit.waitForExistence(timeout: 5))
        XCTAssertTrue(home.exists)
        XCTAssertLessThan(home.frame.maxY, fromMapKit.frame.minY)
        XCTAssertFalse(favorite.exists, "Дарницька площа не підходить під «Майд»")

        // Тап по дому прокладає маршрут туди.
        home.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["remaining.label"].waitForExistence(timeout: 10))
    }

    private func suggestion(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
}
