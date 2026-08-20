import Foundation

/// Remembers the best a charger has ever offered, so a drop can be named.
///
/// The case this exists for: a multi-port charger where one port is fast and
/// the others are not. Moving the cable from C1 to C2 on a 200 W unit costs
/// 40 W, announces nothing, and looks identical from the outside. A one-shot
/// reading says "100 W, fine". Only something that remembers 140 W can say
/// "you used to get more than this".
///
/// The cable is ruled out by comparing current ceilings: if the cable's
/// ampere limit is unchanged and the offered voltage rail dropped, the cable
/// is not what changed — the port is.
struct ChargerCapability: Codable, Equatable {
    var maxWatts: Int
    var maxMilliVolts: Int
    var maxMilliAmps: Int

    init(from s: PowerSnapshot) {
        maxWatts      = s.advertisedMaxW
        maxMilliVolts = s.advertisedProfiles.map(\.mV).max() ?? 0
        maxMilliAmps  = s.advertisedProfiles.map(\.mA).max() ?? 0
    }
}

@MainActor
final class ChargerMemory {

    private let key = "bestChargerCapability"
    private(set) var best: ChargerCapability?

    init() { load() }

    /// Feed every reading in. Only genuine improvements are kept.
    func record(_ s: PowerSnapshot) {
        guard s.adapterConnected, s.advertisedMaxW > 0 else { return }
        let current = ChargerCapability(from: s)
        if best == nil || current.maxWatts > best!.maxWatts {
            best = current
            save()
        }
    }

    /// Non-nil when this charger has demonstrably done better before, and
    /// the cable is not the reason.
    func downgrade(_ s: PowerSnapshot) -> String? {
        guard let best,
              s.adapterConnected,
              s.advertisedMaxW > 0,
              best.maxWatts >= s.advertisedMaxW + 15
        else { return nil }

        let cableUnchanged = abs(best.maxMilliAmps - (s.advertisedProfiles.map(\.mA).max() ?? 0)) < 200
        let railDropped = (s.advertisedProfiles.map(\.mV).max() ?? 0) < best.maxMilliVolts

        if cableUnchanged && railDropped {
            return "This charger has offered \(best.maxWatts) W before, on a "
                 + "\(best.maxMilliVolts / 1000) V rail. Right now the best it offers is "
                 + "\(s.advertisedMaxW) W. Your cable has not changed — the same current limit "
                 + "is in place — so this is the port. Multi-port chargers usually put their "
                 + "full power on one port only. Move back to the port you were using."
        }
        if cableUnchanged {
            return "This charger has offered \(best.maxWatts) W before and is offering "
                 + "\(s.advertisedMaxW) W now, with the same cable. Check whether something "
                 + "else is plugged into it, or try its other port."
        }
        return "This charger has offered \(best.maxWatts) W before. It is offering "
             + "\(s.advertisedMaxW) W now, and the cable's limit has changed too — so this is "
             + "probably a different cable."
    }

    func forget() {
        best = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        best = try? JSONDecoder().decode(ChargerCapability.self, from: data)
    }

    private func save() {
        guard let best, let data = try? JSONEncoder().encode(best) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
