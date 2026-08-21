# App Store Connect listing

Every field below is within its limit — verified, not estimated.


## App name  (14/30)

```
Smart Charging
```


## Subtitle  (27/30)

```
See what your charger gives
```


## Promotional text  (143/170)

```
macOS reports Charging but never how much. This reads the sensor and identifies whether the cable, the port or the negotiation is limiting you.
```


## Keywords  (86/100)

```
charger,battery,wattage,usb-c,power,watt,charging,macbook,adapter,cable,health,monitor
```


## Description  (2591/4000)

```
Smart Charging reports the power your Mac is actually receiving, and identifies which part of the chain is limiting it.

macOS shows "Charging" whenever an adapter is attached, but never the delivered wattage, the negotiated voltage, or the cable's current ceiling. Those figures exist on every Mac. They are simply not surfaced anywhere in the interface.

WHY IT MATTERS

A 100 W charger paired with a 3 A cable negotiates 60 W. During ordinary work that goes unnoticed. Under sustained load — compiling, video export, or running a model locally with Ollama or MLX — your Mac draws more than the supply provides, makes up the difference from the battery, and is throttled to fit inside what remains.

The result reads as a slow machine rather than a power problem, and it is usually diagnosed as neither.

WHAT IT SHOWS

• Delivered wattage, live in the menu bar
• The negotiated voltage rail and the cable's current ceiling
• Power flowing into or out of the battery, in watts
• A running chart of that flow
• Battery temperature, health and cycle count

NAMING THE CAUSE

Similar wattages have different causes and opposite fixes:

• A cable without an e-marker chip caps at 3 A, giving 60 W on a full 20 V rail
• A low-power port lowers the voltage instead, giving 30 W on a 12 V rail
• A multi-port charger divides its total when a second device is attached
• A negotiation can settle below what the port supplies and remain there

Reading current and voltage together separates these. Wattage alone cannot.

CHARGER MEMORY

Smart Charging records the best a charger has offered. If the same charger later offers less — after changing ports, attaching another device, or a negotiation that settled low — that drop is reported rather than absorbed.

BATTERY LONGEVITY

Being plugged in is not inherently bad for a battery. Being plugged into something too small is: the pack cycles continuously while the chip runs hot, and heat and cycling are the two mechanisms that age lithium cells. Smart Charging tracks time spent at high charge, temperature exposure, and charge-direction reversals, and reports what your current setup is doing.

PRIVACY

Readings come from the AppleSmartBattery sensor on your own machine. No network access, no accounts, no analytics, no data collection of any kind. History is stored locally in Application Support.

OPEN SOURCE

Complete source is published under the MIT licence at github.com/bluehawana/mac-smartcharging-monitor

REQUIREMENTS

macOS 14 or later. Apple silicon and Intel. A Mac with a battery — desktop Macs have no charging sensor to read.
```


## What's New  (348/4000)

```
First release.

Reports delivered wattage, negotiated voltage and cable current ceiling from the AppleSmartBattery sensor, and identifies whether the cable, the port, or the power negotiation is limiting your Mac.

Includes battery longevity tracking: time at high charge, temperature exposure, and the charge cycling an undersized supply produces.
```


## URLs required by App Store Connect

| Field | Value |
|---|---|
| Privacy Policy URL | `https://charging.bluehawana.com/privacy.html` |
| Support URL | `https://github.com/bluehawana/mac-smartcharging-monitor/issues` |
| Marketing URL | `https://charging.bluehawana.com` |
| Copyright | `2026 Hongzhi Li` |

Privacy Policy is mandatory. A submission cannot proceed without it.

## Privacy nutrition label

Answer **Data Not Collected**. That is accurate: the app reads a local
hardware sensor, makes no network requests, and stores history only in
`~/Library/Application Support/SmartCharging`.

Do not tick any category. Ticking one you do not actually use invites review
questions you cannot answer.

## Screenshots

Use `docs/appstore-ready/2880x1800/` — three verified slides.

**Do not use the menu bar panel capture** (`docs/images/menubar-panel.png`) in
the App Store listing. It shows the "Using the most CPU" section, which is
compiled out of the App Store build because the sandbox blocks process
inspection. A screenshot showing a feature the submitted binary does not have
is grounds for rejection.

## Category and rating

| Field | Value |
|---|---|
| Primary category | Utilities |
| Secondary category | Developer Tools |
| Age rating | 4+ |
| Price | Free |
