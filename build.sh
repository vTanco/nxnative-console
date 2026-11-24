#!/bin/zsh
# Builds build/Console.app from the sources (Xcode or its command line tools give swiftc). ./install.sh builds and installs it.
set -e
cd "${0:A:h}"
if [ ! -f Resources/AppIcon.icns ]; then   # the icon is in the repository; this redraws it when it is deleted
  T=$(mktemp -d); swiftc -O Resources/icon.swift -o $T/icon && $T/icon $T/icon-1024.png
  mkdir $T/AppIcon.iconset
  for n in 16 32 128 256 512; do
    sips -z $n $n $T/icon-1024.png --out $T/AppIcon.iconset/icon_${n}x${n}.png >/dev/null
    sips -z $((n*2)) $((n*2)) $T/icon-1024.png --out $T/AppIcon.iconset/icon_${n}x${n}@2x.png >/dev/null
  done
  iconutil -c icns $T/AppIcon.iconset -o Resources/AppIcon.icns; rm -rf $T
fi
APP=build/Console.app; rm -rf $APP; mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 Sources/main.swift -o $APP/Contents/MacOS/Console
cp Resources/Info.plist $APP/Contents/; cp Resources/AppIcon.icns $APP/Contents/Resources/
codesign --force --sign - $APP   # ad-hoc: built on this Mac, so Gatekeeper does not quarantine it
echo "built $APP"
