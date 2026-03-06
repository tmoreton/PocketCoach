#!/bin/bash
#
# Record App Store Preview Video using iOS Simulator
# Usage: ./scripts/record_preview.sh [device_name]
#
# Default device: iPhone 15 Pro Max
# Output: fastlane/screenshots/app_preview.mp4

set -euo pipefail

DEVICE_NAME="${1:-iPhone 15 Pro Max}"
OUTPUT_DIR="./fastlane/screenshots"
OUTPUT_FILE="$OUTPUT_DIR/app_preview.mp4"
RECORD_DURATION=30
SCHEME="PocketCoach"
BUNDLE_ID="com.reactnativenerd.PocketCoach"

mkdir -p "$OUTPUT_DIR"

echo "==> Finding or creating simulator: $DEVICE_NAME"
DEVICE_UDID=$(xcrun simctl list devices available | grep "$DEVICE_NAME" | head -1 | grep -oE '[0-9A-F-]{36}')

if [ -z "$DEVICE_UDID" ]; then
    echo "Error: No available simulator found for '$DEVICE_NAME'"
    echo "Available devices:"
    xcrun simctl list devices available
    exit 1
fi

echo "==> Using device: $DEVICE_UDID"

# Boot simulator if not already booted
BOOT_STATE=$(xcrun simctl list devices | grep "$DEVICE_UDID" | grep -o "(Booted)" || true)
if [ -z "$BOOT_STATE" ]; then
    echo "==> Booting simulator..."
    xcrun simctl boot "$DEVICE_UDID"
    sleep 5
fi

# Open Simulator app
open -a Simulator

# Wait for simulator to be fully ready
sleep 3

# Override status bar for clean screenshots
echo "==> Setting clean status bar..."
xcrun simctl status_bar "$DEVICE_UDID" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4 \
    --cellularMode active

# Build and install the app with VIDEO_MODE
echo "==> Building app..."
xcodebuild build-for-testing \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$DEVICE_UDID" \
    -quiet \
    2>/dev/null || true

# Install and launch with video mode arguments
echo "==> Launching app in VIDEO_MODE..."
xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" 2>/dev/null || true
sleep 1

# Launch with video mode arguments
xcrun simctl launch "$DEVICE_UDID" "$BUNDLE_ID" -SCREENSHOT_MODE -VIDEO_MODE

sleep 2

# Start recording
echo "==> Recording ${RECORD_DURATION}s preview video..."
xcrun simctl io "$DEVICE_UDID" recordVideo --codec h264 --force "$OUTPUT_FILE" &
RECORD_PID=$!

# Wait for the recording duration
sleep "$RECORD_DURATION"

# Stop recording
kill -INT "$RECORD_PID" 2>/dev/null || true
wait "$RECORD_PID" 2>/dev/null || true

# Clear status bar override
echo "==> Cleaning up status bar..."
xcrun simctl status_bar "$DEVICE_UDID" clear

echo ""
echo "==> Preview video saved to: $OUTPUT_FILE"
echo "==> Duration: ${RECORD_DURATION}s"
echo ""
echo "Next steps:"
echo "  1. Review the video at: $OUTPUT_FILE"
echo "  2. Trim to exactly 15-30 seconds if needed"
echo "  3. Upload via App Store Connect or 'fastlane deliver'"
