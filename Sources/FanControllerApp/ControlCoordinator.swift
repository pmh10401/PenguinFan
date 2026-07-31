import FanControlIPC
import FanControllerCore
import Foundation

protocol ControlClient: Sendable {
    func send(_ command: ControlCommand) async throws -> ControlResult
}

struct UnixSocketControlClient: ControlClient {
    let path: String

    func send(_ command: ControlCommand) async throws -> ControlResult {
        let path = path
        return try await Task.detached {
            let request = ControlRequest(id: UUID(), command: command)
            let response = try UnixSocketClient(path: path).send(request)
            return response.result
        }.value
    }
}

enum ControlCoordinatorError: Error, Equatable {
    case missingTemperature
    case rejected(code: String, message: String)
    case fanDidNotRespond(Int)
}

actor ControlCoordinator {
    private let client: any ControlClient
    private var settings: FanSettings
    private let fans: [FanDescriptor]
    private var requestedTargets: [Int: Int] = [:]
    private var targetRequestedAt: Date?
    private var isLowTemperatureSystemAutoActive = false
    private var lastCurveTemperature: Double?
    private var lastCurveTemperatureSampleAt: Date?
    private var curveTemperatureMissingSince: Date?

    init(
        client: any ControlClient,
        settings: FanSettings,
        fans: [FanDescriptor]
    ) {
        self.client = client
        self.settings = settings
        self.fans = fans
    }

    func update(settings: FanSettings) {
        if settings.mode != .curve {
            lastCurveTemperature = nil
            lastCurveTemperatureSampleAt = nil
            curveTemperatureMissingSince = nil
        }
        self.settings = settings
    }

    func apply(snapshot: SensorSnapshot) async throws {
        guard settings.mode == .curve || settings.mode == .manual else {
            return
        }

        do {
            if try shouldUseSystemAuto(snapshot: snapshot) {
                if !isLowTemperatureSystemAutoActive {
                    try await requireAcknowledged(
                        client.send(.restoreSystemAuto)
                    )
                }
                requestedTargets.removeAll()
                targetRequestedAt = nil
                isLowTemperatureSystemAutoActive = true
                return
            }

            isLowTemperatureSystemAutoActive = false
            var targets: [Int: Int] = [:]
            for fan in fans {
                let rpm = try targetRPM(for: fan, snapshot: snapshot)
                if rpm == nil {
                    return
                }
                try await requireAcknowledged(
                    client.send(.setRPM(fan: fan.index, rpm: rpm!))
                )
                targets[fan.index] = rpm
            }
            if targets != requestedTargets {
                targetRequestedAt = snapshot.timestamp
            }
            requestedTargets = targets
        } catch {
            _ = try? await client.send(.restoreSystemAuto)
            requestedTargets.removeAll()
            targetRequestedAt = nil
            isLowTemperatureSystemAutoActive = true
            throw error
        }
    }

    func verifyFanResponse(snapshot: SensorSnapshot) async throws {
        guard let requestedAt = targetRequestedAt,
              snapshot.timestamp.timeIntervalSince(requestedAt) >= 8
        else {
            return
        }

        for (fanIndex, target) in requestedTargets {
            guard let reading = snapshot.fans.first(
                where: { $0.index == fanIndex }
            ), abs(reading.actualRPM - target) <= 400 else {
                _ = try? await client.send(.restoreSystemAuto)
                requestedTargets.removeAll()
                targetRequestedAt = nil
                throw ControlCoordinatorError.fanDidNotRespond(fanIndex)
            }
        }
        targetRequestedAt = snapshot.timestamp
    }

    func heartbeat() async throws {
        try await requireAcknowledged(client.send(.heartbeat))
    }

    func status() async throws -> AgentStatus {
        let result = try await client.send(.status)
        guard case .status(let status) = result else {
            try requireAcknowledged(result)
            throw ControlCoordinatorError.rejected(
                code: "invalid_status",
                message: "Agent returned no status payload."
            )
        }
        return status
    }

    func restoreAndShutdown() async {
        _ = try? await client.send(.restoreSystemAuto)
        _ = try? await client.send(.shutdown)
        requestedTargets.removeAll()
        targetRequestedAt = nil
        isLowTemperatureSystemAutoActive = true
    }

    func restoreSystemAuto() async throws {
        try await requireAcknowledged(
            client.send(.restoreSystemAuto)
        )
        requestedTargets.removeAll()
        targetRequestedAt = nil
        isLowTemperatureSystemAutoActive = true
    }

    private func shouldUseSystemAuto(
        snapshot: SensorSnapshot
    ) throws -> Bool {
        guard settings.mode == .curve,
              snapshot.thermalPressure != .critical
        else {
            return false
        }
        guard let temperature = snapshot.maximumTemperature else {
            return false
        }
        return try CurveEngine.shouldUseSystemAuto(
            temperature: temperature,
            points: settings.curve
        )
    }

    private func targetRPM(
        for fan: FanDescriptor,
        snapshot: SensorSnapshot
    ) throws -> Int? {
        if snapshot.thermalPressure == .critical {
            return fan.maximumRPM
        }

        switch settings.mode {
        case .curve:
            guard let temperature = try resolvedCurveTemperature(
                from: snapshot
            ) else {
                return nil
            }
            return try CurveEngine.targetRPM(
                temperature: temperature,
                points: settings.curve,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
        case .manual:
            return min(
                max(settings.manualRPM, fan.minimumRPM),
                fan.maximumRPM
            )
        case .systemAuto:
            return fan.minimumRPM
        }
    }

    private func resolvedCurveTemperature(
        from snapshot: SensorSnapshot
    ) throws -> Double? {
        guard snapshot.thermalPressure != .critical else {
            lastCurveTemperature = nil
            lastCurveTemperatureSampleAt = nil
            curveTemperatureMissingSince = nil
            return nil
        }

        guard let temperature = snapshot.maximumTemperature else {
            if let missingSince = curveTemperatureMissingSince,
               snapshot.timestamp.timeIntervalSince(missingSince) > 5 {
                throw ControlCoordinatorError.missingTemperature
            }

            if let previousSampleAt = lastCurveTemperatureSampleAt,
               let lastCurveTemperature,
               snapshot.timestamp.timeIntervalSince(previousSampleAt) <= 5 {
                return lastCurveTemperature
            }

            if curveTemperatureMissingSince == nil {
                curveTemperatureMissingSince = snapshot.timestamp
            }
            return nil
        }

        curveTemperatureMissingSince = nil
        lastCurveTemperature = temperature
        lastCurveTemperatureSampleAt = snapshot.timestamp
        return temperature
    }

    private func requireAcknowledged(
        _ result: ControlResult
    ) throws {
        switch result {
        case .acknowledged:
            return
        case .rejected(let code, let message):
            throw ControlCoordinatorError.rejected(
                code: code,
                message: message
            )
        case .status:
            throw ControlCoordinatorError.rejected(
                code: "unexpected_status",
                message: "Unexpected status payload."
            )
        }
    }
}
