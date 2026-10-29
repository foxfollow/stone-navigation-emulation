import NavigationCore
import SwiftUI

/// Великий запит «GPS показує інше місце. Перейти на GPS?». За замовчуванням виділено «Лишити розрахункову».
struct SpoofPromptView: View {
    let prompt: SpoofPrompt
    @Environment(NavigationSession.self) private var session

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("МОЖЛИВА ПІДМІНА GPS")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(Palette.danger)
                Text("GPS показує інше місце. Перейти на GPS?")
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("spoof.prompt")
                Text("Нова точка за \(UkrainianFormat.distance(prompt.distance)) від розрахункової позиції, точність ±\(Int(prompt.fix.horizontalAccuracy.rounded())) м. Авто не могло так швидко переміститися.")
                    .font(.body)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    session.keepDeadReckoning()
                } label: {
                    Label("Лишити розрахункову", systemImage: "diamond.fill")
                }
                .buttonStyle(BigButtonStyle(background: Palette.deadReckoning, foreground: .black, height: 68))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("spoof.keep")
                Button("Перейти на GPS") {
                    session.acceptSpoofPrompt()
                }
                .buttonStyle(BigButtonStyle(height: 56))
                .accessibilityIdentifier("spoof.switch")
            }
            .padding(20)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Palette.danger, lineWidth: 2))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}
