import Foundation
import IOKit
import Observation

// MARK: - Snapshot

/// One reading of the machine's power state, taken straight from
/// the AppleSmartBattery IOService. Everything here is measured;
/// nothing is inferred.
struct PowerSnapshot: Equatable {
    var adapterConnected = false

    /// Watts the Mac and the charger agreed on. This is the number that
    /// exposes a weak cable: it is a negotiated ceiling, not a rating.
    var adapterWatts = 0

    /// The negotiated rail. 20000 mV is standard USB-PD; 28000 mV only
    /// exists on PD 3.1 (EPR) and is how 140 W is delivered.
    var adapterVoltageMV = 0

    /// The current ceiling the cable permitted. 3000 mA means the cable
    /// carries no e-marker chip and the charger was forbidden to go higher.
    var adapterCurrentMA = 0

    var adapterDescription: String?

    var batteryPercent = 0
    var batteryVoltageMV = 0

    /// Signed. Positive = charge flowing in, negative = battery draining.
    var instantAmperageMA = 0

    var isCharging = false
    var temperatureC: Double = 0
    var cycleCount = 0
    var healthPercent = 0

    /// What the charging circuit asked for. When this greatly exceeds what
    /// arrives, the supply is the constraint rather than the battery.
    var requestedCurrentMA = 0

    var notChargingReason = 0
    var timestamp = Date()

    // MARK: Derived

    /// Power flowing into (+) or out of (−) the battery, in watts.
    var batteryFlowW: Double {
        (Double(batteryVoltageMV) / 1000.0) * (Double(instantAmperageMA) / 1000.0)
    }

    var isDraining: Bool { instantAmperageMA < -20 }

    /// Only knowable when the adapter is saturated — i.e. the machine is
    /// pulling everything the adapter can give and still taking from the
    /// battery. Then draw = adapter ceiling + the deficit. Any other time
    /// the adapter's actual output isn't exposed, so we don't guess.
    var systemDrawW: Double? {
        guard adapterConnected, isDraining else { return nil }
        return Double(adapterWatts) + abs(batteryFlowW)
    }

    /// Watts short of breaking even, when running a deficit on AC.
    var deficitW: Double? {
        guard adapterConnected, isDraining else { return nil }
        return abs(batteryFlowW)
    }
}

// MARK: - Monitor

@MainActor
@Observable
final class PowerMonitor {

    private(set) var snapshot = PowerSnapshot()
    private(set) var history: [Double] = []       // battery flow, watts
    private(set) var lastError: String?
    private(set) var loads: [RunningLoad] = []

    /// Peak adapter wattage seen this session — makes an intermittent
    /// power-sharing drop visible after the fact.
    private(set) var peakWattsSeen = 0

    private var timer: Timer?
    private var tick = 0
    private var isActive = true
    private let historyLimit = 90                  // ~3 minutes at 2 s

    /// Watching closely while someone is looking; barely ticking otherwise.
    /// A tool that measures power has no business wasting it.
    private var interval: TimeInterval { isActive ? 2.0 : 10.0 }

    var diagnosis: Diagnosis { Diagnosis.evaluate(snapshot) }

    func start() {
        stop()
        refresh()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the panel opens or the window shows/hides. Idle cadence
    /// keeps the menu bar number honest without polling four times as often
    /// as anyone can read it.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { refresh() }
        if timer != nil { schedule() }
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard let props = Self.readBatteryProperties() else {
            lastError = "Could not read AppleSmartBattery. This Mac may not have a battery."
            return
        }
        lastError = nil

        var s = PowerSnapshot()
        s.timestamp = Date()

        s.adapterConnected = (props["ExternalConnected"] as? Bool) ?? false
        s.batteryPercent   = Self.int(props["CurrentCapacity"]) ?? 0
        s.batteryVoltageMV = Self.int(props["Voltage"]) ?? 0
        s.isCharging       = (props["IsCharging"] as? Bool) ?? false
        s.cycleCount       = Self.int(props["CycleCount"]) ?? 0
        s.healthPercent    = Self.int(props["MaxCapacity"]) ?? 0

        if let raw = Self.int(props["Temperature"]) {
            s.temperatureC = Double(raw) / 100.0
        }

        // InstantAmperage arrives as a 64-bit two's-complement value, so a
        // discharge reads as a huge unsigned number unless reinterpreted.
        s.instantAmperageMA = Self.signed(props["InstantAmperage"])
            ?? Self.signed(props["Amperage"])
            ?? 0

        if let adapter = props["AdapterDetails"] as? [String: Any] {
            s.adapterWatts       = Self.int(adapter["Watts"]) ?? 0
            s.adapterVoltageMV   = Self.int(adapter["AdapterVoltage"]) ?? 0
            s.adapterCurrentMA   = Self.int(adapter["Current"]) ?? 0
            s.adapterDescription = adapter["Description"] as? String
        }

        if let charger = props["ChargerData"] as? [String: Any] {
            s.requestedCurrentMA = Self.int(charger["ChargingCurrent"]) ?? 0
            s.notChargingReason  = Self.int(charger["NotChargingReason"]) ?? 0
        }

        snapshot = s

        if s.adapterConnected {
            peakWattsSeen = max(peakWattsSeen, s.adapterWatts)
        } else {
            peakWattsSeen = 0
        }

        history.append(s.batteryFlowW)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }

        // Process sampling shells out, so do it far less often than the
        // sensor read — and only while someone is actually watching.
        tick &+= 1
        if isActive && tick % 3 == 0 {
            loads = ProcessWatch.topLoads()
        }
    }

    /// The heavy hitter worth naming, if there is one.
    var dominantAIRuntime: RunningLoad? {
        loads.first { $0.isAIRuntime && $0.cpuPercent > 20 }
    }

    // MARK: IOKit

    private static func readBatteryProperties() -> [String: Any]? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = unmanaged?.takeRetainedValue() else { return nil }
        return dict as? [String: Any]
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// Reinterpret the stored bit pattern as signed, so a draining battery
    /// reads as a negative milliamp figure rather than ~1.8×10¹⁹.
    private static func signed(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber else { return nil }
        return Int(Int64(bitPattern: n.uint64Value))
    }
}
