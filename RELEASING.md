# Releasing

Two one-time setup steps, then `make release` does everything else.

Both setup steps involve your Apple credentials, so run them yourself — no
build script should ever hold them.

---

## One-time setup

### 1. Create a Developer ID Application certificate

An **Apple Development** certificate is not enough. That one only runs code on
your own machines. Distribution outside the App Store needs a **Developer ID
Application** certificate, and only the Account Holder or an Admin on the team
can create one.

In Xcode: **Settings → Accounts → (your Apple ID) → Manage Certificates →
+ → Developer ID Application**.

Confirm it worked:

```bash
security find-identity -v -p codesigning
```

You want a line reading `Developer ID Application: Your Name (TEAMID)`. If you
only see `Apple Development:`, the certificate wasn't created.

### 2. Store a notary credential

Notarisation needs to authenticate to Apple. Use an **app-specific password**,
not your Apple ID password — create one at
[appleid.apple.com](https://appleid.apple.com) under Sign-In and Security →
App-Specific Passwords.

Run it as a **single line** and omit `--password`. notarytool then gives you a
secure prompt, so the password never reaches your shell history:

```bash
xcrun notarytool store-credentials smartcharging-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

This saves the credential into your login keychain under the profile name
`smartcharging-notary`, which is what the Makefile looks for. You never have to
pass the password again.

If you see `unexpected arguments: 'notarytool', 'store-credentials', ...`, the
command reached the shell twice — press **Ctrl+U** to clear the line and paste
once. Backslash-continued versions of this command are easy to mangle on paste,
which is why the single-line form is given here.

Your Team ID is the parenthesised code in the certificate name above, and is
also on the [membership page](https://developer.apple.com/account).

---

### Check both steps landed

```bash
make preflight
```

It names whichever piece is missing rather than failing part-way through a
submission. The signing identity is read from your keychain, so nothing
personal is written into the repo.

## Cutting a release

```bash
make release VERSION=1.0.0
```

That runs, in order:

| Step | What it does |
|------|--------------|
| `app` | Builds the binary and assembles the `.app` bundle with its icon |
| `sign` | Re-signs with your Developer ID, Hardened Runtime, secure timestamp |
| `dmg` | Builds a drag-to-Applications disk image |
| `notarize` | Submits to Apple, waits for the verdict, staples the ticket |
| `verify` | Prints what Gatekeeper will say on someone else's Mac |

Notarisation usually takes a few minutes. The staple matters: it embeds the
approval into the disk image so it validates even when the user is offline.

Then upload `build/SmartCharging-<version>.dmg` to GitHub Releases.

### If you hold more than one Developer ID

The first match in the keychain is used. Override it explicitly:

```bash
make release DEV_ID="Developer ID Application: Your Name (TEAMID)"
```

Note that an **Apple Development** certificate carries a different identifier
in its parentheses than your Team ID. Only the Developer ID certificate's
parenthesised code is the Team ID, and that is the one notarisation checks.

---

## Checking it worked

```bash
make verify
```

The line you need is `source=Notarized Developer ID`. Anything else means
Gatekeeper will warn the person downloading it.

To test the real download experience, the quarantine flag is what matters —
copying a file locally doesn't set it, so a local copy always opens even when
a downloaded one wouldn't:

```bash
xattr -w com.apple.quarantine "0081;00000000;Safari;" /tmp/SmartCharging.dmg
open /tmp/SmartCharging.dmg
```

---

## Why not the App Store

Measured, not assumed — the bundle was re-signed with
`com.apple.security.app-sandbox` and run:

| Capability | Sandboxed |
|---|---|
| `AppleSmartBattery` read | works |
| Process attribution via `/bin/ps` | blocked |
| SMC charge limit | impossible — needs a privileged helper |

A sandboxed build works as a monitor but loses the ability to name the process
draining your battery, and can never carry a charge limit. TestFlight is not a
way around this; it submits through App Store Connect with the same sandbox
and review requirements.

Direct distribution keeps every feature and avoids the platform cut, which is
why every comparable app — Mole, AlDente, coconutBattery — ships this way. An
App Store monitor-only edition remains possible later.
