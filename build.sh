#!/bin/zsh
# Builds WorldCup26.app — a universal (Apple Silicon + Intel) menu bar app.
set -e
cd "$(dirname "$0")"

echo "==> Compiling (arm64 + x86_64, macOS 13+)..."
mkdir -p .build
swiftc -O -swift-version 5 -parse-as-library \
    -target arm64-apple-macos13.0 Sources/*.swift -o .build/WorldCup26-arm64
swiftc -O -swift-version 5 -parse-as-library \
    -target x86_64-apple-macos13.0 Sources/*.swift -o .build/WorldCup26-x86_64
lipo -create .build/WorldCup26-arm64 .build/WorldCup26-x86_64 -output .build/WorldCup26

echo "==> Rendering app icon..."
if [ ! -f .build/AppIcon.icns ]; then
    swift scripts/make_icon.swift .build/AppIcon.iconset
    iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
fi

echo "==> Assembling WorldCup26.app..."
APP=WorldCup26.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/WorldCup26 "$APP/Contents/MacOS/WorldCup26"
cp Info.plist "$APP/Contents/Info.plist"
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp dog.jpg "$APP/Contents/Resources/dog.jpg"

echo "==> Code signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "==> Zipping for sharing..."
ditto -c -k --keepParent "$APP" WorldCup26.zip

echo ""
echo "Done! Launch with:  open $APP"
echo "Share WorldCup26.zip with other Macs (Apple Silicon or Intel, macOS 13+)."
