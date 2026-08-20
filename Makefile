APP      := SmartCharging
BUNDLE   := build/$(APP).app
CONFIG   := release
BINARY   := .build/$(CONFIG)/$(APP)

.PHONY: all build app run install clean icon sign dmg notarize release verify

# Distribution settings. Override on the command line if your identity or
# notary profile is named differently:
#   make release DEV_ID="Developer ID Application: Your Name (TEAMID)"
DEV_ID         ?= Developer ID Application
NOTARY_PROFILE ?= smartcharging-notary
VERSION        ?= 1.0.0
DMG            := build/$(APP)-$(VERSION).dmg
STAGE          := build/dmgroot

all: app

build:
	swift build -c $(CONFIG)

# Icon is generated from code rather than checked in as binary art, so a
# palette change is a one-line edit rather than a redraw.
icon:
	@mkdir -p build docs/images
	@swift Tools/makeicon.swift
	@iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "built Resources/AppIcon.icns"

# Assemble a real .app bundle. A menu bar app needs one — NSStatusItem
# and MenuBarExtra rely on bundle identity, so a bare executable misbehaves.
app: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	@codesign --force --deep --sign - $(BUNDLE) 2>/dev/null || \
		echo "note: ad-hoc signing unavailable; the app still runs locally"
	@echo "built $(BUNDLE)"

run: app
	@pkill -x $(APP) 2>/dev/null || true
	@open $(BUNDLE)

# Copy into /Applications so it survives a rebuild and can be a login item.
install: app
	@rm -rf /Applications/$(APP).app
	@cp -R $(BUNDLE) /Applications/
	@echo "installed to /Applications/$(APP).app"

clean:
	swift package clean
	@rm -rf build .build


# ---------------------------------------------------------------------------
# Distribution
#
# Notarisation requires three things Apple will not let a build script invent:
# a Developer ID Application certificate, the Hardened Runtime, and a stored
# notary credential. See RELEASING.md for the two one-time setup steps.
# ---------------------------------------------------------------------------

# Re-sign the bundle for distribution. Hardened Runtime (--options runtime)
# and a secure timestamp are both mandatory for notarisation.
sign: app
	@echo "signing with: $(DEV_ID)"
	@codesign --force --options runtime --timestamp \
		--sign "$(DEV_ID)" $(BUNDLE)
	@codesign --verify --strict --verbose=2 $(BUNDLE)

# A drag-to-Applications disk image, which is what people expect to download.
dmg: sign
	@rm -rf $(STAGE) $(DMG)
	@mkdir -p $(STAGE)
	@cp -R $(BUNDLE) $(STAGE)/
	@ln -s /Applications $(STAGE)/Applications
	@hdiutil create -volname "$(APP)" -srcfolder $(STAGE) \
		-ov -format ULFO $(DMG) >/dev/null
	@rm -rf $(STAGE)
	@echo "built $(DMG)"

# Submit, wait for the verdict, then staple so it validates offline.
notarize: dmg
	@echo "submitting to Apple — this usually takes a few minutes"
	@xcrun notarytool submit $(DMG) \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple $(DMG)
	@echo "stapled $(DMG)"

# What Gatekeeper will say on someone else's Mac.
verify:
	@echo "--- signature ---"
	@codesign -dv --verbose=4 $(BUNDLE) 2>&1 | grep -E "Authority|TeamIdentifier|Runtime" || true
	@echo "--- gatekeeper ---"
	@spctl -a -vvv -t install $(BUNDLE) 2>&1 || true
	@echo "--- staple ---"
	@xcrun stapler validate $(DMG) 2>&1 || true

release: notarize verify
	@echo
	@echo "$(DMG) is ready to upload to GitHub Releases."
