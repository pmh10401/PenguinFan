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
    @Published var privilegedServiceState: PrivilegedServiceState =
        .notRegistered
    @Published var pendingPrivilegedMode: ControlMode?
    @Published var isPrivilegedApprovalPresented = false
    var modeRequestHandler: ((ControlMode) -> Void)?
    var privilegedApprovalHandler: (() async -> Void)?
    var privilegedApprovalSettingsHandler: (() -> Void)?

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
        if mode != .systemAuto,
           privilegedServiceState != .enabled {
            settings.mode = .systemAuto
            pendingPrivilegedMode = mode
            isPrivilegedApprovalPresented = true
            controlStatus = .authorizing
            diagnosticMessage =
                "계속을 선택해야 권한 서비스 등록을 시작합니다."
            return
        }

        pendingPrivilegedMode = nil
        isPrivilegedApprovalPresented = false
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

    func confirmPrivilegedApproval() async {
        await privilegedApprovalHandler?()
    }

    func cancelPrivilegedApproval() {
        pendingPrivilegedMode = nil
        isPrivilegedApprovalPresented = false
        settings.mode = .systemAuto
        controlStatus = .systemAuto
        diagnosticMessage =
            "권한 요청을 취소했습니다. macOS 시스템 팬 제어를 유지합니다."
    }

    func openPrivilegedApprovalSettings() {
        privilegedApprovalSettingsHandler?()
    }

    func applyPendingPrivilegedMode() -> ControlMode? {
        guard let pendingPrivilegedMode else {
            return nil
        }
        self.pendingPrivilegedMode = nil
        isPrivilegedApprovalPresented = false
        settings.mode = pendingPrivilegedMode
        return pendingPrivilegedMode
    }

    func returnToSystemAuto() {
        selectMode(.systemAuto)
    }

    func markSystemAuto() {
        pendingPrivilegedMode = nil
        isPrivilegedApprovalPresented = false
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
