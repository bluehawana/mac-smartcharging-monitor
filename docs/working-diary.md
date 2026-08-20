# Working diary

## 2026-08-20 — Day one: from a charging complaint to a shipped monitor

### What was broken

The whole project started as a support question about a laptop that wouldn't
charge properly. A 16-inch MacBook Pro (M5 Max), a UGREEN charger, one USB-C
cable — and the battery going *down* while plugged in, running a 27B model
under oMLX. Hot, laggy, and stuck below 50% for weeks.

The diagnosis took several wrong turns worth recording, because the app now
encodes what each of them taught:

- **First reading: 65 W.** I blamed the cable. Wrong — the charger was
  offering 3250 mA, and USB-PD forbids exceeding 3000 mA unless the cable
  carries an e-marker. Offering 3.25 A *proves* the cable identified itself.
  The 65 W was the charger's power-sharing tier. I had read past that in the
  first data dump.
- **Then: 60 W, 3000 mA.** A different cable, and this time genuinely
  unmarked — hard-capped at 3 A. So both faults were real, on different
  cables, at different moments.
- **Then: 140 W at 28 V.** New charger and cable. The 28 V rail only exists
  on PD 3.1, so that number alone proves EPR end to end.
- **Then: 100 W, same 4990 mA cable.** No fault at all — the cable had moved
  from C1 to C2 on the new Nexode 200 W. One port carries 140 W; the rest
  don't.

Four readings, four different causes, and every one of them invisible unless
you go digging in `ioreg`. That is the product.

### What got built

A SwiftUI menu bar app, SPM-built into a real `.app` bundle (menu bar apps
need bundle identity — `NSStatusItem` misbehaves from a bare executable).

- `PowerMonitor` — reads `AppleSmartBattery` via IOKit. The fiddly bit is
  `InstantAmperage`, which arrives as a 64-bit two's-complement value, so a
  draining battery reads as ~1.8×10¹⁹ unless you reinterpret the bit pattern.
- `Diagnosis` — rules that separate a cable limit (60 W) from charger power
  sharing (65 W). One watt apart, completely different fixes. This distinction
  is the app's whole reason to exist.
- `ChargerMemory` — remembers the best a charger ever offered. Catches the
  C1→C2 move that a one-shot reading calls "100 W, fine".
- `BatteryHealth` — persistent tracking of high-charge time, heat exposure,
  and micro-cycling.
- `ProcessWatch` — names the local-inference runtime responsible.
- `Probe` — `--probe` prints one reading as text and exits.

### Design notes

**Read `UsbHvcMenu`, not just `Watts`.** `AdapterDetails` carries the full
list of profiles the charger offered. The charger builds that list *after*
reading the cable, so an unmarked cable forces every entry to 3000 mA.
Comparing the best offer against what was negotiated is what separates "this
charger can't" from "this cable won't" — no single wattage figure can.

**Don't invent watts.** macOS doesn't expose the adapter's actual output.
System draw is therefore only reported when the adapter is *saturated* —
drawing everything it can and still losing to the battery — where
`draw = ceiling + deficit` is exact. Every other moment it stays blank.
Same reasoning for per-process power: `ProcessWatch` reports CPU share and
says so, rather than fabricating a wattage split.

**The battery-health thesis.** An undersized charger doesn't only cost speed,
it costs battery life. Under a supply that can't keep up, the pack is pushed
into continuous shallow charge/discharge reversals while the chip runs hot —
and heat plus cycling are the two things that actually wear lithium cells.
Sitting at 100% on an adequate charger is *gentler* than hovering at 45% on
one that's 20 W short. That reframes right-sizing a charger as a longevity
fix, not just a convenience one.

**Adaptive polling.** 2 s while someone is watching, 10 s otherwise. A tool
that measures power has no business wasting it — lifted from how Mole
releases window memory when it tucks into the menu bar.

### Verification

The data layer was checked against live hardware throughout; `--probe`
returned correct readings at every stage. The port-downgrade detector was
verified by seeding the remembered capability with the real 140 W/28 V
reading and confirming it correctly ruled out the cable (4990 vs 5000 mA,
unchanged) and named the port. Seed removed afterwards.

**Not verified: the UI.** This shell has no screen recording permission, so
nothing in `DashboardView` or `MenuPanelView` has been seen rendered. Every
layout decision in them is currently untested.

### Measurement worth keeping

At 100 W on C2, running Qwen3.8-27B under oMLX:

```
Delivered        100 W
Cable ceiling    4990 mA
Battery flow     -21.39 W
System draw      ~121 W  (adapter saturated)
```

121 W of real sustained draw. My earlier estimate of 80–110 W was low — which
is the argument for measuring rather than projecting, and the reason the app
exists at all.

### Next

1. Look at the UI and fix whatever the screenshots would have caught.
2. Decide on the SMC charge limit (`CHWA` on Apple silicon, `BCLM`/`CH0B` on
   Intel). It's the paid anchor, and it needs a privileged helper plus a
   Developer ID to ship to anyone else.
3. Note for the record: the iPhone/iPad 80% idea can only ever be an *alert*.
   No API lets a Mac stop an attached iOS device from charging, and there's no
   per-port power control on Apple silicon to cut it at the source.

---

## 2026-08-20 (later) — Screenshots caught a misdiagnosis

Ran the app across all three USB-C ports of the Nexode 200 W and captured
each. Same laptop, same 240 W cable throughout — only the port changed:

| Port | Delivered | Rail | Cable ceiling | Draw | Battery |
|------|----------:|-----:|--------------:|-----:|--------:|
| C1 | 140 W | 28 V | 4990 mA | — | +0.0 W |
| C2 | 100 W | 20 V | 4990 mA | 117 W | −16.9 W |
| C3 | 30 W | 12 V | 2480 mA | 47 W | −17.2 W |

A 110 W swing decided by which hole the cable went into, with no warning from
macOS at any point. That table is now the top of the README — it makes the
case better than any amount of prose.

### The bug it exposed

On C3 the app said **"Your cable is holding you back — the cable can only
carry 3 amps."** Wrong, and provably so from the screenshots themselves: the
same cable reports 4990 mA on C1. The cable was never the problem.

Cause was rule ordering in `Diagnosis.evaluate`. The cable rule tested
`adapterCurrentMA <= 3000 && adapterWatts <= 60`, and a 30 W port satisfies
both — it negotiates 2480 mA, which is under 3000. The low-power-port rule
that should have caught it sat *below* the cable rule and never ran.

Two fixes:
- Moved the low-priority-port check above the cable check.
- Tightened the cable rule to the actual e-marker signature rather than a
  loose inequality: every offered profile pinned at 3000 mA (`cableCappedAt3A`,
  read from `UsbHvcMenu`) **and** the full 20 V rail **and** ≤60 W. A slow port
  fails that test because it drops the rail too, which a cable cap never does.

Lesson worth keeping: "under 3 amps" is not the e-marker signature. "Exactly
3000 mA on 20 V" is. The loose version blames the cable for anything low, which
is the single most expensive wrong answer this app could give — it sends
someone out to buy a cable that won't fix anything.

### Note

The UI is now verified — it renders correctly in dark mode, the readouts align,
the sparkline works, and the semantic colours read as intended (red at 30 W,
amber at 100 W, green at 140 W). That closes the item flagged as unverified in
the previous entry.
