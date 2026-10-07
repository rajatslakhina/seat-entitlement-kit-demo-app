#!/usr/bin/env bash
# Builds Demo.xcodeproj for an iOS Simulator, installs and launches the app in
# four scripted states, checks it is still running after each launch, and saves
# real screenshots to Demo/Screenshots/. Runs on the GitHub-hosted macOS runner.
set -euo pipefail

RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
BUNDLE_ID="com.rajatlakhina.SeatEntitlementsDemo"
OUT="Demo/Screenshots"
mkdir -p "$OUT"

# Pick an iPhone simulator whose runtime matches the iOS Simulator SDK of the
# selected Xcode (runner images carry several runtimes; a newer one than the
# SDK cannot be a build destination). Never a hard-coded device name.
SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
echo "iOS Simulator SDK $SDK_VERSION"
UDID=$(xcrun simctl list devices available -j | SDK_VERSION="$SDK_VERSION" python3 -c '
import json, os, sys
sdk = os.environ["SDK_VERSION"]
major_minor = "-".join(sdk.split(".")[:2])
devices = json.load(sys.stdin)["devices"]
def pick(match):
    for runtime, items in sorted(devices.items(), reverse=True):
        if "iOS" not in runtime or not match(runtime):
            continue
        for d in items:
            if d["name"].startswith("iPhone") and "Max" not in d["name"]:
                print(d["udid"]); sys.exit(0)
pick(lambda r: r.endswith("iOS-" + major_minor))
pick(lambda r: r.split("iOS-")[-1].split("-")[0] == sdk.split(".")[0])
sys.exit(1)')
echo "Using simulator $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

xcodebuild -project Demo.xcodeproj -scheme Demo -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

APP="build/Build/Products/Debug-iphonesimulator/Demo.app"
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true

shoot () {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
  # Wait (up to 60 s) for the app process, then give the scripted scenario
  # time to run and render. Written to a file first: piping into `grep -q`
  # under pipefail can fail with SIGPIPE (exit 141).
  local up=0
  for _ in $(seq 1 60); do
    xcrun simctl spawn "$UDID" launchctl list > "$RUNNER_TEMP/processes.txt"
    if grep -q "$BUNDLE_ID" "$RUNNER_TEMP/processes.txt"; then up=1; break; fi
    sleep 1
  done
  [ "$up" = 1 ] || { echo "app never started"; exit 1; }
  sleep 6
  # Still running after the scenario played out, i.e. it did not crash.
  xcrun simctl spawn "$UDID" launchctl list > "$RUNNER_TEMP/processes.txt"
  grep -q "$BUNDLE_ID" "$RUNNER_TEMP/processes.txt"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
}

shoot 1-verified -scenario fresh
shoot 2-offline-grace -scenario offlineReassign
shoot 3-revoked-online -scenario onlineRevoke
shoot 4-rollout-herd -tab herd
ls -la "$OUT"
