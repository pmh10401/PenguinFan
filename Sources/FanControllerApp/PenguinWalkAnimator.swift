import AppKit
import Foundation

@MainActor
final class PenguinWalkAnimator: NSObject {
    typealias RPMProvider = () -> [Double]
    typealias FrameHandler = (NSImage) -> Void

    private var timer: Timer?
    private var rpmProvider: RPMProvider?
    private var frameHandler: FrameHandler?
    private var frame = 0

    static func averageRPM(_ values: [Double]) -> Double? {
        let validValues = values.filter { $0.isFinite && $0 >= 0 }
        guard !validValues.isEmpty else {
            return nil
        }
        return validValues.reduce(0, +) / Double(validValues.count)
    }

    static func frameInterval(for averageRPM: Double?) -> TimeInterval {
        guard let averageRPM, averageRPM.isFinite else {
            return 0.90
        }

        let points: [(rpm: Double, interval: TimeInterval)] = [
            (1_500, 0.90),
            (3_000, 0.55),
            (4_500, 0.32),
            (6_000, 0.18),
        ]

        if averageRPM <= points[0].rpm {
            return points[0].interval
        }
        if averageRPM >= points[3].rpm {
            return points[3].interval
        }

        for index in 0..<(points.count - 1) {
            let lower = points[index]
            let upper = points[index + 1]
            guard averageRPM <= upper.rpm else {
                continue
            }
            let progress = (averageRPM - lower.rpm) / (upper.rpm - lower.rpm)
            return lower.interval + ((upper.interval - lower.interval) * progress)
        }

        return points[3].interval
    }

    func start(
        rpmProvider: @escaping RPMProvider,
        onFrame: @escaping FrameHandler
    ) {
        stop()
        self.rpmProvider = rpmProvider
        frameHandler = onFrame
        frame = 0
        onFrame(PenguinMenuBarIcon.make(frame: frame))
        scheduleNextFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rpmProvider = nil
        frameHandler = nil
        frame = 0
    }

    @objc
    private func advanceFrame() {
        let averageRPM = Self.averageRPM(rpmProvider?() ?? [])
        if averageRPM == nil {
            frame = 0
        } else {
            frame = (frame + 1) % 4
        }
        frameHandler?(PenguinMenuBarIcon.make(frame: frame))
        scheduleNextFrame(averageRPM: averageRPM)
    }

    private func scheduleNextFrame(averageRPM: Double? = nil) {
        let currentRPM = averageRPM ?? Self.averageRPM(rpmProvider?() ?? [])
        timer = Timer.scheduledTimer(
            timeInterval: Self.frameInterval(for: currentRPM),
            target: self,
            selector: #selector(advanceFrame),
            userInfo: nil,
            repeats: false
        )
        timer?.tolerance = 0.02
    }
}
