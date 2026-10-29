import CoreMotion
import NavigationCore

/// Справжні датчики: CMMotionActivityManager (стоянка / їзда) і CMMotionManager
/// (акселерометр + гіроскоп через deviceMotion) для кутової швидкості навколо вертикалі.
@MainActor
final class CoreMotionSource: MotionSource {
    var onActivity: (@MainActor (MotionActivity) -> Void)?
    var onYawRate: (@MainActor (YawSample) -> Void)?

    private let activityManager = CMMotionActivityManager()
    private let motionManager = CMMotionManager()

    /// 10 Гц достатньо для поворотів авто і не садить батарею.
    static let motionInterval: TimeInterval = 0.1

    func start() {
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                let state: MotionActivity = activity.stationary ? .stationary
                    : activity.automotive ? .automotive
                    : activity.walking ? .walking : .unknown
                MainActor.assumeIsolated { self?.onActivity?(state) }
            }
        }
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = Self.motionInterval
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion else { return }
                // Проєкція кутової швидкості на вертикаль (за гравітацією): працює за будь-якого кріплення телефона.
                let g = motion.gravity
                let r = motion.rotationRate
                let norm = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
                guard norm > 0.1 else { return }
                let yawRate = -(r.x * g.x + r.y * g.y + r.z * g.z) / norm
                let sample = YawSample(rate: yawRate, timestamp: motion.timestamp)
                MainActor.assumeIsolated { self?.onYawRate?(sample) }
            }
        }
    }

    func stop() {
        activityManager.stopActivityUpdates()
        motionManager.stopDeviceMotionUpdates()
    }
}
