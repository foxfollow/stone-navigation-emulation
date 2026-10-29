import NavigationCore
import SwiftUI

/// Усі числа зі специфікації: у межах, зберігаються між запусками, є «Скинути до стандартних».
struct SettingsView: View {
    @Environment(SettingsModel.self) private var model
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app
    @State private var confirmReset = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Picker("Кнопки швидкості", selection: $app.isLeftHanded) {
                        Text("Правша").tag(false)
                        Text("Лівша").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.hand")
                } header: {
                    Text("Нижня панель")
                } footer: {
                    Text(app.isLeftHanded
                         ? "Швидкість і зсув біля лівого краю, під великий палець лівої руки."
                         : "Швидкість і зсув біля правого краю, під великий палець правої руки.")
                }

                ForEach(SettingSection.allCases) { section in
                    Section {
                        ForEach(SettingToggle.allCases.filter { $0.section == section }) { toggle in
                            Toggle(toggle.title, isOn: Binding(
                                get: { model.settings[toggle] },
                                set: { model.set(toggle, $0) }
                            ))
                            .font(.body.weight(.semibold))
                            .accessibilityIdentifier("settings.toggle.\(toggle.rawValue)")
                        }
                        ForEach(SettingKey.allCases.filter { $0.spec.section == section }) { key in
                            SettingRow(key: key)
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        footer(for: section)
                    }
                }

                Section {
                    NavigationLink("Режим тестування: GPX") {
                        TestModeView()
                    }
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("settings.testMode")
                }

                Section {
                    Button("Скинути до стандартних", role: .destructive) {
                        confirmReset = true
                    }
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("settings.reset")
                }
            }
            .navigationTitle("Налаштування")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { app.showSettings = false }
                        .font(.headline)
                        .accessibilityIdentifier("settings.done")
                }
            }
            .confirmationDialog("Скинути всі налаштування до стандартних?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Скинути", role: .destructive) { model.resetToDefaults() }
                    .accessibilityIdentifier("settings.reset.confirm")
                Button("Скасувати", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func footer(for section: SettingSection) -> some View {
        switch section {
        case .switching:
            Text("Повернення на GPS має гістерезис: точність має бути кращою за нижній поріг протягом заданого часу.")
        case .spoofing:
            Text("Якщо GPS далі за межу від розрахункової позиції, додаток питає, чи переходити на GPS.")
        case .voice:
            if session.isVoiceAvailable {
                Text("Голос uk-UA встановлено. Підказки звучать поверх музики і через динаміки авто.")
            } else {
                Text("Українського голосу немає. Завантажте: Параметри → Універсальний доступ → Вміст, що озвучується → Голоси → Українська.")
                    .accessibilityIdentifier("settings.voice.hint")
            }
        case .landmarks:
            Text("Коридор це максимальна відстань орієнтира від лінії дороги. Пошук іде вздовж маршруту, тож працює і без GPS.")
        case .screen:
            Text("Під час довгої їзди тримайте телефон на зарядці: увімкнений екран, GPS і голос швидко розряджають батарею. Затемнення знімається будь-яким дотиком і не зупиняє навігацію.")
                .accessibilityIdentifier("settings.charging.hint")
        case .sensors:
            Text("Стоянка за датчиками зупиняє розрахункову точку. Поворот за гіроскопом пропонує підтягнути точку до повороту маршруту.")
        case .movement, .route:
            EmptyView()
        }
    }
}

/// Рядок числового налаштування: назва, межі, великі кнопки − і +.
private struct SettingRow: View {
    let key: SettingKey
    @Environment(SettingsModel.self) private var model

    var body: some View {
        let spec = key.spec
        let value = model.settings[key]
        VStack(alignment: .leading, spacing: 8) {
            Text(spec.title)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(SettingsModel.formatRange(for: key))
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Palette.secondaryText)
                Spacer(minLength: 4)
                Button {
                    model.decrement(key)
                } label: {
                    Image(systemName: "minus").font(.headline.bold()).frame(width: 36, height: 30)
                }
                .buttonStyle(.bordered)
                .disabled(value <= spec.range.lowerBound)
                .accessibilityLabel("Зменшити")
                .accessibilityIdentifier("settings.\(key.rawValue).minus")
                Text(SettingsModel.format(value, for: key))
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 96)
                    .accessibilityIdentifier("settings.\(key.rawValue).value")
                Button {
                    model.increment(key)
                } label: {
                    Image(systemName: "plus").font(.headline.bold()).frame(width: 36, height: 30)
                }
                .buttonStyle(.bordered)
                .disabled(value >= spec.range.upperBound)
                .accessibilityLabel("Збільшити")
                .accessibilityIdentifier("settings.\(key.rawValue).plus")
            }
        }
        .padding(.vertical, 4)
    }
}
