#!/bin/bash
# The front view driven by REAL rear-camera footage: builds for the iPhone 17 simulator,
# copies a rear clip (and its .camera.json, if beside it) into the app's Documents, and
# launches the Front role on the pretend ride with the rear pipeline running on the clip.
#   scripts/rear-replay.sh <clip.mp4> [seconds_between=6] [count=10] [out_dir]
# Footage stays out of the repo (it is public). Only one simulator is ever booted.
# SIM_WAIT_FLAG=<file>: wait for that file before touching the simulator.
set -euo pipefail
CLIP=${1:?usage: scripts/rear-replay.sh <clip.mp4> [gap] [count] [out_dir]}
GAP=${2:-6}; COUNT=${3:-10}
OUT=${4:-${TMPDIR:-/tmp}/4sight-replay}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DD="${TMPDIR:-/tmp}/4sight-replay-dd"
BUNDLE=com.zupersun.foursight
NAME=$(basename "$CLIP")
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for rt in json.load(sys.stdin)["devices"].values() for d in rt if d["name"] == "iPhone 17"]
print(devs[0]["udid"] if devs else "")')
[ -n "$UDID" ] || { echo "No 'iPhone 17' simulator installed."; exit 1; }

echo "Building..."
xcodebuild -project "$ROOT/4sight/4sight.xcodeproj" -scheme 4sight \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" -quiet build
APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "*.app" | head -1)

if [ -n "${SIM_WAIT_FLAG:-}" ]; then
  until [ -f "$SIM_WAIT_FLAG" ]; do echo "Waiting for $SIM_WAIT_FLAG"; sleep 30; done
fi
for other in $(xcrun simctl list devices booted -j | python3 -c '
import json, sys
print(" ".join(d["udid"] for rt in json.load(sys.stdin)["devices"].values() for d in rt))'); do
  [ "$other" = "$UDID" ] || { echo "Shutting down $other"; xcrun simctl shutdown "$other"; }
done
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || true   # Xcode 27 renamed the app DeviceHub

xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" 2>/dev/null || true
DOCS="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents"
mkdir -p "$DOCS"
cp "$CLIP" "$DOCS/$NAME"
SIDE="${CLIP%.*}.camera.json"
[ -f "$SIDE" ] && cp "$SIDE" "$DOCS/"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" -role front -previewRide YES -replayRear "$NAME" >/dev/null
sleep 8
for i in $(seq 1 "$COUNT"); do
  xcrun simctl io "$UDID" screenshot "$OUT/replay-$i.png" >/dev/null 2>&1
  echo "$OUT/replay-$i.png"
  [ "$i" -lt "$COUNT" ] && sleep "$GAP"
done
echo "Simulator $UDID left running. Stop it with: xcrun simctl shutdown $UDID"
