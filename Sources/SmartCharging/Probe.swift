import Foundation

/// `SmartCharging --probe` prints one reading as text and exits.
///
/// Useful for pasting into a bug report, for checking a machine over SSH,
/// and for confirming the sensor layer works without launching any UI.
enum Probe {

    static func run() {
        MainActor.assumeIsolated {
            let monitor = PowerMonitor()
            monitor.refresh()

            if let err = monitor.lastError {
                FileHandle.standardError.write(Data((err + "\n").utf8))
                exit(1)
            }

            let s = monitor.snapshot
            let d = monitor.diagnosis

            print("SmartCharging probe")
            print(String(repeating: "─", count: 52))

            row("Adapter", s.adapterConnected ? "connected" : "not connected")
            if s.adapterConnected {
                row("Delivered", "\(s.adapterWatts) W")
                row("Rail voltage", "\(s.adapterVoltageMV) mV")
                row("Cable ceiling", "\(s.adapterCurrentMA) mA"
                    + (s.adapterCurrentMA <= 3000 ? "   (no e-marker — 3 A limit)" : ""))
                if let desc = s.adapterDescription { row("Description", desc) }

                if !s.advertisedProfiles.isEmpty {
                    let offered = s.advertisedProfiles
                        .map { "\($0.mV / 1000)V/\(String(format: "%.2f", Double($0.mA) / 1000))A" }
                        .joined(separator: "  ")
                    row("Offered", offered)
                    row("Best offer", "\(s.advertisedMaxW) W"
                        + (s.cableCappedAt3A ? "   (every profile capped at 3 A by the cable)" : ""))
                }
            }

            row("Charge", "\(s.batteryPercent) %")
            row("Battery flow", String(format: "%+.2f W  (%d mA)", s.batteryFlowW, s.instantAmperageMA))
            row("Charging", s.isCharging ? "yes" : "no")
            if s.requestedCurrentMA > 0 {
                row("Circuit wants", "\(s.requestedCurrentMA) mA")
            }
            if let draw = s.systemDrawW {
                row("System draw", String(format: "~%.0f W  (adapter saturated)", draw))
            }
            row("Health", "\(s.healthPercent) %  ·  \(s.cycleCount) cycles")
            row("Temperature", String(format: "%.1f °C", s.temperatureC))

            print(String(repeating: "─", count: 52))
            if let notice = monitor.downgradeNotice {
                print("⚠︎  " + wrap(notice, indent: 4))
                print("")
            }
            print(d.headline)
            print("")
            print(wrap(d.detail))
            if !d.fix.isEmpty {
                print("")
                print("Fix: " + wrap(d.fix, indent: 5))
            }
        }
    }

    private static func row(_ label: String, _ value: String) {
        let padded = label.padding(toLength: 16, withPad: " ", startingAt: 0)
        print("\(padded) \(value)")
    }

    /// Wrap to a comfortable reading width for a terminal.
    private static func wrap(_ text: String, width: Int = 72, indent: Int = 0) -> String {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.count + word.count + 1 > width {
                lines.append(line)
                line = String(word)
            } else {
                line = line.isEmpty ? String(word) : line + " " + word
            }
        }
        if !line.isEmpty { lines.append(line) }
        let pad = String(repeating: " ", count: indent)
        return lines.enumerated()
            .map { $0.offset == 0 ? $0.element : pad + $0.element }
            .joined(separator: "\n")
    }
}
