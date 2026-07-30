import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section("하드웨어") {
                LabeledContent(
                    "모델",
                    value: model.capabilities?.modelIdentifier ?? "탐지 대기"
                )
                LabeledContent(
                    "AppleSMC 팬",
                    value: "\(model.capabilities?.fans.count ?? 0)개"
                )
                LabeledContent(
                    "IPC",
                    value: model.ipcConnected ? "연결됨" : "연결 안 됨"
                )
                LabeledContent(
                    "실험적 권한 서비스",
                    value: model.privilegedServiceStatusLabel
                )
            }

            Section("팬") {
                if let fans = model.capabilities?.fans, !fans.isEmpty {
                    ForEach(fans, id: \.index) { fan in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Fan \(fan.index + 1)")
                                .font(.headline)
                            Text(
                                "\(fan.minimumRPM)–\(fan.maximumRPM) RPM · \(fan.modeKey)"
                            )
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("팬 정보가 아직 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("유효 온도 센서") {
                Text(
                    model.snapshot?.validTemperatureKeys.joined(
                        separator: ", "
                    ) ?? "센서 탐지 대기"
                )
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }

            Section("최근 오류") {
                Text(model.diagnosticMessage ?? "오류 없음")
                    .foregroundStyle(
                        model.diagnosticMessage == nil
                            ? Color.secondary
                            : Color.orange
                    )
                    .textSelection(.enabled)
            }

            Section("실험적 진단 옵션") {
                Toggle(
                    "레거시 osascript fallback 허용",
                    isOn: $model.legacyFallbackEnabled
                )
                Text(
                    "이 옵션을 켜면 권한 승인 대화상자에 PenguinFan이 아닌 osascript가 표시될 수 있습니다. 진단이 끝나면 다시 끄세요."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("진단")
    }
}
