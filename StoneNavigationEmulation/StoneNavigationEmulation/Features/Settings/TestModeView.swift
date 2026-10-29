import NavigationCore
import SwiftUI

/// Режим тестування вдома: програвання GPX-треку з імітацією зникнення GPS і стрибка позиції.
struct TestModeView: View {
    @Environment(AppModel.self) private var app
    @State private var simulateLoss = true
    @State private var lossStart: Double = 30
    @State private var lossDuration: Double = 40
    @State private var simulateJump = true
    @State private var jumpStart: Double = 120
    @State private var jumpDuration: Double = 30
    @State private var jumpDistance: Double = 1500

    var body: some View {
        Form {
            Section {
                Text("Програє записаний трек test_track.gpx уздовж тестового маршруту Майдан Незалежності → Дарницька площа (Київ). Геолокація телефона на час програвання вимикається.")
                    .font(.subheadline)
            }
            Section("Зникнення GPS") {
                Toggle("Імітувати зникнення", isOn: $simulateLoss)
                    .accessibilityIdentifier("testmode.loss")
                Stepper("Початок: \(Int(lossStart)) с", value: $lossStart, in: 5...600, step: 5)
                Stepper("Тривалість: \(Int(lossDuration)) с", value: $lossDuration, in: 5...600, step: 5)
            }
            Section("Стрибок позиції (підміна)") {
                Toggle("Імітувати стрибок", isOn: $simulateJump)
                    .accessibilityIdentifier("testmode.jump")
                Stepper("Початок: \(Int(jumpStart)) с", value: $jumpStart, in: 5...600, step: 5)
                Stepper("Тривалість: \(Int(jumpDuration)) с", value: $jumpDuration, in: 5...600, step: 5)
                Stepper("Зсув: \(UkrainianFormat.distance(jumpDistance))", value: $jumpDistance, in: 100...5000, step: 100)
            }
            Section {
                if app.replayRunning {
                    Button("Зупинити програвання", role: .destructive) { app.stopReplay() }
                        .accessibilityIdentifier("testmode.stop")
                } else {
                    Button("Запустити програвання") {
                        app.startReplay(options: ReplayOptions(
                            lossStart: simulateLoss ? lossStart : nil,
                            lossDuration: lossDuration,
                            jumpStart: simulateJump ? jumpStart : nil,
                            jumpDuration: jumpDuration,
                            jumpDistance: jumpDistance
                        ))
                        app.showSettings = false
                    }
                    .font(.headline)
                    .accessibilityIdentifier("testmode.start")
                }
            }
        }
        .navigationTitle("Режим тестування")
    }
}
