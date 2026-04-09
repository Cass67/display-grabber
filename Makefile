# --- Tray app ---
# Build always runs as the current user (no sudo).
# install-tray requires sudo only for launchctl bootstrap.
TRAY_SRC      = tray/main.m
TRAY_APP      = dist/DisplayGrabber.app
TRAY_BIN      = $(TRAY_APP)/Contents/MacOS/DisplayGrabber
TRAY_PLIST    = $(TRAY_APP)/Contents/Info.plist
LAUNCH_AGENTS = $(HOME)/Library/LaunchAgents
AGENT_PLIST   = $(LAUNCH_AGENTS)/com.display-grabber.tray.plist
REAL_UID      := $(shell echo $${SUDO_UID:-$$(id -u)})
REAL_USER     := $(shell echo $${SUDO_USER:-$$(id -un)})

.PHONY: tray install-tray uninstall-tray

tray: $(TRAY_SRC) tray/Info.plist
	mkdir -p $(TRAY_APP)/Contents/MacOS
	mkdir -p $(TRAY_APP)/Contents/Resources
	clang -fobjc-arc \
	      -framework AppKit \
	      -framework CoreGraphics \
	      -framework CoreFoundation \
	      $(TRAY_SRC) -o $(TRAY_BIN)
	cp tray/Info.plist $(TRAY_PLIST)
	codesign --sign - --force $(TRAY_APP)

# install-tray does NOT depend on tray — always run 'make tray' first (as yourself, not sudo).
# Only launchctl bootstrap needs sudo.
install-tray:
	@test -f $(TRAY_BIN) || (echo "ERROR: run 'make tray' first (without sudo)"; exit 1)
	rm -rf $(HOME)/Applications/DisplayGrabber.app
	cp -r $(TRAY_APP) $(HOME)/Applications/
	mkdir -p $(LAUNCH_AGENTS)
	sed "s|APP_PATH|$(HOME)/Applications/DisplayGrabber.app/Contents/MacOS/DisplayGrabber|g" \
	    tray/launchagent.plist.template > $(AGENT_PLIST)
	chown $(REAL_USER) $(AGENT_PLIST)
	-launchctl bootout gui/$(REAL_UID) $(AGENT_PLIST) 2>/dev/null
	launchctl bootstrap gui/$(REAL_UID) $(AGENT_PLIST)

uninstall-tray:
	-launchctl bootout gui/$(REAL_UID) $(AGENT_PLIST) 2>/dev/null
	rm -f $(AGENT_PLIST)
	rm -rf $(HOME)/Applications/DisplayGrabber.app
