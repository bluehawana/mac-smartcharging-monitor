APP      := SmartCharging
BUNDLE   := build/$(APP).app
CONFIG   := release
BINARY   := .build/$(CONFIG)/$(APP)

.PHONY: all build app run install clean

all: app

build:
	swift build -c $(CONFIG)

# Assemble a real .app bundle. A menu bar app needs one — NSStatusItem
# and MenuBarExtra rely on bundle identity, so a bare executable misbehaves.
app: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
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
