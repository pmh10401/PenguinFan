import AppKit
import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            if enabled && !isEnabled {
                message = "시스템 설정에서 로그인 항목 승인이 필요합니다."
                openLoginItemsSettings()
            }
        } catch {
            isEnabled = false
            message = error.localizedDescription
        }
    }

    private func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        if status == .requiresApproval {
            message = "시스템 설정에서 로그인을 승인해 주세요."
        } else if status == .notRegistered || status == .enabled {
            message = nil
        }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
