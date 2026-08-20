import SwiftUI
import AppKit

/// Real entry point, so `--probe` can answer and exit before any UI exists.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            Probe.run()
            exit(0)
        }
        SmartChargingApp.main()
    }
}

struct SmartChargingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var monitor = PowerMonitor()

    var body: some Scene {
        // The full guide. Closing it does not quit — the app drops back
        // to the menu bar and keeps measuring.
        Window("Mac Charging Guide", id: "dashboard") {
            DashboardView()
                .environment(monitor)
                .task { monitor.start() }
        }
        .defaultSize(width: 820, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuPanelView()
                .environment(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
                .task { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// What sits in the top-right of the screen: the live wattage, plus an
/// icon that changes shape — not just colour — when something is wrong,
/// so the state reads at a glance and without relying on colour alone.
private struct MenuBarLabel: View {
    @Bindable var monitor: PowerMonitor

    var body: some View {
        let s = monitor.snapshot

        HStack(spacing: 3) {
            Image(systemName: symbol(s))
            Text(text(s))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
    }

    private func symbol(_ s: PowerSnapshot) -> String {
        guard s.adapterConnected else { return "battery.50" }
        if s.isDraining { return "exclamationmark.triangle.fill" }
        if monitor.diagnosis.level >= .warning { return "bolt.badge.clock.fill" }
        return "bolt.fill"
    }

    private func text(_ s: PowerSnapshot) -> String {
        s.adapterConnected ? "\(s.adapterWatts)W" : "\(s.batteryPercent)%"
    }
}

// MARK: - Lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Closing the last window must not quit the app — the whole point is
    /// that it keeps running in the menu bar afterwards.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Let the close finish before counting what's left.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let stillOpen = NSApp.windows.contains { window in
                    window.isVisible
                        && !(window is NSPanel)          // the menu bar panel doesn't count
                        && window.canBecomeMain
                }
                if !stillOpen {
                    // Menu-bar-only: no Dock icon, no menu bar app menu.
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
