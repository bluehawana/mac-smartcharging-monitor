import SwiftUI

struct DashboardView: View {
    @Environment(PowerMonitor.self) private var monitor

    private var s: PowerSnapshot { monitor.snapshot }
    private var d: Diagnosis { monitor.diagnosis }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                liveStatus
                explanation
                cableReference
                sharingTrap
                symptoms
                buying
                footer
            }
            .padding(30)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Theme.plate)
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: - Live

    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldLabel("Right now")

            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(s.adapterConnected ? "\(s.adapterWatts)" : "—")
                            .font(Theme.readout(58, weight: .bold))
                            .foregroundStyle(d.level == .good ? Theme.pass : d.level.tint)
                        Text("W")
                            .font(.system(size: 22, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    FieldLabel("Reaching your Mac")
                }

                Divider().frame(height: 62).overlay(Theme.hairline)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 22) {
                        Readout(label: "Battery flow",
                                value: String(format: "%+.1f", s.batteryFlowW),
                                unit: "W",
                                tint: s.isDraining ? Theme.fail : Theme.pass,
                                size: 19)
                        Readout(label: "Charge", value: "\(s.batteryPercent)", unit: "%", size: 19)
                        Readout(label: "Cable limit",
                                value: s.adapterConnected ? "\(s.adapterCurrentMA)" : "—",
                                unit: "mA", size: 19)
                        Readout(label: "Rail",
                                value: s.adapterConnected ? "\(s.adapterVoltageMV / 1000)" : "—",
                                unit: "V", size: 19)
                    }

                    if let draw = s.systemDrawW {
                        Text(String(format: "Your Mac is pulling about %.0f W — more than the charger can give.", draw))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.fail)
                    }
                }
                Spacer(minLength: 0)
            }

            FlowSparkline(values: monitor.history, height: 54)
                .padding(.top, 2)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.hairline))
    }

    // MARK: - Explanation

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: d.level.symbol).foregroundStyle(d.level.tint)
                Text(d.headline).font(.system(size: 20, weight: .bold))
            }

            Text(d.detail)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !d.fix.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    FieldLabel("What to do")
                    Text(d.fix).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(d.level.tint.opacity(0.10)))
            }

            if !d.evidence.isEmpty {
                HStack(spacing: 14) {
                    ForEach(d.evidence, id: \.self) { e in
                        Text(e).font(Theme.label(10)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    // MARK: - Cables

    private var cableReference: some View {
        Section(title: "Which cable is which",
                blurb: "Above 3 amps a cable must carry an identifying chip called an e-marker. "
                     + "Without one the charger is required to stop at 60 W — however good it is.") {
            VStack(spacing: 0) {
                CableRow("Basic USB-C", "Bundled with phones", "60 W", Theme.fail,
                         "Thin, smooth plastic. If you don't know where it came from, assume this.")
                CableRow("Apple USB-C Charge Cable", "Ships with iPhone", "60 W", Theme.fail,
                         "Thin white plastic — looks like the good Apple cable but isn't.")
                CableRow("5 A e-marked", "USB-PD 3.0", "100 W", Theme.warn,
                         "Usually printed “100W” on the connector. Often braided.")
                CableRow("240 W e-marked", "USB-PD 3.1", "240 W", Theme.pass,
                         "Printed “240W” or “EPR”. The only kind that can carry 140 W.")
                CableRow("Apple 240 W cable", "Ships with 140 W Macs", "240 W", Theme.pass,
                         "Thick and fabric-woven. Woven means fast.", last: true)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.hairline))

            Text("The quickest test: woven texture means the fast cable, smooth plastic means 60 W.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
        }
    }

    // MARK: - Sharing

    private var sharingTrap: some View {
        Section(title: "“200 W” on the box is not 200 W for your Mac",
                blurb: "Multi-port chargers advertise their total, and divide it the moment a "
                     + "second device appears — often even when that device is charging nothing.") {
            VStack(spacing: 0) {
                ShareRow("Mac alone on the main port", "100 W", Theme.pass, "Full rated power")
                ShareRow("Mac + anything in the second USB-C", "65 W", Theme.warn, "Cut by a third")
                ShareRow("Mac + anything in USB-A", "65 W", Theme.warn, "Same penalty", last: true)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.hairline))

            Text("This is why the exact number matters: 60 W means the cable is the limit, "
               + "65 W means the charger is splitting power. One watt apart, completely "
               + "different problems.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: - Symptoms

    private var symptoms: some View {
        Section(title: "What too little power feels like",
                blurb: "Running a local model with Ollama or oMLX is close to the highest sustained "
                     + "power draw an Apple silicon chip can produce — higher than compiling, higher "
                     + "than exporting video. That is when an undersized charger stops hiding.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 14) {
                SymptomCard("Hot, loud, and still slow",
                            "macOS throttles the chip to fit inside what the adapter supplies. You end up running a Max chip like a base model.")
                SymptomCard("“Charging” while the battery drops",
                            "macOS says Charging whenever a cable is attached. It does not mean you are gaining anything.")
                SymptomCard("Never gets past half",
                            "The battery only recovers in the gaps between generations, so it settles into a low band and stays there.")
                SymptomCard("Looks completely dead",
                            "Drained too far, the Mac saves memory to disk and shuts down. A weak adapter can't gather enough charge to boot. Leave it plugged in for 20–30 minutes.")
            }
        }
    }

    // MARK: - Buying

    private var buying: some View {
        Section(title: "What to buy, in order",
                blurb: "Cheapest and most likely fix first.") {
            VStack(alignment: .leading, spacing: 16) {
                Step(1, "A 240 W / PD 3.1 cable — around €20",
                     "Buy this before anything else, even if you think your cable is fine. It is the "
                   + "most common fault and the cheapest part. Versions with a wattage display on the "
                   + "connector show you the number without any of this.")
                Step(2, "Re-test before buying a charger",
                     "With a proper cable your existing charger may already deliver its full rating. "
                   + "If that's enough for what you do, you are finished.")
                Step(3, "A 140 W adapter — only if the test says so",
                     "Needed for sustained large-model work on Pro and Max chips. Check for 140 W on a "
                   + "single port and PD 3.1 — many “200 W” chargers cap every individual port at 100 W.")
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("Free things to try first")
                Text("Empty every other port on the charger. Unplug it from the wall for 15 seconds. "
                   + "Move to the main port. Try your other cable — if two give different wattages, "
                   + "the higher one is better. Plug into the wall directly, not through a hub or monitor.")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.pass.opacity(0.10)))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.hairline)
            Text("Readings come from the AppleSmartBattery sensor on this Mac. Closing this window "
               + "leaves the monitor running in the menu bar.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if s.cycleCount > 0 {
                Text("Battery health \(s.healthPercent)% · \(s.cycleCount) cycles · "
                   + String(format: "%.1f °C", s.temperatureC))
                    .font(Theme.label(10))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: - Building blocks

private struct Section<Content: View>: View {
    let title: String
    let blurb: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(blurb)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

private struct CableRow: View {
    let name: String, sub: String, watts: String, tint: Color, how: String
    var last = false

    init(_ name: String, _ sub: String, _ watts: String, _ tint: Color, _ how: String, last: Bool = false) {
        self.name = name; self.sub = sub; self.watts = watts; self.tint = tint
        self.how = how; self.last = last
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13.5, weight: .semibold))
                    Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                }
                .frame(width: 190, alignment: .leading)

                Text(watts)
                    .font(Theme.readout(15))
                    .foregroundStyle(tint)
                    .frame(width: 66, alignment: .leading)

                Text(how)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !last { Divider().overlay(Theme.hairline) }
        }
    }
}

private struct ShareRow: View {
    let what: String, watts: String, tint: Color, note: String
    var last = false

    init(_ what: String, _ watts: String, _ tint: Color, _ note: String, last: Bool = false) {
        self.what = what; self.watts = watts; self.tint = tint; self.note = note; self.last = last
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(what).font(.system(size: 13.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(watts).font(Theme.readout(15)).foregroundStyle(tint)
                    .frame(width: 66, alignment: .trailing)
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .frame(width: 150, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !last { Divider().overlay(Theme.hairline) }
        }
    }
}

private struct SymptomCard: View {
    let title: String, body_: String
    init(_ t: String, _ b: String) { title = t; body_ = b }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(body_).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.hairline))
    }
}

private struct Step: View {
    let n: Int, title: String, body_: String
    init(_ n: Int, _ t: String, _ b: String) { self.n = n; title = t; body_ = b }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(String(format: "%02d", n))
                .font(Theme.label(11))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(body_).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
