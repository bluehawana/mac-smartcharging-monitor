import SwiftUI

/// The panel that drops down from the menu bar. Designed to answer one
/// question at a glance — am I gaining or losing power — with the
/// supporting numbers underneath for anyone who wants them.
struct MenuPanelView: View {
    @Environment(PowerMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow

    private var s: PowerSnapshot { monitor.snapshot }
    private var d: Diagnosis { monitor.diagnosis }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            numbers
            Divider().overlay(Theme.hairline)
            chart
            if !monitor.loads.isEmpty {
                Divider().overlay(Theme.hairline)
                culprits
            }
            Divider().overlay(Theme.hairline)
            actions
        }
        .frame(width: 340)
        .background(Theme.plate)
        // Poll quickly only while this panel is on screen.
        .onAppear { monitor.setActive(true) }
        .onDisappear { monitor.setActive(false) }
    }

    // MARK: Who's drawing the power

    private var culprits: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel("Using the most CPU")

            ForEach(monitor.loads) { load in
                HStack(spacing: 8) {
                    if load.isAIRuntime {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(load.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(String(format: "%.0f%%", load.cpuPercent))
                        .font(Theme.readout(11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }

            if let ai = monitor.dominantAIRuntime, s.isDraining {
                Text("\(ai.name) is running a local model — that is what your charger "
                   + "is losing to. Pausing it will let the battery recover.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Header — verdict first

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: d.level.symbol)
                    .foregroundStyle(d.level.tint)
                    .font(.system(size: 15))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(d.headline)
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(flowSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }

            if !d.fix.isEmpty {
                Text(d.fix)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(d.level.tint)
                            .frame(width: 2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only something that remembers can say "you used to get more".
            if let notice = monitor.downgradeNotice {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "arrow.down.right.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warn)
                        .padding(.top, 1)
                    Text(notice)
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.warn.opacity(0.12)))
            }
        }
        .padding(14)
    }

    private var flowSummary: String {
        guard s.adapterConnected else {
            return "\(s.batteryPercent)% left, running on battery"
        }
        if s.isDraining {
            return String(format: "Losing %.1f W while plugged in · %d%%",
                          abs(s.batteryFlowW), s.batteryPercent)
        }
        if s.batteryFlowW > 0.5 {
            return String(format: "Gaining %.1f W · %d%%", s.batteryFlowW, s.batteryPercent)
        }
        if s.batteryPercent >= 78 && s.batteryPercent <= 82 {
            return "Holding at \(s.batteryPercent)% — normal battery care"
        }
        return "Holding steady · \(s.batteryPercent)%"
    }

    // MARK: Numbers

    private var numbers: some View {
        HStack(alignment: .top, spacing: 0) {
            Readout(label: "Delivered",
                    value: s.adapterConnected ? "\(s.adapterWatts)" : "—",
                    unit: "W",
                    tint: d.level == .good ? Theme.pass : d.level.tint,
                    size: 24)
                .frame(maxWidth: .infinity, alignment: .leading)

            Readout(label: "Battery",
                    value: String(format: "%+.1f", s.batteryFlowW),
                    unit: "W",
                    tint: s.isDraining ? Theme.fail : Theme.pass,
                    size: 24)
                .frame(maxWidth: .infinity, alignment: .leading)

            Readout(label: "Charge",
                    value: "\(s.batteryPercent)",
                    unit: "%",
                    size: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                FieldLabel("Battery flow · last 3 min")
                Spacer()
                if s.adapterConnected {
                    Text("\(s.adapterCurrentMA) mA cable · \(s.adapterVoltageMV / 1000) V rail")
                        .font(Theme.label(9))
                        .foregroundStyle(Theme.muted)
                }
            }
            FlowSparkline(values: monitor.history, height: 42)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "dashboard")
            } label: {
                Label("Open guide", systemImage: "book")
                    .font(.system(size: 12))
            }

            Spacer()

            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .help("Read the sensors again now")

            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
