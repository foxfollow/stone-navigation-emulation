import XCTest

/// Довгий тап по карті під час навігації: «Я тут», «Маршрут звідси», «Сюди».
@MainActor
final class MapPointUITests: XCTestCase {
    func testMapPointDuringNavigation() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "lost")
        XCTAssertTrue(UITest.wait(app.staticTexts["mode.indicator"], label: "Розрахункова позиція", timeout: 20))
        let pause = app.buttons["pause.toggle"]
        pause.tap()
        XCTAssertEqual(pause.label, "Далі")
        guard let before = UITest.remaining(app) else { return XCTFail("немає залишку") }

        // Точка на маршруті трохи попереду (карта за напрямком руху, маршрут іде вгору від позиції).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 1.2)
        let here = app.buttons["pending.here"]
        XCTAssertTrue(here.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pending.rebuild"].exists)
        XCTAssertTrue(app.buttons["pending.go"].exists)
        XCTAssertFalse(app.buttons["pending.origin"].exists, "«Звідси» лише без навігації")
        let place = app.staticTexts["pending.where"].label
        XCTAssertTrue(place.hasPrefix("На маршруті") || place.hasPrefix("Біля маршруту"), place)
        XCTAssertTrue(here.isEnabled)

        // «Я тут»: позиція стає на маршрут навпроти точки, картка закривається.
        here.tap()
        XCTAssertTrue(here.waitForNonExistence(timeout: 3))
        let moved = before - (UITest.remaining(app) ?? before)
        XCTAssertGreaterThan(moved, 15, "позиція переставлена вперед")
        XCTAssertLessThan(moved, 150)

        // Точка далеко від маршруту: «Я тут» недоступне, «Маршрут звідси» прокладає маршрут від неї.
        app.buttons["map.zoomOut"].tap()
        app.buttons["map.zoomOut"].tap()
        UITest.pause(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.32)).press(forDuration: 1.2)
        XCTAssertTrue(here.waitForExistence(timeout: 5))
        let far = app.staticTexts["pending.where"].label
        XCTAssertTrue(far.hasPrefix("Далеко від маршруту"), far)
        XCTAssertFalse(here.isEnabled)
        app.buttons["pending.rebuild"].tap()
        XCTAssertTrue(here.waitForNonExistence(timeout: 3))
        // Записаний маршрут від фейкового MapKit: позиція на його початку; точка була на паузі, тож чекає «Далі».
        XCTAssertTrue(UITest.wait(app.staticTexts["remaining.label"], valuePrefix: "1137", timeout: 5), app.staticTexts["remaining.label"].value as? String ?? "")
        XCTAssertEqual(pause.label, "Далі")
    }
}
