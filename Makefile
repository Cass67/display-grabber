.PHONY: lint typecheck check install dev-install

lint:
	ruff format src/ && ruff check --fix src/

typecheck:
	pyright src/

check: lint typecheck

install:
	pip install .

dev-install:
	pip install -e .

# --- Tray app ---
TRAY_SRC     = tray/main.m
TRAY_APP     = dist/DisplayGrabber.app
TRAY_BIN     = $(TRAY_APP)/Contents/MacOS/DisplayGrabber
TRAY_PLIST   = $(TRAY_APP)/Contents/Info.plist
LAUNCH_AGENTS = $(HOME)/Library/LaunchAgents
AGENT_PLIST  = $(LAUNCH_AGENTS)/com.display-grabber.tray.plist
UID          := $(shell id -u)

.PHONY: tray install-tray uninstall-tray

tray: $(TRAY_SRC) tray/Info.plist
	mkdir -p dist
	mkdir -p $(TRAY_APP)/Contents/MacOS
	mkdir -p $(TRAY_APP)/Contents/Resources
	clang -fobjc-arc \
	      -framework AppKit \
	      -framework CoreGraphics \
	      -framework CoreFoundation \
	      $(TRAY_SRC) -o $(TRAY_BIN)
	cp tray/Info.plist $(TRAY_PLIST)
	codesign --sign - --force $(TRAY_APP)

install-tray: tray
	cp -r $(TRAY_APP) ~/Applications/
	mkdir -p $(LAUNCH_AGENTS)
	sed "s|APP_PATH|$(HOME)/Applications/DisplayGrabber.app/Contents/MacOS/DisplayGrabber|g" \
	    tray/launchagent.plist.template > $(AGENT_PLIST)
	launchctl bootstrap gui/$(UID) $(AGENT_PLIST)

uninstall-tray:
	-launchctl bootout gui/$(UID) $(AGENT_PLIST) 2>/dev/null
	rm -f $(AGENT_PLIST)
	rm -rf ~/Applications/DisplayGrabber.app
