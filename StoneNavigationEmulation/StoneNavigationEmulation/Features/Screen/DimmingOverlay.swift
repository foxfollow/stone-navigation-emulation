import SwiftUI
import UIKit

/// Необов'язкове затемнення після бездіяльності. Яскравість не змінює, навігацію не зупиняє,
/// знімається будь-яким дотиком.
struct DimmingOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Color.black.opacity(0.88)
            .ignoresSafeArea()
            .overlay {
                Text("Торкніться, щоб повернути екран")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .contentShape(Rectangle())
            .onTapGesture { app.registerInteraction() }
            .accessibilityIdentifier("dim.overlay")
    }
}

/// Спостерігач дотиків на рівні вікна: бачить усі дотики і нічого не перехоплює.
struct TouchObserver: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> TouchObserverView {
        let view = TouchObserverView()
        view.isUserInteractionEnabled = false
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: TouchObserverView, context: Context) {
        view.onTouch = onTouch
    }
}

final class TouchObserverView: UIView {
    var onTouch: (() -> Void)?
    private var recognizer: TouchRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, recognizer == nil else { return }
        let recognizer = TouchRecognizer(target: nil, action: nil)
        recognizer.onTouch = { [weak self] in self?.onTouch?() }
        window.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }
}

private final class TouchRecognizer: UIGestureRecognizer {
    var onTouch: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch?()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
