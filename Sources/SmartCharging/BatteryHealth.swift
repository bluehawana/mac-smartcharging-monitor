import Foundation

/// Battery longevity tracking.
///
/// The thesis this module exists to prove out: an undersized charger doesn't
/// only cost you speed, it costs you battery life. Under a supply that can't
/// keep up, the pack is pushed into continuous shallow charge/discharge
/// reversals — micro-cycling — while the chip is running hot. Heat and
/// cycling are the two things that actually age lithium cells, and a
/// too-small charger under sustained load produces both at once.
///
/// Sitting at 100% on a correctly sized charger is gentler than hovering at
/// 45% on one that's 20 W short.

struct HealthSample: Codable {
    var t: Date
    var soc: Int
    var tempC: Double
    var flowW: Double
    var onAC: Bool
}

struct HealthMetrics {
    var window: TimeInterval = 0          // seconds actually covered
    var fractionAbove90 = 0.0             // time at high charge
    var fractionInIdealBand = 0.0         // 20–80%
    var hoursAbove35C = 0.0
    var microCyclesPerHour = 0.0
    var deficitHours = 0.0                // time draining while plugged in
    var sampleCount = 0

    var hasEnoughData: Bool { window >= 3600 }   // at least an hour

    /// 0 = gentle, 100 = hard on the battery. Weighted toward the two
    /// factors with real evidence behind them: heat and cycling.
    var stressScore: Int {
        guard hasEnoughData else { return 0 }
        let heat    = min(hoursAbove35C / max(window / 3600, 1), 1.0) * 40
        let cycling = min(microCyclesPerHour / 12.0, 1.0) * 35
        let highSoC = fractionAbove90 * 15
        let deficit = min(deficitHours / max(window / 3600, 1), 1.0) * 10
        return Int((heat + cycling + highSoC + deficit).rounded())
    }

    var stressLabel: String {
        switch stressScore {
        case ..<20:  return "Gentle"
        case ..<45:  return "Normal"
        case ..<70:  return "Hard"
        default:     return "Very hard"
        }
    }
}

@MainActor
final class BatteryHealthTracker {

    private(set) var samples: [HealthSample] = []
    private var lastStored: Date?
    private var lastFlowSign = 0

    private let storeInterval: TimeInterval = 60          // one sample a minute
    private let retention: TimeInterval = 14 * 24 * 3600  // two weeks

    private let url: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmartCharging", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("health.json")
    }()

    init() { load() }

    // MARK: Recording

    func record(_ s: PowerSnapshot) {
        // Micro-cycles are counted on every reading, not every stored
        // sample — a reversal that happens between minutes still happened.
        if s.adapterConnected {
            let sign = s.batteryFlowW > 2 ? 1 : (s.batteryFlowW < -2 ? -1 : 0)
            if sign != 0 {
                if lastFlowSign != 0 && sign != lastFlowSign {
                    reversals.append(Date())
                }
                lastFlowSign = sign
            }
        } else {
            lastFlowSign = 0
        }

        let now = Date()
        if let last = lastStored, now.timeIntervalSince(last) < storeInterval { return }
        lastStored = now

        samples.append(HealthSample(t: now,
                                    soc: s.batteryPercent,
                                    tempC: s.temperatureC,
                                    flowW: s.batteryFlowW,
                                    onAC: s.adapterConnected))
        prune()
        save()
    }

    private var reversals: [Date] = []

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        samples.removeAll { $0.t < cutoff }
        reversals.removeAll { $0 < cutoff }
    }

    // MARK: Metrics

    func metrics(over days: Double = 7) -> HealthMetrics {
        let cutoff = Date().addingTimeInterval(-days * 24 * 3600)
        let window = samples.filter { $0.t >= cutoff }
        guard window.count >= 2 else { return HealthMetrics() }

        var m = HealthMetrics()
        m.sampleCount = window.count
        m.window = window.last!.t.timeIntervalSince(window.first!.t)

        // Each sample represents the interval up to the next one, capped so a
        // sleeping Mac doesn't book eight hours of "exposure" from one sample.
        var above90 = 0.0, ideal = 0.0, hot = 0.0, deficit = 0.0, total = 0.0

        for i in 0..<(window.count - 1) {
            let s = window[i]
            let dt = min(window[i + 1].t.timeIntervalSince(s.t), storeInterval * 2)
            total += dt
            if s.soc > 90 { above90 += dt }
            if s.soc >= 20 && s.soc <= 80 { ideal += dt }
            if s.tempC > 35 { hot += dt }
            if s.onAC && s.flowW < -2 { deficit += dt }
        }

        guard total > 0 else { return m }
        m.fractionAbove90     = above90 / total
        m.fractionInIdealBand = ideal / total
        m.hoursAbove35C       = hot / 3600
        m.deficitHours        = deficit / 3600

        let recentReversals = reversals.filter { $0 >= cutoff }.count
        m.microCyclesPerHour = Double(recentReversals) / max(total / 3600, 1)

        return m
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        samples = (try? dec.decode([HealthSample].self, from: data)) ?? []
        prune()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(samples) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Coaching

/// One piece of advice, phrased as something to do rather than something
/// to know. Ordered by how much difference it actually makes.
struct BatteryAdvice: Identifiable, Equatable {
    enum Kind { case act, watch, good }
    var id: String { title }
    var kind: Kind
    var title: String
    var body: String
}

enum BatteryCoach {

    static func advise(snapshot s: PowerSnapshot, metrics m: HealthMetrics) -> [BatteryAdvice] {
        var out: [BatteryAdvice] = []

        // --- The headline case: undersized supply under load ------------
        if s.adapterConnected && s.isDraining {
            out.append(BatteryAdvice(
                kind: .act,
                title: "Your charger is aging your battery, not just slowing you down",
                body: "Because the supply can't keep up, the battery is being discharged and "
                    + "recharged over and over while the chip runs hot. Heat and cycling are the "
                    + "two things that actually wear a battery out, and a charger that's short "
                    + "produces both at once. A correctly sized charger is gentler than this, "
                    + "even though it keeps the battery fuller."
            ))
        }

        if m.hasEnoughData && m.microCyclesPerHour >= 6 {
            out.append(BatteryAdvice(
                kind: .act,
                title: String(format: "%.0f charge reversals an hour", m.microCyclesPerHour),
                body: "The battery keeps flipping between charging and draining. That is the "
                    + "signature of a supply that is borderline for what you're running. Each "
                    + "reversal is a small piece of a cycle, and they add up faster than a "
                    + "normal charge does."
            ))
        }

        // --- Heat -------------------------------------------------------
        if s.temperatureC > 37 {
            out.append(BatteryAdvice(
                kind: .act,
                title: String(format: "Battery is at %.0f °C", s.temperatureC),
                body: "Sustained heat is the single biggest thing that shortens battery life. "
                    + "Lift the laptop so air can reach the underside, or pause what's running "
                    + "for a few minutes."
            ))
        } else if m.hasEnoughData && m.hoursAbove35C > 4 {
            out.append(BatteryAdvice(
                kind: .watch,
                title: String(format: "%.1f hours above 35 °C this week", m.hoursAbove35C),
                body: "Long stretches of heat matter more than the peaks. If most of that is "
                    + "model runs, raising the machine off the desk is the cheapest fix there is."
            ))
        }

        // --- Sitting full and idle --------------------------------------
        if s.adapterConnected && s.batteryPercent >= 97 && !s.isDraining && abs(s.batteryFlowW) < 2 {
            out.append(BatteryAdvice(
                kind: .watch,
                title: "Full and idle — unplugging now would be kinder",
                body: "A lithium battery held at 100% ages faster than one resting around 50–80%. "
                    + "If you're not about to travel, run on battery for a while. macOS also has "
                    + "an 80% limit in System Settings → Battery that does this automatically."
            ))
        }

        if m.hasEnoughData && m.fractionAbove90 > 0.6 {
            out.append(BatteryAdvice(
                kind: .watch,
                title: String(format: "%.0f%% of the week spent above 90%%", m.fractionAbove90 * 100),
                body: "Mostly-full is a slow, steady source of wear. Turning on Optimized Battery "
                    + "Charging or the 80% limit removes it without you having to think about it."
            ))
        }

        // --- The balance question ---------------------------------------
        if s.adapterConnected && !s.isDraining && s.batteryPercent < 90 {
            out.append(BatteryAdvice(
                kind: .good,
                title: "This is the good state",
                body: "Plugged into a supply that keeps up, below 90%, not cycling. Doing heavy "
                    + "work here costs the battery almost nothing — the power comes from the wall "
                    + "instead of the cells."
            ))
        }

        if m.hasEnoughData && m.fractionInIdealBand > 0.7 && m.microCyclesPerHour < 3 {
            out.append(BatteryAdvice(
                kind: .good,
                title: "Your charging habits are good",
                body: String(format: "Most of the week was spent between 20%% and 80%%, with little "
                    + "cycling. That is close to the gentlest way to use a laptop battery.")
            ))
        }

        return out
    }

    /// The answer to "should I stay plugged in or not?" given right now.
    static func plugAdvice(_ s: PowerSnapshot, aiRunning: Bool) -> String {
        if !s.adapterConnected {
            if aiRunning {
                return "Running a model on battery drains fast and throttles hard. Plug in — "
                     + "with an adequate charger this costs the battery nothing."
            }
            return s.batteryPercent < 20
                ? "Low. Plug in when convenient."
                : "On battery in a healthy range. Nothing to do."
        }
        if s.isDraining {
            return "Plugged in but still losing charge. Either use a stronger charger or pause "
                 + "the model — this state is the hardest on the battery."
        }
        if s.batteryPercent >= 97 {
            return "Full. If you're staying at the desk, unplug and let it drift down."
        }
        return "Plugged in and keeping up. Good state to do heavy work in."
    }
}
