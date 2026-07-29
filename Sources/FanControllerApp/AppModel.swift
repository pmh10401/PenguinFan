import Combine
import FanControllerCore
import Foundation
import SMCKit

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: SensorSnapshot?
    @Published var history: [SensorSnapshot] = []
    @Published var settings: FanSettings
    @Published var controlStatus: ControlStatus = .systemAuto
    @Published var diagnosticMessage: String?
    @Published var capabilities: HardwareCapabilities?
    @Published var ipcConnected = false
    var modeRequestHandler: ((ControlMode) -> Void)?

    init(settings: FanSettings = .safeDefaults) {
        self.settings = settings
    }

    var menuBarTitle: String {
        guard let temperature = snapshot?.maximumTemperature else {
            return "Fan"
        }
        return "\(Int(temperature.rounded()))°"
    }

    var menuBarSymbol: String {
        switch snapshot?.thermalPressure {
        case .critical:
            "exclamationmark.triangle.fill"
        case .hot:
            "thermometer.high"
        default:
            "fan.fill"
        }
    }

    var safeRPMRange: ClosedRange<Double> {
        guard let fans = capabilities?.fans, !fans.isEmpty else {
            return 1_500...6_000
        }
        let minimum = fans.map(\.minimumRPM).max() ?? 1_500
        let maximum = fans.map(\.maximumRPM).min() ?? 6_000
        guard minimum <= maximum else {
            return 1_500...6_000
        }
        return Double(minimum)...Double(maximum)
    }

    func record(_ newSnapshot: SensorSnapshot) {
        snapshot = newSnapshot
        history.append(newSnapshot)
        let cutoff = newSnapshot.timestamp.addingTimeInterval(-600)
        history = history
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func selectMode(_ mode: ControlMode) {
        settings.mode = mode
        if mode == .systemAuto {
            controlStatus = .restoring
        } else {
            controlStatus = .authorizing
            diagnosticMessage = ipcConnected
                ? nil
                : "관리자 제어 연결 후 적용됩니다."
        }
        modeRequestHandler?(mode)
    }

    func returnToSystemAuto() {
        selectMode(.systemAuto)
    }

    func markSystemAuto() {
        settings.mode = .systemAuto
        controlStatus = .systemAuto
        diagnosticMessage = nil
    }

    func updateCurvePoint(
        at index: Int,
        temperature: Double? = nil,
        rpm: Int? = nil
    ) {
        guard settings.curve.indices.contains(index) else {
            return
        }
        var point = settings.curve[index]
        if let temperature {
            let lower = index == 0
                ? 30
                : settings.curve[index - 1].temperature + 1
            let upper = index == settings.curve.count - 1
                ? 110
                : settings.curve[index + 1].temperature - 1
            point.temperature = min(max(temperature, lower), upper)
        }
        if let rpm {
            point.rpm = Int(
                min(
                    max(Double(rpm), safeRPMRange.lowerBound),
                    safeRPMRange.upperBound
                )
            )
        }
        settings.curve[index] = point
    }
}
