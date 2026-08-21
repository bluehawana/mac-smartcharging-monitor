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

### Control test — the cable, isolated

A third cable (Cirafon, generic) produced 60 W at 20 V with a 3000 mA ceiling.
Tested across four combinations — UGREEN C1 and C2, into both the left and
right Type-C ports on the Mac — and the number never moved off 60 W.

Change every port on both ends, no effect. Swap only the cable, 140 W. That is
about as clean an isolation as this kind of fault allows, and it is now in the
README as the control table.

It also confirms the tightened rule works on real hardware in both directions:
this reading correctly says **cable** (3000 mA on a full 20 V rail), while the
30 W port reading correctly says **port** (12 V). Before the fix, both said
"cable".

---

## 2026-08-20 (evening) — Systematic port/cable matrix, and three more bugs

### Test process

Ran every combination available on the desk, reading each with `--probe` and
the dashboard. One variable changed at a time.

**Cables tested** (all into UGREEN Nexode 200 W, port C1, the 140 W port):

| Cable | Rail | Current | Delivered |
|-------|-----:|--------:|----------:|
| UGREEN 240 W PD 3.1 | 28 V | 4990 mA | **140 W** |
| Apple M1-era USB-C | 20 V | 5000 mA | 100 W |
| Cirafon generic | 20 V | 3000 mA | 60 W |

Three cables, one port, three tiers. The Apple M1 cable is the instructive
one: it is *properly e-marked* at a full 5 A, and still stops at 100 W,
because it predates PD 3.1 and never offers the 28 V rail. "E-marked" is not
binary — there are two tiers, 5 A/20 V (100 W) and 5 A/48 V EPR (240 W).

**Ports tested** (UGREEN 240 W cable):

| Charger port | Rail | Current | Delivered |
|--------------|-----:|--------:|----------:|
| C1 | 28 V | 4990 mA | 140 W |
| C2 | 20 V | 4990 mA | 100 W |
| C3 | 12 V | 2500 mA | 30 W |

**Cable isolation.** The Cirafon cable was then tried in four combinations —
UGREEN C1 and C2, into both the left and right Type-C ports on the Mac. 60 W
every time. Change every port on both ends, no movement; swap only the cable,
140 W. Both Mac-side ports behave identically, so the side you plug into does
not matter — only the charger's port does.

### Three bugs this exposed

All three had the same root cause: **testing current without checking the
rail.** A cable cap lowers current; a slow port lowers voltage *and* current.
Anything that looks only at current blames the cable for a port fault.

1. `cableCappedAt3A` returned true for the 30 W port (2500 mA). Now requires
   ≥19 V as well.
2. Two `--probe` annotations said "no e-marker" and "capped at 3 A by the
   cable" on the 30 W port. Both now use the corrected helper, and a low rail
   prints "this port never offers the full 20 V rail" instead.
3. `ChargerMemory.downgrade` said "probably a different cable" when moving
   C1→C3, because the current ceiling dropped along with the rail. Reordered
   to check the rail first: a cable can only limit current, never voltage, so
   a dropped rail is the port regardless of what the current did.

### A misdiagnosis I made about my own fix

I claimed the 21:02 screenshot validated the earlier port/cable fix. It did
not — the 60 W case reads identically before and after, so that screenshot
could not distinguish the two builds. What actually happened is the app under
test had been launched at 20:55, four minutes *before* the 20:59 rebuild, so
every screenshot up to 21:10 was from the stale binary. Verified by comparing
process start time against binary mtime. Restarted, re-tested, and the 30 W
case now correctly reports the port.

Lesson: when verifying a fix from a screenshot, check that the screenshot came
from a build containing the fix, and pick a test case whose output actually
differs between the two versions.

### Two honesty corrections in the copy

- **65 W is genuinely ambiguous.** A multi-port charger splitting power and a
  real single-port 65 W charger both negotiate 20 V / 3.25 A. The reading
  cannot tell them apart. The copy previously asserted "your charger is
  splitting power"; it now presents both and says which evidence separates
  them. This matters more on older Macs, where 65 W third-party chargers are
  common and there is no fault at all.
- **`advertisedMaxW` under-reported under EPR.** PD 3.1's 28 V profiles are
  negotiated outside `UsbHvcMenu`, so the probe printed "Best offer 99 W"
  while delivering 140 W. Now floored at whatever is actually being delivered.

### Older Mac support

Reading the sensor on Intel and pre-USB-C machines needs different handling,
now added:

- **Charge percentage.** Apple silicon reports `CurrentCapacity` as a
  percentage; Intel reports it in mAh. Detected by `MaxCapacity > 100` and
  converted, with health derived from `DesignCapacity`. Without this, an Intel
  Mac would have shown a "charge" of several thousand percent.
- **Adapter voltage key.** Apple silicon uses `AdapterVoltage`, Intel uses
  `Voltage`. Both are read now.
- **No profile menu.** Intel and MagSafe 1/2 chargers report watts with no
  `UsbHvcMenu` at all. Wattage is derived from volts × amps when missing, and
  every cable rule is inert without a menu — so a MagSafe machine is never
  told to buy a USB-C cable.
- **Machines without a battery.** Mac mini, Studio, and Pro have no
  `AppleSmartBattery`. Now says so plainly instead of reporting a read failure.

**The real floor is macOS 14**, not the hardware. `MenuBarExtra` needs 13 and
`@Observable` needs 14. That still covers Intel MacBooks from roughly 2018
onward, since those run Sonoma. Dropping to 13 would mean replacing
`@Observable` with `ObservableObject` across every view — worth doing only if
people actually ask for it.

### Icon

Generated from code (`Tools/makeicon.swift`) rather than checked in as
finished art, so a palette change is a one-line edit. A bolt inside a gauge
arc that is deliberately *short* of full — the app is about the gap between
what you should be getting and what you are. `make icon` regenerates the
`.icns`.

### App Store viability — tested, not assumed

App Store (and TestFlight, which submits through the same pipeline) requires
the app to be sandboxed. Rather than guess what survives that, the bundle was
re-signed with `com.apple.security.app-sandbox` and run:

| Capability | Sandboxed | Notes |
|---|---|---|
| `AppleSmartBattery` read via IOKit | **works** | Full reading: watts, rail, current, flow, health |
| `ProcessWatch` via `/bin/ps` | **blocked** | Returns nothing; `Process` cannot exec in the sandbox |
| SMC charge limit | **impossible** | Needs a privileged helper, which App Store apps cannot install |

So an App Store build is possible but loses process attribution — the "oMLX is
what your charger is losing to" feature — and can never carry the charge limit
that was meant to be the paid anchor.

`--probe` now prints top processes, partly because it is useful and partly
because it makes this exact difference visible from the command line.

Conclusion: direct distribution (Developer ID + notarisation) first. It keeps
every feature, avoids the platform cut, and is what every comparable app in
this category — Mole, AlDente, coconutBattery — does, for these reasons. An
App Store "monitor only" edition stays possible later if reach matters more
than capability. TestFlight is not a shortcut around any of this; it carries
the same sandbox and review requirements.

---

## 2026-08-20 (night) — Signed, notarised, shipped

`make release VERSION=1.0.0` completed end to end. Apple returned
`status: Accepted`, the ticket stapled, and Gatekeeper reports
`source=Notarized Developer ID`.

### The Gatekeeper gap worth knowing about

First notarisation passed and stapled, but testing the *download* experience
told a different story. Copying a file locally never sets the quarantine flag,
so a local copy always opens even when a downloaded one would not. Faking it:

```
xattr -w com.apple.quarantine "0081;00000000;Safari;" file.dmg
spctl -a -vvv -t open --context context:primary-signature file.dmg
```

Result: `rejected — source=no usable signature`.

The app inside was correctly signed and notarised; the **disk image itself was
not signed**. Notarising and stapling a `.dmg` does not sign it. Fixed by
signing the image after `hdiutil create` and before submission — the order
matters, because signing rewrites the file and would invalidate a staple
applied first.

After the fix the quarantined copy reports
`accepted — source=Notarized Developer ID`.

Lesson: verifying a release against an un-quarantined local copy proves
nothing about what a downloader sees.

### Two preflight checks, one of which was wrong

`preflight` originally looked for the notary credential with
`security find-generic-password`. It reported the credential missing straight
after notarytool had saved it successfully — because notarytool stores it in
the data-protection keychain, which the legacy `security` CLI cannot read.
Replaced with a question to notarytool itself, which answers locally before
making any network call.

The certificate check was right and earned its place: the account had an
**Apple Development** certificate, which cannot be notarised, and no
**Developer ID Application** certificate. That is the usual first stumble and
now fails with an explicit instruction rather than a signing error.

### Credentials

Nothing secret is stored in the repo, and nothing needs to be. The notary
credential lives in the macOS keychain and is referenced only by profile name;
the signing identity is discovered from the keychain at build time, so no
personal name or team id is committed either. `.gitignore` now covers `.env`,
`*.p8`, `*.p12`, `*.pem`, `*.key`, `*.cer`, `*.mobileprovision` and `AuthKey_*`
defensively, and `.env.example` documents build-configuration overrides only —
with an explicit note that writing an app-specific password into a file would
be less safe than where it already is.

### Not the App Store

Direct distribution, per the sandbox testing above: an App Store build keeps
the monitor but loses process attribution and can never carry a charge limit.

---

## 2026-08-20 (end of day) — Shipped

Smart Charging 1.0.0 is signed, notarised, and published. Verified end to end
against a quarantined copy — the file a browser actually produces — which
reports `accepted, source=Notarized Developer ID`.

Two install paths work:

    brew install --cask bluehawana/tap/smartcharging
    or the .dmg from GitHub Releases

Landing page live at http://charging.bluehawana.com — a subdomain, because the
account's user site claims www.bluehawana.com and that domain resolves to
Cloudflare rather than GitHub Pages. Every project page under the account gets
redirected there and lands on the portfolio instead, which no setting on the
project repo can override. A dedicated subdomain sidesteps the handoff
entirely.

Also shipped: bluehawana/appstore-screenshot-forapps, a Mac App Store
screenshot generator, built because every existing tool targets iPhone and
Android. Five layouts, JSON config, optional window capture, no dependencies.

### Open

1. **HTTPS certificate** still pending with GitHub after ~30 minutes. Share
   http:// until it issues. If still pending, remove and re-add the domain in
   repo Settings → Pages to force revalidation, then enable enforcement.
2. **The 30 W capture.** Every screenshot taken before 21:10:53 came from the
   pre-fix build and shows the app blaming the cable for a slow port. To
   redo: plug into the charger's 30 W port, open the app window, then
   `swift Tools/makeshots.swift --capture "SmartCharging" docs/images/port-c3-30w.png`
   followed by a plain regenerate. Meanwhile `screenshots-ready.json` builds
   three verified slides that are safe to publish.
3. **LinkedIn post** written and ready.
4. **SMC charge limit** — the paid feature, and the reason this ships outside
   the App Store. The Developer ID and notarisation pipeline needed for its
   privileged helper are now in place.

---

## 2026-08-20 (late) — A third failure mode, found by running the app

Plugged into the charger's 30 W port, the app read **22 W** on a 12 V rail with
a 1830 mA ceiling. The offered menu was flat — 9 V/2.44 A and 12 V/1.83 A both
land on 22 W — which reads like a phone brick, and I said so.

Wrong. Unplugging and reconnecting the same cable in the same port restored
**30 W** at 12 V/2500 mA.

So the negotiation had settled *below what the port could actually supply* and
stayed there. That is a third failure mode, distinct from the two the app
already handled:

| Symptom | Cause | Fix |
|---|---|---|
| 3000 mA on a full 20 V rail | Cable has no e-marker | Replace the cable |
| Low rail (12 V, 15 V) | Slow port, or a hub in the way | Move to the main port |
| **Same rail, lower current than before** | **Negotiation stuck low** | **Reconnect the cable** |

### The gap it exposed

`ChargerMemory.downgrade` treated "same rail, lower current" as evidence of a
cable change — the only explanation I had when writing it. That is the most
expensive wrong answer this app can give: it sends someone to buy a cable when
reseating the one they own would have fixed it.

Reworded to suggest the reconnect first, and only then the cable. A reconnect
costs nothing to try; a cable does not.

### Why this matters for the product

Nobody would find this by hand. There is no symptom beyond "charging feels
slow", the wattage is plausible, and the fix — unplug and replug — is
indistinguishable from superstition unless you can see the number change.

That is the clearest argument yet for the app existing: it turns an invisible
degradation into a number you can watch recover.

### Also confirmed working

The battery health tracker now has real data and reads **Gentle** — 0% above
90%, no time over 35 °C, 1–2 reversals/hour. Those reversals are the
micro-cycling the module was written to measure, showing up exactly where
predicted: on an undersized supply, sitting near break-even.

---

## 2026-08-20 (final) — Site carries both tools; launch framing settled

The landing page now promotes the screenshot generator alongside the app, with
three copy-ready install commands (clone, render, or curl the single file).
The audience overlaps almost exactly: someone reading about Mac charging
because they build Mac apps is the same person who will shortly need App Store
screenshots and discover every generator targets iPhone and Android.

Verified live at charging.bluehawana.com — both the brew one-liner and the
screenshot section are being served.

### Launch framing

Rewrote the launch post to withhold explanations rather than deliver them.
Three findings stated as numbers with no mechanism — 100 W charger giving
60 W, one cable across three ports giving 140/100/30 W, and a port silently
dropping to 22 W until replugged — so the only way to resolve the curiosity is
to visit the page. The earlier draft explained everything up front, which read
well but gave nobody a reason to click.

Framed as "project #10 of my new year", which signals a body of work without
claiming anything.

### Still open

- **HTTPS certificate** has not issued after roughly an hour. The post must
  use the bare domain, not `https://`, until it does. If it stays pending,
  remove and re-add the domain in repo Settings → Pages to force
  revalidation, then enable `https_enforced`.
- **The 30 W capture** is still pre-fix and cannot ship. Three verified slides
  are ready via `screenshots-ready.json`.

---

## 2026-08-21 — Website rewritten, App Store submission prepared

### Website

Corrected a framing error worth recording. The cable table headed its
right-hand column "Ceiling", which invites reading a 240 W cable rating as a
charging rate. Apple does sell a 240 W cable, so the row was factually right;
the column name was not. It now reads "Cable rating", with a callout stating
that no Mac charges at 240 W — 140 W on the 16-inch MacBook Pro is the highest
any model accepts — and a table of what each model actually draws.

Rewrote the tone throughout. The headline was "Your charger is probably lying
to you"; it is now "Know what your Mac is actually receiving". Section
headings became descriptive, and the app section leads with the two things a
reader cares about — sustained performance and battery longevity — described
as mechanisms rather than claims.

### Charger generation comparison

Photographed the two UGREEN chargers together, four years apart, and read
their labels. The rated totals (100 W against 200 W) are the wrong comparison.
The 2022 CD226's highest rail is 20 V, so 100 W is a hardware ceiling that no
cable can lift. 140 W requires the 28 V rail introduced with USB-PD 3.1, which
a charger either offers or does not.

Every label figure matched what the app measured — C1 140 W at 28 V, C2 100 W
at 20 V, C3 30 W at 12 V, and the older unit 99 W at 20 V. That agreement is
the actual argument: the specification is accurate and printed on the
underside of the charger, and is simply never visible while you work.

### In-browser analyser

A native app cannot run in a browser, but the analysis can. The rules from
Diagnosis.swift are ported to JavaScript and execute client-side, so a visitor
can click a sample reading or paste one command's output from their own Mac.
Nothing is uploaded, so no server is needed.

Testing it caught a real bug: InstantAmperage exceeds Number.MAX_SAFE_INTEGER,
so parseInt rounded it and the two's-complement conversion returned a wrong,
often positive, value. Every discharging state was being read as charging.
Fixed with BigInt.

Also corrected an overclaim in the copy. "Check your own Mac in the browser —
no install" implies clicking and seeing your own data; it actually requires
running one command. The button now says "See a live reading", which is what
pressing it does.

### App Store submission

Created the Apple Distribution and 3rd Party Mac Developer Installer
certificates, registered com.bluehawana.smartcharging, and generated a Mac App
Store provisioning profile, working through the portal in the browser. The key
was generated with openssl and imported into the login keychain; no key
material remains in the working tree, and every filename the portal produces is
gitignored.

App record created — Apple ID 6803880963. "Smart Charging" was already taken,
so the listing is "Smart Charging Monitor". Everything else keeps the original
name: renaming the repo, cask or site would break a shipped release for no
gain, and store listing names routinely differ from product names.

### Two upload rejections, both instructive

**90886** — the signature was missing an application identifier while the
provisioning profile had one. The entitlements declared only the sandbox; App
Store builds must also carry com.apple.application-identifier and
com.apple.developer.team-identifier in the signature itself.

**90242** — Info.plist must declare LSApplicationCategoryType. Meaningless for
direct distribution, so it had never been needed.

Both share a shape worth remembering: codesign and plutil verified the build
without complaint, and only Apple's upload validator knew what was missing.
Local verification cannot substitute for an upload attempt, so these arrive one
at a time.

Added ITSAppUsesNonExemptEncryption = false while fixing the second. It is
accurate and removes the export compliance question from every future
submission.

### altool

Three separate failures: a notarytool flag it does not accept, a missing
--item on the command meant to store a credential, and finally a refusal to
accept an Apple ID password where an app-specific one is required — none of
which it explains before failing. It is deprecated. Transporter is the
recommended path and needs no app-specific password at all.

### Open

1. Upload the package. It is correct now; the last attempt failed on
   authentication rather than on the build.
2. EU trader status. Mandatory for a Sweden-based developer under the DSA, and
   declaring it as an individual publishes name and address on the listing.
   A decision, not a formality.
3. Remaining listing fields: subtitle, category, copyright.
4. Privacy label: Data Not Collected, which is accurate.

---

## 2026-08-21 (afternoon) — Submitted to the App Store

Status: **1.0 Waiting for Review**, build 1.0.0 (2), Apple ID 6803880963.

### Three rejections before the build was accepted

**90886** — the signature was missing an application identifier while the
provisioning profile carried one. Entitlements declared only the sandbox; App
Store builds must also sign in com.apple.application-identifier and
com.apple.developer.team-identifier, matching the profile exactly.

**90242** — Info.plist must declare LSApplicationCategoryType. Meaningless for
direct distribution, so it had never been needed.

**91109** — com.apple.quarantine on Contents/embedded.provisionprofile. The
profile is downloaded through a browser, macOS tags downloads with that
attribute, and it travels into the bundle when copied. This one is the most
instructive of the three: it passed upload validation and only failed minutes
later during processing, so the terminal reported "UPLOAD SUCCEEDED" while
TestFlight showed Failed and App Store Connect showed no icon. `xattr -cr` now
runs before signing.

The shared lesson: codesign and plutil verify a build that Apple then refuses.
Local checks cannot substitute for an upload, and the failures arrive one at a
time.

### altool

Three separate authentication failures — a notarytool flag it does not accept,
a missing --item on the command meant to store a credential, and a refusal to
take an Apple ID password where an app-specific one is required. None explained
before failing. Omitting -p entirely, so it prompts on stdin, is what finally
worked. Transporter remains the better tool.

### Listing

Name is "Smart Charging Monitor" — "Smart Charging" was taken. Everything else
keeps the original name: renaming the repo, cask or site would break a shipped
release for nothing, and store listing names routinely differ from product
names.

Content Rights declared as no third-party content. Age rating 4+ across 172
countries. App Privacy published as Data Not Collected, which is accurate and
verifiable — the privacy page documents how to confirm the absence of network
activity independently. Sign-in requirement unticked, since the app has no
accounts.

Review notes explain where to find a menu bar app after launch, that a charger
must be attached for meaningful values, and that reading AppleSmartBattery needs
no entitlement beyond the sandbox. A reviewer who launches a menu bar app, sees
the window close and finds nothing in the Dock could reasonably conclude it does
nothing.

### The icon question

"Why no logo" had a real answer rather than a caching quirk: App Store Connect
reads the icon from a processed build, and there was no processed build while
91109 kept failing. The placeholder disappeared the moment build 2 completed.

### Open

1. Await review. 50% within 24 hours, 90% within 48.
2. Publish the launch post. The site, direct download and Homebrew install all
   work today regardless of the review outcome.
3. SMC charge limit remains the intended paid feature, and remains impossible
   in the App Store edition.
