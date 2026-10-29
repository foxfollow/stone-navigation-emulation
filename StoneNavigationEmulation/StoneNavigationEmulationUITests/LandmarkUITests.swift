import XCTest

/// Орієнтири біля повороту, «Оновити поруч» і стан завантаження, на записаних POI без мережі.
@MainActor
final class LandmarkUITests: XCTestCase {
    func testTurnLandmarkShownInBanner() {
        continueAfterFailure = false
        // Попереду поворот на Братиславську, а перед ним «Супер-пупер маркет Shket».
        let app = UITest.launch(scenario: "turn")
        let instruction = app.staticTexts["maneuver.instruction"]
        XCTAssertTrue(instruction.waitForExistence(timeout: 20))
        XCTAssertTrue(UITest.wait(instruction, label: "Поверніть управо на Братиславська вулиця", timeout: 10))
        let landmark = app.descendants(matching: .any)["maneuver.landmark"]
        XCTAssertTrue(landmark.waitForExistence(timeout: 10))
        XCTAssertEqual(landmark.label, "Орієнтир біля повороту: Супер-пупер маркет Shket")

        // У списку орієнтир позначено «біля повороту».
        app.buttons["landmarks.list.button"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'landmark.row.' AND label CONTAINS %@", "Супер-пупер маркет Shket")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("біля повороту"), row.label)
    }

    func testRefreshAndLoadingStatus() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "poi")
        let list = app.buttons["landmarks.list.button"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        UITest.pause(3)
        list.tap()

        // Стан видно: попереду вже завантажено, запити до MapKit були.
        let coverage = app.staticTexts["landmarks.coverage"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        XCTAssertNotEqual(coverage.label, "Попереду завантажено: 0 м")
        let requests = app.staticTexts["landmarks.requests"]
        guard let before = Self.requestCount(requests.label) else { return XCTFail(requests.label) }
        XCTAssertGreaterThan(before, 0)

        // «Оновити поруч» запитує ще раз, не чекаючи автоматики.
        app.buttons["landmarks.refresh"].tap()
        var after = before
        for _ in 0..<20 where after <= before {
            UITest.pause(0.5)
            after = Self.requestCount(requests.label) ?? before
        }
        XCTAssertGreaterThan(after, before, requests.label)

        // Коридор змінюється просто тут, у подробицях унизу списку.
        let found = app.staticTexts["landmarks.found"]
        UITest.scroll(to: app.buttons["landmarks.corridor.plus"], in: app, maxSwipes: 30)
        XCTAssertTrue(found.label.hasPrefix("Біля дороги (до 50 м)"), found.label)
        app.buttons["landmarks.corridor.plus"].tap()
        // Ширший коридор додає орієнтири вище в списку, тож подробиці знову прокручуємо на вид.
        UITest.scroll(to: found, in: app, maxSwipes: 30)
        XCTAssertTrue(found.label.hasPrefix("Біля дороги (до 60 м)"), found.label)
    }

    func testLongNameShortenedOnMapWithPointerAndSideLabel() {
        continueAfterFailure = false
        // У сценарії попереду вигадане місце «Товари для художників та творчості "Майстриня"», 25 м ліворуч від дороги.
        let app = UITest.launch(scenario: "lost")
        UITest.standAtLongNamePlace(app)

        let label = app.buttons["landmark.label.scenario.longName"]
        let pin = app.buttons["landmark.pin.scenario.longName"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertTrue(pin.exists)
        XCTAssertTrue(label.label.hasPrefix("Товари для художників…"), label.label)
        XCTAssertFalse(label.label.contains("Майстриня"), label.label)
        XCTAssertEqual(label.value as? String, "скорочена назва")

        // Карта за напрямком руху, орієнтир ліворуч від дороги: підпис ліворуч від значка, низом на рівні вістря.
        XCTAssertLessThanOrEqual(label.frame.maxX, pin.frame.minX + 1, "підпис \(label.frame), значок \(pin.frame)")
        XCTAssertGreaterThanOrEqual(label.frame.minX, 0, "підпис не виходить за край екрана: \(label.frame)")
        XCTAssertEqual(label.frame.maxY, pin.frame.maxY, accuracy: 2)
        XCTAssertLessThan(pin.frame.maxX, app.otherElements["map.position"].frame.midX)
        // Вістря трикутника (низ значка посередині) там, де саме місце: MapKit ставить точку анотації на координату.
        let point = app.otherElements.matching(NSPredicate(format: "identifier == 'VKPointFeature' AND label == %@", "Товари для художників та творчості \"Майстриня\"")).firstMatch
        XCTAssertTrue(point.exists)
        XCTAssertEqual(pin.frame.midX, point.frame.midX, accuracy: 3, "значок \(pin.frame), точка \(point.frame)")
        XCTAssertEqual(pin.frame.maxY, point.frame.midY, accuracy: 3, "значок \(pin.frame), точка \(point.frame)")

        // Тап по підпису розгортає повну назву, ще тап скорочує.
        label.tap()
        XCTAssertTrue(UITest.wait(label, valuePrefix: "повна назва", timeout: 3))
        XCTAssertTrue(label.label.contains("Майстриня"), label.label)
        label.tap()
        XCTAssertTrue(UITest.wait(label, valuePrefix: "скорочена назва", timeout: 3))

        // У списку теж коротка назва.
        app.buttons["landmarks.list.button"].tap()
        let row = UITest.longNameRow(app)
        XCTAssertTrue(row.exists)
        app.buttons["landmarks.done"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))

        // Тап по значку відкриває картку з повною назвою.
        pin.tap()
        let name = app.staticTexts["landmark.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Товари для художників та творчості \"Майстриня\"")
    }

    func testCategoryMenuIsVerticalAndTogglesSeveral() {
        continueAfterFailure = false
        let app = UITest.launch(scenario: "poi")
        let list = app.buttons["landmarks.list.button"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        UITest.pause(3)
        list.tap()
        XCTAssertTrue(app.buttons["landmark.row.0"].waitForExistence(timeout: 5))
        guard let before = UITest.landmarksAhead(app) else { return XCTFail("немає заголовка «Попереду»") }

        let menu = app.buttons["list.filters"]
        XCTAssertTrue(menu.label.contains("Типи орієнтирів: 7 з 17"), menu.label)
        menu.tap()
        let stores = app.buttons["list.filter.store"]
        let food = app.buttons["list.filter.foodMarket"]
        let sights = app.buttons["list.filter.sight"]
        XCTAssertTrue(stores.waitForExistence(timeout: 3))
        // Типи один під одним, а не смугою вбік.
        XCTAssertEqual(stores.frame.minX, food.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(food.frame.minY, stores.frame.maxY - 1)
        // Меню не закривається: вимикаються кілька типів поспіль.
        stores.tap()
        XCTAssertTrue(food.waitForExistence(timeout: 2))
        food.tap()
        XCTAssertTrue(sights.exists)
        app.buttons["landmarks.refresh"].tap()  // тап поза меню закриває його
        XCTAssertTrue(stores.waitForNonExistence(timeout: 3))
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Типи орієнтирів: 5 з 17"), object: menu)
        XCTAssertEqual(XCTWaiter().wait(for: [updated], timeout: 3), .completed, menu.label)
        XCTAssertLessThan(UITest.landmarksAhead(app) ?? .max, before)
    }

    /// Число з «Запитів до MapKit: 14 · …».
    static func requestCount(_ label: String) -> Int? {
        guard let range = label.range(of: "Запитів до MapKit: ") else { return nil }
        return Int(label[range.upperBound...].prefix { $0.isNumber })
    }
}
