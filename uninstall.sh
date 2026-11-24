#!/bin/zsh
# Removes Console, its login agent and its settings. Your games are not touched.
LABEL=io.github.vtanco.console
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null
rm -f ~/Library/LaunchAgents/$LABEL.plist
for d in /Applications ~/Applications; do pkill -f "$d/Console.app/Contents/MacOS/Console" 2>/dev/null; rm -rf "$d/Console.app"; done
defaults delete $LABEL 2>/dev/null
echo "Console removed (~/Library/Application Support/Console/extra.txt, if you made one, is kept)"
