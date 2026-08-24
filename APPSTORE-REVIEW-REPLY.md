# App Review reply — Guideline 2.1, submission 9ed03ad9

Paste the "Reply text" section into App Store Connect → App Review → reply,
and attach the recording. Copy the same text into App Review Information →
Notes before resubmitting, as Apple asks.

## 1. Screen recording — to do on this Mac

Use the App Store build (sandboxed), not the direct-download one:

    open build/appstore/SmartCharging.app     # or the pkg-installed copy

Record with QuickTime (File → New Screen Recording) or ⇧⌘5. Keep it under
~2 minutes, 1080p or better. Script:

1. Start recording with the app NOT running and a charger attached.
2. Launch the app from Finder/Launchpad. Show the dashboard window opening.
3. Point out: delivered wattage, voltage rail, cable current ceiling,
   battery flow, the flow chart, temperature / health / cycle count.
4. Close the window. Show the menu bar item still reading live wattage.
5. Click the menu bar item → menu panel; reopen the dashboard from it.
6. Unplug the charger, then plug it into a different port (or use a
   different cable) so the diagnosis text and wattage visibly change.
7. Show Charger Memory reporting the drop, if the second port is slower.
8. Quit from the menu bar item.

There are no logins, purchases, user-generated content, or permission
prompts, so nothing else needs to appear. Attach the .mov to the reply.

## 2–7. Reply text

---

Thank you for the review. Responses to each item:

1. SCREEN RECORDING
Attached. It was captured on a MacBook Pro (Apple M5 Max, Mac17,6) running
macOS 26.6.2 (25G83), starting from app launch and walking through every
feature. The app has no account registration, login, purchases,
subscriptions, user-generated content, or prompts for sensitive data or
device capabilities, so none appear in the recording.

2. DEVICES AND OPERATING SYSTEMS TESTED
- MacBook Pro 16-inch, Apple M5 Max (Mac17,6), macOS 26.6.2 — primary
  development and test machine, including the sandboxed App Store build.
- Minimum supported system is macOS 14.0; the app is built for both Apple
  silicon and Intel.

3. WHAT THE APP DOES AND FOR WHOM
Smart Charging Monitor is a menu bar utility that shows the power a Mac is
actually receiving from its charger. macOS only shows "Charging"; it never
shows the delivered wattage, the negotiated USB-C voltage rail, or the
cable's current ceiling. The app reads those values from the system's
AppleSmartBattery sensor and explains which part of the chain — cable
without an e-marker, a low-power port, a shared multi-port charger, or a
negotiation that settled low — is limiting the supply.

Problem solved: a 100 W charger with a 3 A cable silently negotiates 60 W;
under sustained load (compiling, video export, running local AI models) the
Mac drains its battery while plugged in and throttles, which users
misdiagnose as a slow machine. The app names the real cause. It also
remembers the best a charger has offered and reports later drops, and
tracks battery temperature, health, cycle count and time spent at high
charge.

Target audience: Mac users, particularly developers, video editors and
people running local machine-learning workloads, who rely on USB-C charging
and want to know whether their charger, cable and port are delivering what
they paid for.

4. SETUP AND ACCESS
No setup, account, credentials, or sample files are required.
- Launch the app. A dashboard window opens and a wattage reading appears in
  the menu bar.
- Closing the window keeps the app running in the menu bar; click the menu
  bar item to see the summary panel or reopen the dashboard.
- A charger must be connected for meaningful readings. On battery power the
  app shows the discharge rate and notes that no charger is attached.
- To see the diagnosis change, plug the same charger into a different port
  or use a different cable.
- Quit from the menu bar item.

5. EXTERNAL SERVICES
None. The app makes no network requests and uses no data providers,
authentication services, payment processors, analytics, or AI services. All
readings come from the local AppleSmartBattery IOKit registry entry, which
the App Sandbox permits without additional entitlements. History is stored
locally in ~/Library/Application Support/SmartCharging. The App Privacy
label is "Data Not Collected". The complete source is public under the MIT
licence at https://github.com/bluehawana/mac-smartcharging-monitor, so the
absence of network code can be verified directly.

6. REGIONAL DIFFERENCES
None. The app functions identically in all regions; it has no
region-dependent features, content, or pricing (it is free).

7. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app does not operate in a regulated industry and
contains no protected third-party material. All code and assets are
original and MIT-licensed (https://github.com/bluehawana/mac-smartcharging-monitor).

---
