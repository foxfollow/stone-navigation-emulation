import Foundation
import Testing
@testable import NavigationCore

@Suite("Голосові тригери")
struct VoicePrompterTests {
    let route = TestRoute.make()

    @Test("Підказки на 300 і 100 м, на самому повороті і при прибутті, кожна один раз")
    func sequence() {
        var prompter = VoicePrompter()
        var spoken: [String] = []
        for along in stride(from: 0.0, through: 2000, by: 5) {
            spoken += prompter.update(along: along, route: route, settings: .standard)
        }
        #expect(spoken == [
            "Через 300 метрів поверніть праворуч на вулицю Другу",
            "Через 100 метрів поверніть праворуч на вулицю Другу",
            "Поверніть праворуч на вулицю Другу",
            "Через 300 метрів пункт призначення праворуч",
            "Через 100 метрів пункт призначення праворуч",
            VoicePrompter.arrivalPhrase,
        ])
    }

    @Test("Стрибок усередину порогу: одна підказка зі справжньою відстанню")
    func jumpInsideThreshold() {
        var prompter = VoicePrompter()
        #expect(prompter.update(along: 500, route: route, settings: .standard) == [])
        #expect(prompter.update(along: 940, route: route, settings: .standard) == ["Через 60 метрів поверніть праворуч на вулицю Другу"])
        #expect(prompter.update(along: 945, route: route, settings: .standard) == [])
    }

    @Test("Дистанції підказок беруться з Налаштувань")
    func customDistances() {
        var settings = NavigationSettings()
        settings[.voiceFarDistance] = 800
        settings[.voiceNearDistance] = 200
        var prompter = VoicePrompter()
        #expect(prompter.update(along: 150, route: route, settings: settings) == [])
        // Точки на 5 м усередині порогів: рівно на межі вирішує похибка плаваючої коми.
        #expect(prompter.update(along: 205, route: route, settings: settings) == ["Через 800 метрів поверніть праворуч на вулицю Другу"])
        #expect(prompter.update(along: 790, route: route, settings: settings) == [])
        #expect(prompter.update(along: 805, route: route, settings: settings) == ["Через 200 метрів поверніть праворуч на вулицю Другу"])
    }

    @Test("Пройдені маневри не озвучуються після відновлення")
    func skipsPassed() {
        var prompter = VoicePrompter()
        #expect(prompter.update(along: 1200, route: route, settings: .standard) == [])
    }

    @Test("Українська множина відстаней", arguments: [
        (1.0, "1 метр"), (2.0, "2 метри"), (5.0, "5 метрів"), (11.0, "11 метрів"), (21.0, "21 метр"),
        (22.0, "22 метри"), (300.0, "300 метрів"), (1000.0, "1 кілометр"), (2000.0, "2 кілометри"),
        (5000.0, "5 кілометрів"), (1500.0, "1,5 кілометра"),
    ])
    func plural(meters: Double, expected: String) {
        #expect(UkrainianFormat.spokenDistance(meters) == expected)
    }

    @Test("Короткі відстані й час для екрана")
    func screenFormats() {
        #expect(UkrainianFormat.distance(84) == "80 м")
        #expect(UkrainianFormat.distance(340) == "350 м")
        #expect(UkrainianFormat.distance(1240) == "1,2 км")
        #expect(UkrainianFormat.distance(12_600) == "13 км")
        #expect(UkrainianFormat.timer(134) == "02:14")
        #expect(UkrainianFormat.timer(3734) == "1:02:14")
        #expect(UkrainianFormat.duration(720) == "12 хв")
        #expect(UkrainianFormat.duration(3900) == "1 год 05 хв")
        #expect(UkrainianFormat.speed(50 / 3.6) == "50 км/год")
    }
}

@Suite("Голос у сесії")
@MainActor
struct VoiceSessionTests {
    @Test("Сесія озвучує поворот, а вимкнений голос мовчить")
    func speaks() {
        let h = SessionHarness()
        h.session.begin(route: TestRoute.make(), destination: nil)
        h.session.selectDeadReckoning()
        for _ in 0..<75 { h.advance(1) }
        #expect(h.speech.spoken.first == "Через 300 метрів поверніть праворуч на вулицю Другу")

        var silent = NavigationSettings()
        silent[.voiceEnabled] = false
        let quiet = SessionHarness(settings: silent)
        quiet.session.begin(route: TestRoute.make(), destination: nil)
        quiet.session.selectDeadReckoning()
        for _ in 0..<75 { quiet.advance(1) }
        #expect(quiet.speech.spoken.isEmpty)
    }
}
