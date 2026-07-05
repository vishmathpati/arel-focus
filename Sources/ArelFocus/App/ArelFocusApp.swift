import AppKit
import SwiftUI

@main
struct ArelFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = FocusStore()
    @State private var didRequestInitialDashboard = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .onAppear { store.start() }
        } label: {
            Group {
                if let timer = store.menuBarTimerText {
                    // Text label so the live countdown is visible in the menu bar
                    // (a Label collapses to icon-only there). Icon interpolated in.
                    Text("\(Image(systemName: store.menuBarSystemImage))  \(timer)")
                } else {
                    Image(systemName: "timer")
                }
            }
            .onAppear {
                store.start()
                DashboardOpener.openAction = { openWindow(id: "dashboard") }
                openDashboardAtLaunch()
            }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Arel Focus", id: "dashboard") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1040, minHeight: 680)
                .background(DashboardWindowMarker())
                .onAppear {
                    store.start()
                    // Capture the openWindow action so AppDelegate (Dock click)
                    // can reopen the dashboard from outside the SwiftUI graph.
                    DashboardOpener.openAction = { openWindow(id: "dashboard") }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 520)
        }
    }

    private func openDashboardAtLaunch() {
        guard !didRequestInitialDashboard else { return }
        didRequestInitialDashboard = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            DashboardOpener.openDashboard()
        }
    }
}

// Static bridge from AppDelegate's Dock-click handler back into SwiftUI's
// openWindow environment. Set by the dashboard's onAppear.
@MainActor
enum DashboardOpener {
    private static let dashboardIdentifier = NSUserInterfaceItemIdentifier("com.arel.focus.dashboard")

    static var openAction: (() -> Void)?

    static func register(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = dashboardIdentifier
        window.title = "Arel Focus"
    }

    @discardableResult
    static func surfaceDashboard() -> Bool {
        guard let window = dashboardWindow else { return false }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    static func openDashboard() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if surfaceDashboard() {
            return
        }

        openAction?()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            _ = surfaceDashboard()
        }
    }

    private static var dashboardWindow: NSWindow? {
        NSApp.windows.first { window in
            window.identifier == dashboardIdentifier
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Restore the dashboard window when the user clicks the Dock icon.
    // SwiftUI's WindowGroup does not auto-reopen a closed window, so we
    // bring any existing window forward, or call back into the captured
    // openWindow action to create a fresh dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DashboardOpener.openDashboard()
        return false
    }
}

private struct DashboardWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            DashboardOpener.register(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            DashboardOpener.register(nsView.window)
        }
    }
}
