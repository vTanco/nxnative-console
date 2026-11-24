#!/bin/zsh
# Builds Console and installs it in /Applications (in ~/Applications when /Applications is not writable), with a login agent that keeps it
# waiting in the background so it comes up when a game controller connects. ./install.sh --no-autostart installs the app only.
set -e
cd "${0:A:h}"
LABEL=io.github.vtanco.console
AGENT=~/Library/LaunchAgents/$LABEL.plist
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || { echo "Console needs macOS 14 or later"; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc not found: install Xcode or its command line tools (xcode-select --install)"; exit 1; }
./build.sh
DEST=/Applications; [ -w $DEST ] || { DEST=~/Applications; mkdir -p $DEST; }
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
pkill -f "$DEST/Console.app/Contents/MacOS/Console" 2>/dev/null || true
rm -rf "$DEST/Console.app" && cp -R build/Console.app "$DEST/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Console.app"
if [ "$1" != --no-autostart ]; then
  mkdir -p ~/Library/LaunchAgents
  cat > $AGENT <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$DEST/Console.app/Contents/MacOS/Console</string><string>--hidden</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
  launchctl bootstrap gui/$(id -u) $AGENT
  echo "installed $DEST/Console.app; it starts at login and comes up when a controller connects"
else
  echo "installed $DEST/Console.app (no login agent)"
fi
