#!/usr/bin/env bash
# Run native unit and UI tests on an iPhone simulator, once per shipped language.
# Unit tests and UI tests (-ui-testing) use an in-memory server, so nothing touches the network.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS tests require macOS, Xcode, and an installed iPhone simulator runtime." >&2
  exit 1
fi
for tool in xcodegen xcodebuild xcrun python3; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
[[ -f ios/project.yml ]] || { echo "No iOS app project exists yet (ios/project.yml)." >&2; exit 1; }
if [[ -z "${SIMULATOR_UDID:-}" ]]; then
  SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
  export SDK_VERSION
  SIMULATOR_UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, os, re, sys
def version(value):
    return tuple(int(part) for part in re.findall(r"\d+", value))
sdk = version(os.environ["SDK_VERSION"])
catalog = json.load(sys.stdin)["devices"]
choices = [(runtime, device) for runtime, devices in catalog.items()
           if "iOS" in runtime and version(runtime.split("iOS-")[-1]) <= sdk
           for device in devices if device.get("isAvailable") and "iPhone" in device["name"]]
if not choices:
    raise SystemExit("No available iPhone simulator; install an iOS runtime in Xcode Settings")
# A booted device avoids unnecessary cold boots; otherwise choose a recent runtime.
choices.sort(key=lambda pair: (
    version(pair[0].split("iOS-")[-1]),
    pair[1].get("state") == "Booted",
    "SE" not in pair[1]["name"],
    version(pair[1]["name"]),
    "Pro" in pair[1]["name"]
), reverse=True)
print(choices[0][1]["udid"])
')"
fi
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
(cd ios && xcodegen generate)
mkdir -p ios/build
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
# Every shipped language must pass the full suite; UI tests catch untranslated or truncated strings.
# Italian runs in dark mode, so the screenshots show both appearances.
for run in en:US:light it:IT:dark; do
  IFS=: read -r LANGUAGE REGION APPEARANCE <<<"$run"
  xcrun simctl ui "$SIMULATOR_UDID" appearance "$APPEARANCE"
  RESULT="$ROOT/ios/build/TestResults-$LANGUAGE-$STAMP.xcresult"
  xcodebuild test \
    -project ios/Putia.xcodeproj \
    -scheme Putia \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -derivedDataPath "$ROOT/ios/DerivedData" \
    -resultBundlePath "$RESULT" \
    -testLanguage "$LANGUAGE" \
    -testRegion "$REGION" \
    CODE_SIGNING_ALLOWED=NO
  printf '\nNative tests passed for %s_%s; Xcode result: %s\n' "$LANGUAGE" "$REGION" "$RESULT"
done
