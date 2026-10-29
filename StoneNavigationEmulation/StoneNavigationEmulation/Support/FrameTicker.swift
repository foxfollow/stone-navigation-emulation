import QuartzCore

/// Виклик на кожному кадрі екрана (до 60 разів на секунду), щоб точка і камера рухались плавно.
/// Рушій рахує позицію рідше (раз на `updateInterval`), кадри лише малюють проміжні положення.
@MainActor
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let onFrame: @MainActor () -> Void

    init(onFrame: @escaping @MainActor () -> Void) {
        self.onFrame = onFrame
    }

    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        onFrame()
    }
}
