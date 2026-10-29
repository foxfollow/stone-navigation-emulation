import NavigationCore
import SwiftUI

/// Усі орієнтири на маршруті: можна вибрати і підтвердити позицію. Згори кнопка «Оновити поруч» і короткий стан
/// завантаження, внизу подробиці, щоб було видно, що орієнтири справді приходять від MapKit.
struct LandmarkListView: View {
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        let along = session.engine.along
        let visible = session.visibleLandmarks
        let ahead = visible.filter { $0.along >= along - 20 }
        let behind = visible.filter { $0.along < along - 20 }.reversed()
        let atTurns = Set(session.turnLandmarks(within: .infinity).map(\.id))
        NavigationStack {
            List {
                Section {
                    LandmarkRefreshRow()
                }
                Section {
                    CategoryFilterMenu()
                }
                if visible.isEmpty {
                    Section {
                        Text("Орієнтирів у коридорі \(Int(session.settings[.landmarkCorridor])) м від дороги поки немає. Коридор можна розширити вище або в Налаштуваннях.")
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                if !ahead.isEmpty {
                    Section {
                        ForEach(Array(ahead.enumerated()), id: \.element.id) { index, landmark in
                            NavigationLink(value: landmark) {
                                LandmarkRow(landmark: landmark, along: along, isAtTurn: atTurns.contains(landmark.id))
                            }
                            .accessibilityIdentifier("landmark.row.\(index)")
                        }
                    } header: {
                        Text("Попереду · \(ahead.count)")
                            .accessibilityIdentifier("landmarks.ahead")
                    }
                }
                if !behind.isEmpty {
                    Section("Позаду") {
                        ForEach(Array(behind)) { landmark in
                            NavigationLink(value: landmark) {
                                LandmarkRow(landmark: landmark, along: along, isAtTurn: false)
                            }
                        }
                    }
                }
                Section("Завантаження") {
                    LandmarkLoadDetails()
                }
            }
            .navigationTitle("Орієнтири")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Landmark.self) { landmark in
                LandmarkCardView(landmark: landmark)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { app.showLandmarkList = false }
                        .accessibilityIdentifier("landmarks.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// «Оновити поруч» і коротко: скільки попереду вже завантажено і скільки було запитів.
private struct LandmarkRefreshRow: View {
    @Environment(NavigationSession.self) private var session

    var body: some View {
        let status = session.landmarkStatus
        HStack(spacing: 12) {
            Button {
                session.refreshLandmarks()
            } label: {
                Group {
                    if status.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.title3.bold())
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Palette.gps, in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Оновити орієнтири поруч")
            .accessibilityHint("Заново запитати орієнтири на 2 км попереду і біля найближчого повороту")
            .accessibilityIdentifier("landmarks.refresh")
            VStack(alignment: .leading, spacing: 2) {
                Text("Попереду завантажено: \(UkrainianFormat.distance(status.coverageAhead))")
                    .font(.subheadline.bold())
                    .accessibilityIdentifier("landmarks.coverage")
                if let error = status.lastError {
                    Text(LandmarkLoadDetails.errorText(error, retryAt: status.retryAt, now: session.now))
                        .font(.subheadline.bold())
                        .foregroundStyle(Palette.danger)
                        .lineLimit(2)
                        .accessibilityIdentifier("landmarks.error")
                } else {
                    Text(status.isLoading ? "Завантажую… Запитів до MapKit: \(status.requests)" : "Запитів до MapKit: \(status.requests)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityIdentifier("landmarks.requests")
                }
            }
        }
    }
}

/// Подробиці завантаження: остання відповідь, скільки місць біля дороги, ширина коридору, примітка про мову.
private struct LandmarkLoadDetails: View {
    @Environment(NavigationSession.self) private var session
    @Environment(SettingsModel.self) private var settingsModel

    var body: some View {
        let status = session.landmarkStatus
        let corridor = settingsModel.settings[.landmarkCorridor]
        VStack(alignment: .leading, spacing: 8) {
            if let last = status.lastSuccessAt {
                Text("Остання відповідь \(max(0, Int(session.now.timeIntervalSince(last)))) с тому, місць у ній: \(status.lastFound). Невдалих запитів: \(status.failures)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .accessibilityIdentifier("landmarks.last")
            }
            HStack(spacing: 10) {
                Text("Біля дороги (до \(Int(corridor)) м): \(session.landmarks.count) з \(session.landmarkCandidates.count) знайдених")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("landmarks.found")
                Spacer(minLength: 4)
                Button {
                    settingsModel.decrement(.landmarkCorridor)
                } label: {
                    Image(systemName: "minus").frame(width: 30, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(corridor <= SettingKey.landmarkCorridor.spec.range.lowerBound)
                .accessibilityLabel("Вужчий коридор")
                .accessibilityIdentifier("landmarks.corridor.minus")
                Button {
                    settingsModel.increment(.landmarkCorridor)
                } label: {
                    Image(systemName: "plus").frame(width: 30, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(corridor >= SettingKey.landmarkCorridor.spec.range.upperBound)
                .accessibilityLabel("Ширший коридор")
                .accessibilityIdentifier("landmarks.corridor.plus")
            }
            Text("Місця шукаються за типом, а не за текстом, тож мова телефону на пошук не впливає. Назви приходять такими, як їх знає Apple Maps.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.vertical, 4)
    }

    static func errorText(_ error: String, retryAt: Date?, now: Date) -> String {
        guard let retryAt else { return error }
        let wait = Int(retryAt.timeIntervalSince(now).rounded(.up))
        return wait > 0 ? "\(error). Повтор через \(wait) с" : error
    }
}

private struct LandmarkRow: View {
    let landmark: Landmark
    let along: Double
    let isAtTurn: Bool

    var body: some View {
        let distance = landmark.along - along
        HStack(spacing: 12) {
            Image(systemName: landmark.place.category.symbolName)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Palette.color(for: landmark.place.category), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                // Довга назва скорочена до трьох слів, повна в картці орієнтира.
                Text(landmark.place.shortName).font(.headline)
                if isAtTurn {
                    Label("біля повороту", systemImage: "arrow.turn.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(Palette.gps)
                }
                Text("\(distance >= 0 ? "через" : "позаду") \(UkrainianFormat.distance(abs(distance))) · \(landmark.side.title) · \(Int(landmark.offset.rounded())) м від дороги")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Типи орієнтирів: тап відкриває список усіх типів згори вниз; меню не закривається, тож можна перемкнути кілька.
struct CategoryFilterMenu: View {
    @Environment(SettingsModel.self) private var settingsModel

    var body: some View {
        let enabled = settingsModel.settings.enabledCategories
        let names = PlaceCategory.allCases.filter(enabled.contains).map(\.title)
        Menu {
            CategoryToggles(identifierPrefix: "list.filter")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Типи орієнтирів: \(enabled.count) з \(PlaceCategory.allCases.count)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(names.isEmpty ? "Усі типи вимкнено" : names.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.bold())
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuActionDismissBehavior(.disabled)
        .accessibilityIdentifier("list.filters")
    }
}

/// Перемикачі всіх типів орієнтирів для меню фільтрів на карті і в списку.
struct CategoryToggles: View {
    let identifierPrefix: String
    @Environment(SettingsModel.self) private var settingsModel

    var body: some View {
        ForEach(PlaceCategory.allCases) { category in
            let toggle = SettingToggle.filter(for: category)
            Toggle(isOn: Binding(get: { settingsModel.settings[toggle] }, set: { settingsModel.set(toggle, $0) })) {
                Label(category.title, systemImage: category.symbolName)
            }
            .accessibilityIdentifier("\(identifierPrefix).\(category.rawValue)")
        }
    }
}
