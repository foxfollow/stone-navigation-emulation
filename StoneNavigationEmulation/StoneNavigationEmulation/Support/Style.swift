import NavigationCore
import SwiftUI

enum Palette {
    static let gps = Color(red: 0.30, green: 0.55, blue: 1.0)
    static let deadReckoning = Color(red: 0.95, green: 0.65, blue: 0.23)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.37)
    static let success = Color(red: 0.24, green: 0.81, blue: 0.57)
    static let surface = Color(white: 0.10)
    static let surfaceRaised = Color(white: 0.17)
    static let secondaryText = Color(white: 0.68)

    static func color(for category: PlaceCategory) -> Color {
        switch category {
        case .gasStation: Color(red: 0.24, green: 0.81, blue: 0.57)
        case .evCharger: Color(red: 0.20, green: 0.75, blue: 0.90)
        case .store: Color(red: 0.66, green: 0.55, blue: 1.0)
        case .foodMarket: Color(red: 1.0, green: 0.56, blue: 0.67)
        case .pharmacy: Color(red: 0.95, green: 0.36, blue: 0.48)
        case .cafe: Color(red: 0.82, green: 0.58, blue: 0.36)
        case .restaurant: Color(red: 1.0, green: 0.60, blue: 0.20)
        case .postOffice: Color(red: 0.95, green: 0.78, blue: 0.22)
        case .bank: Color(red: 0.55, green: 0.80, blue: 0.30)
        case .hotel: Color(red: 0.50, green: 0.52, blue: 0.95)
        case .hospital: Color(red: 1.0, green: 0.30, blue: 0.30)
        case .carService: Color(red: 0.58, green: 0.64, blue: 0.70)
        case .parking: Color(red: 0.25, green: 0.50, blue: 0.95)
        case .police: Color(red: 0.32, green: 0.42, blue: 0.85)
        case .school: Color(red: 0.90, green: 0.70, blue: 0.40)
        case .park: Color(red: 0.32, green: 0.70, blue: 0.32)
        case .sight: Color(red: 0.80, green: 0.66, blue: 0.48)
        }
    }

    static func color(for mode: NavigationMode) -> Color {
        mode == .gps ? gps : deadReckoning
    }
}

/// Велика кнопка для користування за кермом: мінімум 60 pt заввишки, жирний шрифт.
struct BigButtonStyle: ButtonStyle {
    var background: Color = Palette.surfaceRaised
    var foreground: Color = .white
    var height: CGFloat = 60
    /// Нижня панель бере дрібніший шрифт і один рядок, щоб підписи не переносились.
    var font: Font = .title3.weight(.bold)
    var lineLimit = 2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .lineLimit(lineLimit)
            .minimumScaleFactor(lineLimit == 1 ? 0.6 : 0.7)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 6)
            .background(background.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Кругла кнопка збоку карти.
struct RoundIconButtonStyle: ButtonStyle {
    var tint: Color = .white
    var isOn = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(isOn ? tint : Palette.secondaryText)
            .frame(width: 50, height: 50)
            .background(Palette.surface.opacity(configuration.isPressed ? 0.7 : 0.92), in: Circle())
            .overlay(Circle().stroke(isOn ? tint.opacity(0.8) : Color(white: 0.3), lineWidth: 2))
            .opacity(isOn ? 1 : 0.75)
    }
}

extension TurnDirection {
    var symbolName: String {
        switch self {
        case .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.down"
        case .arrive: "flag.checkered"
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
