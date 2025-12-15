#!/bin/bash

# Build script for PortForwarder.app
set -e

APP_NAME="PortForwarder"
BUNDLE_ID="com.portforwarder.app"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building release binary..."
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📋 Copying files..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"
cp "Resources/Info.plist" "$CONTENTS_DIR/"

# Copy icon if exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

echo "🔏 Signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ App bundle created at: $APP_DIR"
echo ""
echo "To install, run:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "Or open directly:"
echo "  open $APP_DIR"
