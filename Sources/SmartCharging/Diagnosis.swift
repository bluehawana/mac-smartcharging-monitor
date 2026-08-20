import SwiftUI

/// Turns a raw power reading into something a person can act on.
/// Every rule here maps to a physical cause, not a guess.
struct Diagnosis: Equatable {

    enum Level: Int, Comparable {
        case good, info, warning, critical
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var tint: Color {
            switch self {
            case .good:     return Theme.pass
            case .info:     return Theme.muted
            case .warning:  return Theme.warn
            case .critical: return Theme.fail
            }
        }

        var symbol: String {
            switch self {
            case .good:     return "checkmark.circle.fill"
            case .info:     return "info.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }

    var level: Level
    /// Short enough to sit in a menu bar panel.
    var headline: String
    /// Plain language, no jargon that isn't immediately explained.
    var detail: String
    /// What to actually do. Empty when nothing needs doing.
    var fix: String
    /// The numbers this conclusion rests on.
    var evidence: [String]

    // MARK: - Rules

    static func evaluate(_ s: PowerSnapshot) -> Diagnosis {

        // --- Unplugged -------------------------------------------------
        guard s.adapterConnected else {
            return Diagnosis(
                level: .info,
                headline: "On battery",
                detail: "No charger attached, so there is nothing to diagnose right now. "
                      + "Plug in to check what your cable and charger actually deliver.",
                fix: "",
                evidence: ["\(s.batteryPercent)% remaining"]
            )
        }

        var evidence = [
            "\(s.adapterWatts) W negotiated",
            "\(s.adapterVoltageMV / 1000) V rail",
            "\(s.adapterCurrentMA) mA cable ceiling"
        ]
        if s.isDraining {
            evidence.append(String(format: "%.1f W leaving the battery", abs(s.batteryFlowW)))
        }

        let draining = s.isDraining
        let deficitNote = draining
            ? " Right now your Mac is using more power than the charger supplies, so the battery is going down even though it is plugged in."
            : ""

        // --- Cable has no e-marker chip --------------------------------
        // Above 3 A a cable must identify itself. 3000 mA exactly is the
        // standard's hard ceiling for a cable that doesn't.
        if s.adapterCurrentMA > 0 && s.adapterCurrentMA <= 3000 && s.adapterWatts <= 60 {
            return Diagnosis(
                level: draining ? .critical : .warning,
                headline: "Your cable is holding you back",
                detail: "You are getting \(s.adapterWatts) W. The cable can only carry 3 amps, "
                      + "which caps you at 60 W no matter how good the charger is. "
                      + "Cables that can carry more contain a small identifying chip; yours does not."
                      + deficitNote,
                fix: "Replace the cable with one rated 240 W (also sold as PD 3.1). "
                   + "It is the cheapest part of the chain and the most common fault.",
                evidence: evidence
            )
        }

        // --- Charger is dividing its output ----------------------------
        // 65 W / 3250 mA is the classic shared tier on multi-port units.
        if s.adapterWatts == 65 || s.adapterCurrentMA == 3250 {
            return Diagnosis(
                level: draining ? .critical : .warning,
                headline: "Charger is splitting its power",
                detail: "You are getting \(s.adapterWatts) W, which is a shared tier rather than "
                      + "a full one. Your charger believes something else is plugged into it and "
                      + "has divided its output — this happens even when the other device is "
                      + "fully charged and drawing nothing." + deficitNote,
                fix: "Unplug everything else from the charger, then unplug the charger itself "
                   + "from the wall for 15 seconds. Power-sharing can stay stuck until mains "
                   + "power is removed.",
                evidence: evidence
            )
        }

        // --- Low-priority port -----------------------------------------
        if s.adapterWatts > 0 && s.adapterWatts <= 35 {
            return Diagnosis(
                level: draining ? .critical : .warning,
                headline: "Only \(s.adapterWatts) W is reaching your Mac",
                detail: "That is far below what a laptop needs. You are most likely in the "
                      + "charger's low-priority port, or plugged into a hub or monitor that "
                      + "passes very little power through." + deficitNote,
                fix: "Move to the charger's main port — usually the one marked, or nearest the "
                   + "edge — and plug the charger straight into the wall.",
                evidence: evidence
            )
        }

        // --- Full PD 3.1 rate ------------------------------------------
        if s.adapterVoltageMV >= 27000 && s.adapterWatts >= 140 {
            return Diagnosis(
                level: draining ? .warning : .good,
                headline: "Full speed — \(s.adapterWatts) W",
                detail: "You are on the 28 volt rail, which only exists on the newer PD 3.1 "
                      + "standard. Both your charger and your cable are doing everything they can. "
                      + (draining
                         ? "Your Mac is still drawing more than this under load, which is close to the "
                         + "physical limit of what any charger can deliver over a single cable."
                         : "Nothing to fix."),
                fix: "",
                evidence: evidence
            )
        }

        // --- Standard 100 W --------------------------------------------
        if s.adapterWatts >= 96 {
            return Diagnosis(
                level: draining ? .warning : .good,
                headline: "\(s.adapterWatts) W — standard full speed",
                detail: "Your cable and charger are working correctly at the normal USB-C limit. "
                      + (draining
                         ? "Under heavy sustained work — running a local AI model, for instance — your "
                         + "Mac wants more than this, so the battery slowly drains."
                         : "This is plenty for everyday work."),
                fix: draining
                    ? "If you regularly run local models, a 140 W charger with a 240 W cable is the "
                    + "next step up. Otherwise nothing needs changing."
                    : "",
                evidence: evidence
            )
        }

        // --- Anything else in between ----------------------------------
        return Diagnosis(
            level: draining ? .critical : .warning,
            headline: "\(s.adapterWatts) W — below full speed",
            detail: "Your Mac is not getting the power it could. Either the cable, the charger, "
                  + "or the port is limiting the connection." + deficitNote,
            fix: "Try your other cable, move to the charger's main port, and plug directly into "
               + "the wall rather than through a hub or display.",
            evidence: evidence
        )
    }
}
