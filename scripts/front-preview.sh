#!/bin/bash
# Watch the LIVE front view on the Mac: builds for the iPhone 17 simulator, launches the
# Front role on a pretend ride around the Pan Am Sports Centre, and screenshots it.
#   scripts/front-preview.sh [seconds_between=3] [count=5] [out_dir]
# Only one simulator is ever booted: several at once make this Mac unusable.
set -euo pipefail
GAP=${1:-3}; COUNT=${2:-5}
OUT=${3:-${TMPDIR:-/tmp}/4sight-preview}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DD="${TMPDIR:-/tmp}/4sight-preview-dd"
BUNDLE=com.zupersun.foursight
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for rt in json.load(sys.stdin)["devices"].values() for d in rt if d["name"] == "iPhone 17"]
print(devs[0]["udid"] if devs else "")')
[ -n "$UDID" ] || { echo "No 'iPhone 17' simulator installed."; exit 1; }

for other in $(xcrun simctl list devices booted -j | python3 -c '
import json, sys
print(" ".join(d["udid"] for rt in json.load(sys.stdin)["devices"].values() for d in rt))'); do
  [ "$other" = "$UDID" ] || { echo "Shutting down $other"; xcrun simctl shutdown "$other"; }
done
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || true   # Xcode 27 renamed the app DeviceHub

echo "Building..."
xcodebuild -project "$ROOT/4sight/4sight.xcodeproj" -scheme 4sight \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" -quiet build
APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "*.app" | head -1)

xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" 2>/dev/null || true
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" -role front -previewRide YES >/dev/null
sleep 4
for i in $(seq 1 "$COUNT"); do
  xcrun simctl io "$UDID" screenshot "$OUT/front-$i.png" >/dev/null 2>&1
  echo "$OUT/front-$i.png"
  [ "$i" -lt "$COUNT" ] && sleep "$GAP"
done
echo "Simulator $UDID left running. Stop it with: xcrun simctl shutdown $UDID"
