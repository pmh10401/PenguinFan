import AppKit
import SwiftUI

@MainActor
final class PopoverPresentationCoordinator {
    enum Trigger {
        case initialLaunch
        case reopen
    }

    private var didRequestInitialPresentation = false
    private let present: () -> Void

    init(present: @escaping () -> Void) {
        self.present = present
    }

    func requestPresentation(for trigger: Trigger) {
        if trigger == .initialLaunch {
            guard !didRequestInitialPresentation else {
                return
            }
            didRequestInitialPresentation = true
        }
        present()
    }
}

@main
struct FanControllerApp: App {
    @NSApplicationDelegateAdaptor(FanControllerAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class FanControllerAppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let runtime = RuntimeController()
    private let penguinAnimator = PenguinWalkAnimator()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?
    private lazy var popoverPresentationCoordinator =
        PopoverPresentationCoordinator { [weak self] in
            self?.presentPopover()
        }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        NSApp.setActivationPolicy(.accessory)
        runtime.start(model: model)

        let statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        guard let button = statusItem.button else {
            return
        }
        button.image = PenguinMenuBarIcon.make()
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = ProductBrand.displayName
        button.target = self
        button.action = #selector(togglePopover)

        let rootView = MenuBarView(
            openSettingsAction: { [weak self] in
                self?.showSettings()
            },
            openDiagnosticsAction: { [weak self] in
                self?.showDiagnostics()
            }
        )
        .environmentObject(model)
        popover.contentSize = NSSize(width: 360, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: rootView
        )
        popover.behavior = .transient
        popover.animates = true
        self.statusItem = statusItem

        penguinAnimator.start(
            rpmProvider: { [weak self] in
                self?.model.snapshot?.fans.map { Double($0.actualRPM) } ?? []
            },
            onFrame: { [weak button] image in
                button?.image = image
            }
        )

        DispatchQueue.main.async { [weak self] in
            self?.popoverPresentationCoordinator.requestPresentation(
                for: .initialLaunch
            )
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        popoverPresentationCoordinator.requestPresentation(for: .reopen)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        penguinAnimator.stop()
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem?.button else {
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }

    private func presentPopover() {
        guard let button = statusItem?.button else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        guard !popover.isShown else {
            return
        }
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: ProductBrand.settingsTitle,
                size: NSSize(width: 620, height: 620),
                rootView: SettingsView(model: model)
            )
        }
        present(settingsWindow)
    }

    private func showDiagnostics() {
        if diagnosticsWindow == nil {
            diagnosticsWindow = makeWindow(
                title: ProductBrand.diagnosticsTitle,
                size: NSSize(width: 620, height: 540),
                rootView: DiagnosticsView(model: model)
            )
        }
        present(diagnosticsWindow)
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(
            rootView: rootView
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
