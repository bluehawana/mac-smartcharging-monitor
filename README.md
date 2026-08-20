# Smart Charging

A macOS menu bar app that tells you what your charger is **actually** delivering —
and, in plain language, what to do about it.

Your Mac negotiates power with the charger every time you plug in, and the result
is often far below what you paid for. A "100 W" charger with the wrong cable
delivers 60 W. macOS never mentions it: the menu bar says *Charging* while the
battery goes down.

That gap stays invisible during ordinary work. It stops being invisible the moment
you run a local model with **Ollama** or **oMLX**, which pushes an Apple silicon
chip to close to its highest sustained draw — higher than compiling, higher than
exporting video. Then the machine gets hot, throttles, and drains while plugged in.

## What it does

- **Lives in the menu bar.** Shows live delivered wattage. Close the window and
  the app keeps measuring from the top right of your screen.
- **Names the fault.** Not just numbers — it distinguishes *your cable is the
  limit* from *your charger is splitting power*, which look nearly identical
  (60 W vs 65 W) and have completely different fixes.
- **Shows whether you're winning.** A running chart of battery flow. Above the
  line you're gaining charge; below it you're losing.
- **Explains it for non-technical users.** A built-in guide covering cables,
  MagSafe vs USB-C, multi-port power sharing, and what to buy in what order.

## Build and run

Requires macOS 14+ and Xcode command line tools.

```bash
make run
```

To keep it around:

```bash
make install    # copies to /Applications
```

Then add it to **System Settings → General → Login Items** so it starts with your Mac.

## Command line

One reading as text — handy over SSH, or to paste into a bug report:

```bash
SmartCharging --probe
```

```
SmartCharging probe
────────────────────────────────────────────────────
Adapter          connected
Delivered        100 W
Rail voltage     20000 mV
Cable ceiling    4990 mA
Charge           80 %
Battery flow     -21.39 W  (-1745 mA)
System draw      ~121 W  (adapter saturated)
────────────────────────────────────────────────────
100 W — standard full speed

Your cable and charger are working correctly at the normal USB-C limit.
Under heavy sustained work — running a local AI model, for instance —
your Mac wants more than this, so the battery slowly drains.
```

That reading is real: a 16-inch MacBook Pro (M5 Max) running a 27B model under
oMLX, pulling **121 W** against a 100 W supply.

## How to read the numbers

The exact wattage identifies the fault. These are one watt apart and mean
entirely different things:

| Watts | Current | What it means | Fix |
|------:|--------:|---------------|-----|
| 60 | 3000 mA | Cable has no e-marker chip, hard-capped at 3 A | Replace the cable |
| 65 | 3250 mA | Charger is splitting power between ports | Empty other ports, unplug from mains 15 s |
| 30 | 3000 mA | Low-priority port, or a hub/monitor in the way | Move to the charger's main port |
| 100 | 5000 mA | Full standard USB-PD | Fine unless you run large models |
| 140 | 4990 mA | Full PD 3.1 — note the 28 V rail | Nothing |

Above 3 amps, a USB-C cable must contain an identifying chip called an
**e-marker**. Without one the charger is *required by the standard* to stop at
3 A — which is 60 W. The charger isn't weak; it's being refused.

## Why cables matter more than people expect

| Cable | Ceiling | How to spot it |
|-------|--------:|----------------|
| Basic USB-C, bundled with phones | 60 W | Thin, smooth plastic |
| Apple USB-C Charge Cable | 60 W | Thin white plastic — looks like the good one |
| 5 A e-marked (PD 3.0) | 100 W | Usually printed "100W", often braided |
| 240 W e-marked (PD 3.1) | 240 W | Printed "240W" or "EPR" |
| Apple 240 W Charge Cable | 240 W | Thick, fabric-woven |
| MagSafe 3 | 140 W | Magnetic connector |

The fastest test: **woven means fast, smooth plastic means 60 W.**

MagSafe is a shape, not extra power — on current MacBook Pros both paths reach
140 W. Choose it for the magnetic breakaway and the freed USB-C port.

## Project layout

```
Sources/SmartCharging/
  PowerMonitor.swift    IOKit reader — AppleSmartBattery, polled every 2 s
  Diagnosis.swift       Rules that turn a reading into a cause and a fix
  MenuPanelView.swift   The menu bar panel
  DashboardView.swift   The full window and guide
  Theme.swift           Palette, readouts, sparkline
  Probe.swift           --probe text output
docs/index.html         Standalone web version of the guide
```

Readings come from the `AppleSmartBattery` IOService. No elevated privileges, no
network access, nothing leaves the machine.

## A note on what's measured vs inferred

Delivered wattage, rail voltage, cable ceiling, battery flow, charge, health, and
temperature are read directly from the sensor.

System draw is only shown when the adapter is **saturated** — when the machine is
taking everything the adapter can give and still pulling from the battery. Then
draw = adapter ceiling + the deficit, which is exact. At any other time macOS does
not expose the adapter's actual output, so the app doesn't guess.

## License

MIT.
