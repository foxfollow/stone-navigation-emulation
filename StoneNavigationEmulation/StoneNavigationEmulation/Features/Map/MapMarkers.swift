import NavigationCore
import SwiftUI

/// Моя позиція: синє коло з GPS, бурштиновий ромб у розрахунковому режимі.
struct PositionMarker: View {
    let mode: NavigationMode
    let rotation: Double
    /// Чи стежить камера за позицією і з якої висоти: для VoiceOver і UI-тестів.
    var following = ""

    var body: some View {
        let color = Palette.color(for: mode)
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 60, height: 60)
            if mode == .deadReckoning {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 3))
                    .rotationEffect(.degrees(45))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
            }
            Image(systemName: "location.north.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(rotation))
        }
        // Значок посеред карти: щипок і перетягування навколо нього мають діставатися карті.
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityIdentifier("map.position")
        .accessibilityLabel(mode == .gps ? "Моя позиція з GPS" : "Розрахункова позиція")
        .accessibilityValue(following)
    }
}

/// Де GPS «бачить» мене, коли я в розрахунковому режимі.
struct GhostGPSMarker: View {
    let isSuspicious: Bool

    var body: some View {
        let color = isSuspicious ? Palette.danger : Color(white: 0.6)
        VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(isSuspicious ? "GPS?" : "GPS")
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
        .allowsHitTesting(false)
    }
}

/// Орієнтир на карті: значок за типом із трикутником, вістря якого точно на місці, і підпис збоку з назвою
/// та відстанню. Підпис з того боку, куди орієнтир відходить від дороги, тож лінію маршруту він не закриває.
/// Довга назва скорочена до трьох слів: тап по підпису розгортає її, тап по значку відкриває картку орієнтира.
struct LandmarkMarker: View {
    let landmark: Landmark
    let distanceAhead: Double
    var isAtTurn = false
    /// З якого боку від значка на екрані підпис.
    let labelSide: RoadSide
    /// Скільки місця на екрані є для тексту підпису з цього боку.
    var maxTextWidth = LandmarkMarker.widestText
    var isExpanded = false
    let onSelect: () -> Void
    let onToggleName: () -> Void

    static let nameSize: CGFloat = 13
    static let detailSize: CGFloat = 12
    /// Ширше за це підпис не буває: довша назва переноситься.
    static let widestText: CGFloat = 160
    /// Вужче назва вже погано читається: тоді підпис переходить на інший бік значка.
    static let narrowestText: CGFloat = 56
    static let labelPadding: CGFloat = 6
    static let spacing: CGFloat = 3
    static let tipSize = CGSize(width: 12, height: 8)
    /// Праворуч край карти закривають кнопки бічної колонки.
    static let rightInset: CGFloat = 66
    static let edgeMargin: CGFloat = 4

    static func pinDiameter(isAtTurn: Bool) -> CGFloat { isAtTurn ? 38 : 30 }
    var pinDiameter: CGFloat { Self.pinDiameter(isAtTurn: isAtTurn) }
    var isShortened: Bool { LandmarkName.isShortened(landmark.place.name) }
    var name: String { isExpanded ? landmark.place.name : landmark.place.shortName }

    var detail: String {
        let distance = distanceAhead < 10 ? "поруч" : UkrainianFormat.distance(distanceAhead)
        return isAtTurn ? "поворот · \(distance)" : distance
    }

    /// Бік і ширина підпису, щоб він не виходив за край екрана. Спершу бік від дороги (`preferred`):
    /// у вужчому підписі назва переноситься на другий рядок. Якщо місця менше за `narrowestText`,
    /// а з іншого боку є, підпис переходить туди.
    static func placement(at point: CGPoint?, preferred: RoadSide, mapWidth: CGFloat, isAtTurn: Bool) -> (side: RoadSide, maxTextWidth: CGFloat) {
        guard let point else { return (preferred, widestText) }
        let reach = pinDiameter(isAtTurn: isAtTurn) / 2 + spacing + 2 * labelPadding
        let left = point.x - reach - edgeMargin
        let right = mapWidth - rightInset - point.x - reach
        let room = preferred == .left ? left : right
        let other = preferred == .left ? right : left
        if room < narrowestText, other >= narrowestText {
            return (preferred == .left ? .right : .left, min(other, widestText))
        }
        return (preferred, min(max(room, narrowestText), widestText))
    }

    /// Ширина підпису з відступами. Рахуємо її наперед, щоб знати, де вістря трикутника.
    var labelWidth: CGFloat {
        let text = max(
            Self.measure(name, size: Self.nameSize, weight: .semibold),
            Self.measure(detail, size: Self.detailSize, weight: .medium)
        )
        return min(text, maxTextWidth) + 2 * Self.labelPadding
    }

    /// Точка прив'язки до координати місця: вістря трикутника під значком.
    var anchor: UnitPoint {
        let total = labelWidth + Self.spacing + pinDiameter
        let tip = labelSide == .left ? total - pinDiameter / 2 : pinDiameter / 2
        return UnitPoint(x: tip / total, y: 1)
    }

    /// Ширина рядка з запасом: SwiftUI малює системний шрифт трохи ширше, ніж міряє UIKit.
    static func measure(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]).width
        return (width * 1.04).rounded(.up) + 4
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            if labelSide == .left {
                label
                pin
            } else {
                pin
                label
            }
        }
        .foregroundStyle(.white)
    }

    private var color: Color { Palette.color(for: landmark.place.category) }

    private var pin: some View {
        Button(action: onSelect) {
            VStack(spacing: -1) {
                Image(systemName: landmark.place.category.symbolName)
                    .font(.system(size: isAtTurn ? 17 : 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: pinDiameter, height: pinDiameter)
                    .background(color, in: Circle())
                    .overlay(Circle().stroke(isAtTurn ? .white : .black.opacity(0.6), lineWidth: isAtTurn ? 3 : 2))
                PinTip()
                    .fill(isAtTurn ? .white : color)
                    .frame(width: Self.tipSize.width, height: Self.tipSize.height)
            }
        }
        .buttonStyle(.plain)
        .frame(width: pinDiameter)
        .accessibilityLabel("\(landmark.place.category.singular): \(landmark.place.name)")
        .accessibilityIdentifier("landmark.pin.\(landmark.id)")
    }

    private var label: some View {
        let isLeft = labelSide == .left
        return Button {
            if isShortened { onToggleName() } else { onSelect() }
        } label: {
            VStack(alignment: isLeft ? .trailing : .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: Self.nameSize, weight: .semibold))
                    .lineLimit(isExpanded ? 6 : 3)
                    .multilineTextAlignment(isLeft ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: Self.detailSize, weight: .medium))
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .multilineTextAlignment(isLeft ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Self.labelPadding)
            .padding(.vertical, 3)
            // Тло по тексту: перенесена назва вужча за відведене місце.
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            .frame(width: labelWidth, alignment: isLeft ? .trailing : .leading)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isShortened ? (isExpanded ? "повна назва" : "скорочена назва") : "")
        .accessibilityHint(isShortened ? (isExpanded ? "Скоротити назву" : "Показати повну назву") : "Відкрити картку орієнтира")
        .accessibilityIdentifier("landmark.label.\(landmark.id)")
    }
}

/// Трикутник під значком орієнтира вістрям униз, на саме місце.
struct PinTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
