import FanControllerCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var launchAtLogin =
        LaunchAtLoginController()

    var body: some View {
        Form {
            Section("수동 제어") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("고정 RPM")
                        Spacer()
                        Button {
                            model.adjustManualRPM(by: -50)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .help("50 RPM 낮추기")
                        .disabled(
                            model.settings.manualRPM
                                <= model.safeRPMIntegerRange.lowerBound
                        )

                        TextField(
                            "RPM",
                            value: Binding(
                                get: { model.settings.manualRPM },
                                set: { model.updateManualRPM($0) }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 92)

                        Button {
                            model.adjustManualRPM(by: 50)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("50 RPM 높이기")
                        .disabled(
                            model.settings.manualRPM
                                >= model.safeRPMIntegerRange.upperBound
                        )
                    }

                    Text("고정 RPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(model.settings.manualRPM) },
                            set: { model.updateManualRPM(Int($0)) }
                        ),
                        in: model.safeRPMRange,
                        step: 50
                    )
                }
                Text(
                    "입력, +/- 버튼 또는 슬라이더를 사용할 수 있습니다. "
                        + "허용 범위: \(model.safeRPMIntegerRange.lowerBound)"
                        + "-\(model.safeRPMIntegerRange.upperBound) RPM"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("온도 커브") {
                ForEach(model.settings.curve.indices, id: \.self) { index in
                    HStack {
                        Text("포인트 \(index + 1)")
                            .frame(width: 68, alignment: .leading)
                        Stepper(
                            "\(Int(model.settings.curve[index].temperature))°C",
                            value: Binding(
                                get: {
                                    model.settings.curve[index].temperature
                                },
                                set: {
                                    model.updateCurvePoint(
                                        at: index,
                                        temperature: $0
                                    )
                                }
                            ),
                            step: 1
                        )
                        Spacer()
                        Stepper(
                            "\(model.settings.curve[index].rpm) RPM",
                            value: Binding(
                                get: { model.settings.curve[index].rpm },
                                set: {
                                    model.updateCurvePoint(at: index, rpm: $0)
                                }
                            ),
                            step: 100
                        )
                    }
                }
                Text(
                    "0°C부터 포인트 1 미만까지는 강제 RPM을 해제하고 "
                        + "macOS 시스템 팬 제어를 사용합니다. 포인트 온도는 "
                        + "항상 낮은 값에서 높은 값 순서로 유지됩니다."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("시작 및 안전") {
                Toggle(
                    "로그인 시 자동 실행",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if let message = launchAtLogin.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("시스템 자동 모드로 즉시 복귀") {
                    model.returnToSystemAuto()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Section("권한 서비스") {
                LabeledContent(
                    "상태",
                    value: model.privilegedServiceStatusLabel
                )

                if model.canOpenPrivilegedApprovalSettings {
                    Button("시스템 설정에서 승인") {
                        model.openPrivilegedApprovalSettings()
                    }
                }

                if model.canRemovePrivilegedService {
                    Button(
                        model.isPrivilegedServiceRemovalInProgress
                            ? "제거 중..."
                            : "권한 서비스 제거",
                        role: .destructive
                    ) {
                        model.requestPrivilegedServiceRemoval()
                    }
                    .disabled(model.isPrivilegedServiceRemovalInProgress)
                }

                Text(
                    "팬 제어에만 사용하는 macOS 권한 서비스입니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 680, minHeight: 580)
        .navigationTitle(ProductBrand.settingsTitle)
        .alert(
            "권한 서비스를 제거할까요?",
            isPresented:
                $model.isPrivilegedServiceRemovalConfirmationPresented
        ) {
            Button("취소", role: .cancel) {
                model.cancelPrivilegedServiceRemoval()
            }
            Button("제거", role: .destructive) {
                Task {
                    await model.confirmPrivilegedServiceRemoval()
                }
            }
        } message: {
            Text(
                "먼저 macOS 시스템 팬 제어로 복귀하고 연결을 종료한 뒤 권한 서비스를 제거합니다."
            )
        }
    }
}
