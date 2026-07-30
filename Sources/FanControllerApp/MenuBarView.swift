import FanControllerCore
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var openSettingsAction: (() -> Void)?
    var openDiagnosticsAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)

            ScrollView {
                VStack(spacing: 14) {
                    thermalHero
                    fanGrid
                    HistoryChartView(history: model.history)
                    modePicker
                    statusStrip
                }
                .padding(16)
            }

            Divider().opacity(0.45)
            footer
        }
        .frame(width: 360, height: 620)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.orange.opacity(0.055),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.orange.gradient)
                Image(nsImage: PenguinMenuBarIcon.make())
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .bold))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(ProductBrand.displayName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text("Apple Silicon Thermal Control")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            model.ipcConnected
                                ? Color.green
                                : Color.secondary
                        )
                        .frame(width: 7, height: 7)
                    Text(model.ipcConnected ? "연결됨" : "안전 대기")
                        .font(.caption2.weight(.medium))
                }
                Text(lastUpdatedText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var thermalHero: some View {
        HStack(spacing: 14) {
            Gauge(
                value: model.snapshot?.maximumTemperature ?? 0,
                in: 30...110
            ) {
                Text("온도")
            } currentValueLabel: {
                Text(temperatureText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(temperatureGradient)
            .scaleEffect(1.15)
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 7) {
                Text("MAX SENSOR")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(pressureTitle)
                    .font(.title3.weight(.semibold))
                Text(pressureDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var fanGrid: some View {
        HStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { index in
                let reading = model.snapshot?.fans.first {
                    $0.index == index
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Image(systemName: "fan")
                        Text("FAN \(index + 1)")
                            .font(.caption.weight(.bold))
                        Spacer()
                    }
                    Text(reading.map { "\($0.actualRPM)" } ?? "—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("목표 \(reading.map { "\($0.targetRPM)" } ?? "—") RPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 13)
                )
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CONTROL MODE")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Picker(
                "제어 모드",
                selection: Binding(
                    get: { model.settings.mode },
                    set: { model.selectMode($0) }
                )
            ) {
                Text("시스템").tag(ControlMode.systemAuto)
                Text("커브").tag(ControlMode.curve)
                Text("수동").tag(ControlMode.manual)
            }
            .pickerStyle(.segmented)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Image(
                systemName: model.controlStatus == .systemAuto
                    ? "checkmark.shield.fill"
                    : "lock.shield"
            )
            .foregroundStyle(
                model.controlStatus == .systemAuto ? .green : .orange
            )
            Text(statusText)
                .font(.caption)
            Spacer()
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text(ProductBrand.currentVersionText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)

            HStack {
                Button("설정") {
                    if let openSettingsAction {
                        openSettingsAction()
                    } else {
                        openWindow(id: "settings")
                    }
                }
                Button("진단") {
                    if let openDiagnosticsAction {
                        openDiagnosticsAction()
                    } else {
                        openWindow(id: "diagnostics")
                    }
                }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(14)
    }

    private var temperatureText: String {
        model.snapshot?.maximumTemperature.map {
            "\(Int($0.rounded()))°"
        } ?? "—"
    }

    private var pressureTitle: String {
        switch model.snapshot?.thermalPressure {
        case .nominal: "정상"
        case .elevated: "부하 상승"
        case .hot: "높은 온도"
        case .critical: "위험 온도"
        default: "센서 대기 중"
        }
    }

    private var pressureDetail: String {
        model.snapshot == nil
            ? "읽기 전용 센서 연결을 준비하고 있습니다."
            : "macOS thermal pressure와 유효 센서를 함께 감시합니다."
    }

    private var statusText: String {
        switch model.controlStatus {
        case .systemAuto: "macOS가 팬을 제어하고 있습니다."
        case .authorizing: "관리자 승인을 기다리고 있습니다."
        case .curve: "온도 커브 제어가 활성화되었습니다."
        case .manual: "고정 RPM 제어가 활성화되었습니다."
        case .restoring: "시스템 자동 모드로 복구 중입니다."
        case .failed: "제어 오류로 자동 복구했습니다."
        }
    }

    private var temperatureGradient: Gradient {
        Gradient(colors: [.teal, .yellow, .orange, .red])
    }

    private var lastUpdatedText: String {
        guard let timestamp = model.snapshot?.timestamp else {
            return "센서 연결 중"
        }
        return timestamp.formatted(
            date: .omitted,
            time: .standard
        )
    }
}
