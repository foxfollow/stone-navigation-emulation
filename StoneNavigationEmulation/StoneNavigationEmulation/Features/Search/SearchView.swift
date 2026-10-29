import NavigationCore
import SwiftUI

/// Пошук пункту призначення: MKLocalSearchCompleter → MKLocalSearch → MKDirections.
/// Рядок «Звідки» перемикає той самий пошук на вибір точки відправлення.
/// Без тексту видно дім, роботу, збережені й останні адреси; з текстом ті з них, що підходять, стоять над підказками.
struct SearchView: View {
    @Environment(NavigationSession.self) private var session
    @Environment(SearchModel.self) private var search
    @Environment(SavedPlacesModel.self) private var saved
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool
    @State private var target = Target.destination

    private enum Target: Equatable {
        case destination, origin
        /// Вибрана далі адреса стане домом, роботою або збереженою.
        case saving(SavedPlaces.Kind)
    }

    var body: some View {
        @Bindable var search = search
        let query = search.query.trimmingCharacters(in: .whitespaces)
        let matches = saved.places.matching(query)
        NavigationStack {
            List {
                Section {
                    if case .saving = target {} else {
                        originRow
                    }
                    TextField(placeholder, text: $search.query)
                        .font(.title3)
                        .focused($focused)
                        .submitLabel(.search)
                        .accessibilityIdentifier("search.field")
                }
                if let error = search.error {
                    Section {
                        Text(error)
                            .foregroundStyle(Palette.danger)
                            .accessibilityIdentifier("search.error")
                    }
                }
                if query.isEmpty {
                    myPlaces
                    recents
                } else if !matches.isEmpty {
                    Section("Мої адреси") {
                        ForEach(matches) { entryRow($0) }
                    }
                }
                Section {
                    ForEach(search.suggestions) { suggestion in
                        Button {
                            Task { await choose(suggestion) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title).font(.headline)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle).font(.subheadline).foregroundStyle(Palette.secondaryText)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .contextMenu {
                            saveMenu(except: nil) { kind in
                                Task { await save(suggestion, as: kind) }
                            }
                        }
                    }
                } footer: {
                    Text(footer)
                }
            }
            // Прокрутка ховає клавіатуру, щоб було видно всі збережені й останні адреси.
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(target == .destination ? "Закрити" : "Назад") {
                        if target == .destination {
                            app.showSearch = false
                        } else {
                            switchTarget(to: .destination)
                        }
                    }
                    .accessibilityIdentifier("search.close")
                }
            }
            // Є мої чи останні адреси: показуємо їх без клавіатури, тап по полю її відкриває.
            .onAppear { focused = saved.places.pinned.isEmpty && saved.places.recentEntries.isEmpty }
        }
    }

    private var title: String {
        switch target {
        case .destination: "Куди їдемо?"
        case .origin: "Звідки їдемо?"
        case .saving(.home): "Адреса дому"
        case .saving(.work): "Адреса роботи"
        case .saving: "Зберегти адресу"
        }
    }

    private var placeholder: String {
        switch target {
        case .destination: "Куди: адреса або місце"
        case .origin: "Звідки: адреса або місце"
        case .saving: "Адреса або місце"
        }
    }

    private var footer: String {
        switch target {
        case .origin:
            "Старт також можна вибрати довгим тапом на карті: «Звідси». Якщо GPS показує інше місце, точка чекає на старті, доки не натиснете «Далі»."
        case .saving:
            "Виберіть адресу з підказок або з останніх."
        case .destination:
            "Також можна вибрати точку довгим тапом на карті. Довгий тап по адресі зберігає її як дім, роботу чи збережену. Маршрут зберігається на телефоні, тож далі навігація працює без інтернету."
        }
    }

    /// Дім, робота, збережені. Порожні дім і робота пропонують додати адресу.
    @ViewBuilder
    private var myPlaces: some View {
        let pinned = saved.places.pinned
        let isSaving = if case .saving = target { true } else { false }
        Section("Мої адреси") {
            ForEach(pinned.filter { $0.kind == .home }) { entryRow($0) }
            if saved.places.home == nil, !isSaving { addRow(.home) }
            ForEach(pinned.filter { $0.kind == .work }) { entryRow($0) }
            if saved.places.work == nil, !isSaving { addRow(.work) }
            ForEach(pinned.filter { $0.kind == .favorite }) { entryRow($0) }
            if !isSaving { addRow(.favorite) }
        }
    }

    @ViewBuilder
    private var recents: some View {
        let entries = saved.places.recentEntries
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entryRow($0) }
            } header: {
                HStack {
                    Text("Останні")
                    Spacer()
                    Button("Очистити") { saved.clearRecents() }
                        .font(.footnote.bold())
                        .accessibilityIdentifier("saved.recent.clear")
                }
            }
        }
    }

    private func entryRow(_ entry: SavedPlaces.Entry) -> some View {
        let isNamed = entry.kind == .home || entry.kind == .work
        let color = Self.color(for: entry.kind)
        let detail = (isNamed ? [entry.place.name, entry.place.subtitle] : [entry.place.subtitle])
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return Button {
            Task { await use(entry.place) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.kind.symbolName)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNamed ? entry.kind.title : entry.place.name).font(.headline)
                    if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryText).lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier(entry.id)
        .contextMenu {
            saveMenu(except: entry.kind) { kind in saved.store(entry.place, as: kind) }
            Button("Прибрати", systemImage: "trash", role: .destructive) { saved.remove(entry) }
        }
        .swipeActions {
            Button("Прибрати", role: .destructive) { saved.remove(entry) }
        }
    }

    private func addRow(_ kind: SavedPlaces.Kind) -> some View {
        Button {
            switchTarget(to: .saving(kind))
        } label: {
            Label(
                kind == .home ? "Додати дім" : kind == .work ? "Додати роботу" : "Зберегти адресу",
                systemImage: kind == .favorite ? "plus.circle" : kind.symbolName
            )
            .font(.headline)
            .foregroundStyle(Self.color(for: kind))
            .frame(minHeight: 38)
        }
        .accessibilityIdentifier("saved.\(kind.rawValue).add")
    }

    /// Пункти контекстного меню: зробити домом, роботою або зберегти.
    @ViewBuilder
    private func saveMenu(except current: SavedPlaces.Kind?, action: @escaping (SavedPlaces.Kind) -> Void) -> some View {
        if current != .home { Button("Зробити домом", systemImage: "house") { action(.home) } }
        if current != .work { Button("Зробити роботою", systemImage: "briefcase") { action(.work) } }
        if current != .favorite { Button("Зберегти", systemImage: "star") { action(.favorite) } }
    }

    static func color(for kind: SavedPlaces.Kind) -> Color {
        switch kind {
        case .home: Palette.gps
        case .work: Palette.deadReckoning
        case .favorite: Color(red: 1.0, green: 0.82, blue: 0.3)
        case .recent: Palette.secondaryText
        }
    }

    /// «Звідки»: моя позиція або вибрана точка. Тап перемикає пошук на вибір старту.
    private var originRow: some View {
        HStack(spacing: 10) {
            Button {
                switchTarget(to: target == .origin ? .destination : .origin)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: app.plannedOrigin == nil ? "location.fill" : "mappin.circle.fill")
                        .foregroundStyle(app.plannedOrigin == nil ? Palette.gps : Palette.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Звідки").font(.footnote).foregroundStyle(Palette.secondaryText)
                        Text(app.plannedOrigin?.name ?? "Моя позиція")
                            .font(.headline)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if target == .destination {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(Palette.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Змінити точку відправлення")
            .accessibilityIdentifier("search.origin")
            if app.plannedOrigin != nil {
                Button {
                    app.plannedOrigin = nil
                } label: {
                    Image(systemName: "location.circle")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.gps)
                .accessibilityLabel("Від моєї позиції")
                .accessibilityIdentifier("search.origin.reset")
            }
        }
    }

    private func switchTarget(to newTarget: Target) {
        target = newTarget
        search.clear()
        focused = true
    }

    private func choose(_ suggestion: PlaceSuggestion) async {
        guard let place = await search.resolve(suggestion) else { return }
        await use(place)
    }

    /// Вибрана адреса: старт, нова збережена адреса або пункт призначення.
    private func use(_ place: Place) async {
        switch target {
        case .origin:
            app.plannedOrigin = place
            switchTarget(to: .destination)
        case .saving(let kind):
            saved.store(place, as: kind)
            switchTarget(to: .destination)
        case .destination:
            app.showSearch = false
            search.clear()
            await app.go(to: place)
        }
    }

    private func save(_ suggestion: PlaceSuggestion, as kind: SavedPlaces.Kind) async {
        guard let place = await search.resolve(suggestion) else { return }
        saved.store(place, as: kind)
    }
}
