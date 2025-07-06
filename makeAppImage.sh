#!/bin/bash
set -e

zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu -Dbuild_sdl3 -Dno_assets=true

APP=Saturn
VERSION=1.0.0
APPDIR=AppDir
EXECUTABLE=zig-out/bin/saturn
DESKTOP_FILE=saturn.desktop
ICON_FILE=saturn.png

# Download linuxdeploy if missing
if [ ! -f linuxdeploy-x86_64.AppImage ]; then
    echo "Downloading linuxdeploy..."
    wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
    chmod +x linuxdeploy-x86_64.AppImage
fi

# Download appimagetool if missing
if [ ! -f appimagetool-x86_64.AppImage ]; then
    echo "Downloading appimagetool..."
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool-x86_64.AppImage
fi

# Clean previous build
rm -rf "$APPDIR"

# Export version for appimagetool metadata
export VERSION="$VERSION"

# Run linuxdeploy to bundle executable, icon, and desktop file
./linuxdeploy-x86_64.AppImage \
    --appdir "$APPDIR" \
    -e "$EXECUTABLE" \
    -d "$DESKTOP_FILE" \
    -i "$ICON_FILE"

# Build the AppImage
./appimagetool-x86_64.AppImage "$APPDIR"

echo "✅ $APP-x86_64.AppImage created successfully!"
