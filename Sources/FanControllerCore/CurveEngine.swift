import Foundation

public enum CurveEngineError: Error, Equatable {
    case insufficientPoints
    case nonFiniteTemperature
    case temperaturesNotIncreasing
    case rpmDecreases
    case invalidHardwareRange
}

public enum CurveEngine {
    public static func validate(_ points: [CurvePoint]) throws {
        guard points.count >= 2 else {
            throw CurveEngineError.insufficientPoints
        }

        for point in points where !point.temperature.isFinite {
            throw CurveEngineError.nonFiniteTemperature
        }

        for index in 1..<points.count {
            guard points[index].temperature > points[index - 1].temperature else {
                throw CurveEngineError.temperaturesNotIncreasing
            }
            guard points[index].rpm >= points[index - 1].rpm else {
                throw CurveEngineError.rpmDecreases
            }
        }
    }

    public static func targetRPM(
        temperature: Double,
        points: [CurvePoint],
        minimumRPM: Int,
        maximumRPM: Int
    ) throws -> Int {
        try validate(points)
        guard temperature.isFinite else {
            throw CurveEngineError.nonFiniteTemperature
        }
        guard minimumRPM > 0, maximumRPM >= minimumRPM else {
            throw CurveEngineError.invalidHardwareRange
        }

        let proposed: Int
        if temperature <= points[0].temperature {
            proposed = points[0].rpm
        } else if temperature >= points[points.count - 1].temperature {
            proposed = points[points.count - 1].rpm
        } else {
            let upperIndex = points.firstIndex { $0.temperature >= temperature }!
            let lower = points[upperIndex - 1]
            let upper = points[upperIndex]
            let ratio = (temperature - lower.temperature) / (upper.temperature - lower.temperature)
            proposed = Int(
                (Double(lower.rpm) + ratio * Double(upper.rpm - lower.rpm)).rounded()
            )
        }

        return min(max(proposed, minimumRPM), maximumRPM)
    }

    public static func limitedRPM(previous: Int, proposed: Int, maximumStep: Int) -> Int {
        let step = max(0, maximumStep)
        return min(max(proposed, previous - step), previous + step)
    }
}
