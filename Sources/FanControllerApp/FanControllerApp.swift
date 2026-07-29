import SwiftUI

@main
struct FanControllerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Fan Controller 설정", id: "settings") {
            SettingsView(model: model)
                .frame(minWidth: 540, minHeight: 560)
        }

        Window("Fan Controller 진단", id: "diagnostics") {
            DiagnosticsView(model: model)
                .frame(minWidth: 540, minHeight: 480)
        }
    }
}
