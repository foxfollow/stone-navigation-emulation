import MapKit
import NavigationCore
import SwiftUI

/// Картка орієнтира. Головна дія: підтвердити, що я зараз біля нього (корекція позиції).
struct LandmarkCardView: View {
    let landmark: Landmark
    @Environment(NavigationSession.self) private var session
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var detailItem: MKMapItem?
    @State private var isLoadingDetails = false

    var body: some View {
        let color = Palette.color(for: landmark.place.category)
        let ahead = landmark.along - session.engine.along
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: landmark.place.category.symbolName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(color, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(landmark.place.name)
                            .font(.title2.bold())
                            .accessibilityIdentifier("landmark.name")
                        Text(landmark.place.category.singular)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(ahead >= 0 ? "Через \(UkrainianFormat.distance(ahead)) по маршруту" : "Позаду \(UkrainianFormat.distance(-ahead)) по маршруту",
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.title3.bold())
                        .accessibilityIdentifier("landmark.distance")
                    Label("\(landmark.side.title.capitalizedFirst) · \(Int(landmark.offset.rounded())) м від дороги",
                          systemImage: landmark.side == .left ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                        .font(.title3)
                        .accessibilityIdentifier("landmark.side")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    session.confirmLandmark(landmark)
                    close()
                } label: {
                    Label("Я біля нього: підтвердити позицію", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(BigButtonStyle(background: Palette.success, foreground: .black, height: 66))
                .accessibilityIdentifier("landmark.confirm")

                HStack(spacing: 10) {
                    Button {
                        Task { await session.addStop(landmark) }
                        close()
                    } label: {
                        Label("Додати як зупинку", systemImage: "plus.circle")
                    }
                    .buttonStyle(BigButtonStyle(height: 56))
                    .accessibilityIdentifier("landmark.addStop")

                    Button {
                        Task { await loadDetails() }
                    } label: {
                        if isLoadingDetails {
                            ProgressView()
                        } else {
                            Label("Детальніше", systemImage: "info.circle")
                        }
                    }
                    .buttonStyle(BigButtonStyle(height: 56))
                    .accessibilityIdentifier("landmark.details")
                }
                Text("«Детальніше» відкриває системну картку MapKit: там графік роботи і телефон.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(20)
        }
        .accessibilityIdentifier("landmark.card")
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.surface)
        .mapItemDetailSheet(item: $detailItem)
    }

    private func close() {
        app.selectedLandmark = nil
        app.showLandmarkList = false
        dismiss()
    }

    private func loadDetails() async {
        isLoadingDetails = true
        detailItem = await MapItemDetails.mapItem(for: landmark.place)
        isLoadingDetails = false
    }
}
