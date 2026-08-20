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

        // --- Low-priority port ------------------------------------------
        // Checked before the cable, because a 30 W port also reports a low
        // current ceiling and would otherwise be blamed on the cable. A real
        // 3 A cable cap sits at 3000 mA on the 20 V rail; a slow port looks
        // nothing like that — it negotiates a lower rail as well.
        if s.adapterWatts > 0 && s.adapterWatts <= 35 {
            return Diagnosis(
                level: draining ? .critical : .warning,
                headline: "Only \(s.adapterWatts) W is reaching your Mac",
                detail: "That is far below what a laptop needs. On a multi-port charger this is "
                      + "the slow port — the one meant for a phone. It can also mean a hub or "
                      + "monitor in the middle passing very little power through."
                      + deficitNote,
                fix: "Move to the charger's main port — usually the one marked, or nearest the "
                   + "edge — and plug the charger straight into the wall.",
                evidence: evidence
            )
        }

        // --- Cable has no e-marker chip --------------------------------
        // Above 3 A a cable must identify itself. The signature is precise:
        // every profile pinned at 3000 mA, on the full 20 V rail, landing on
        // 60 W. Anything else that happens to be under 3 A is a different
        // fault and must not be blamed on the cable.
        if s.cableCappedAt3A && s.adapterVoltageMV >= 19000 && s.adapterWatts <= 60 {
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

        // --- 65 W: either a shared tier or a genuine 65 W charger --------
        // These are indistinguishable from the reading alone — a multi-port
        // unit splitting power and a real single-port 65 W charger both
        // negotiate 20 V / 3.25 A. Say so rather than asserting a fault.
        if s.adapterWatts == 65 || s.adapterCurrentMA == 3250 {
            return Diagnosis(
                level: draining ? .critical : .warning,
                headline: "65 W — check whether it should be more",
                detail: "65 W is two things at once: it is what a genuine 65 W charger "
                      + "delivers, and it is also the tier a bigger multi-port charger drops to "
                      + "when it thinks a second device is attached. If your charger is rated "
                      + "higher than 65 W, it is the second one — and it happens even when the "
                      + "other device is fully charged and drawing nothing." + deficitNote,
                fix: "If the charger is rated above 65 W: unplug everything else from it, then "
                   + "unplug it from the wall for 15 seconds — power-sharing can stay stuck "
                   + "until mains power is removed. If it really is a 65 W charger, this is "
                   + "simply its limit.",
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
