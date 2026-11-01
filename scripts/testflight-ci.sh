#!/usr/bin/env bash
# GitHub-hosted macOS only. Manual owner-supplied signing; never provisions or creates credentials.
set +x
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/scripts/testflight-signing.py"
# App-target-only signing settings, included by ios/Config/Putia.xcconfig. Holds no secrets
# (team, bundle ID, profile UUID, certificate fingerprint, keychain path) and is always removed.
SIGNING_XCCONFIG="$ROOT/ios/Config/Signing.local.xcconfig"
remove_signing_xcconfig() {
  python3 -c 'import os, sys; os.path.isfile(sys.argv[1]) and os.remove(sys.argv[1])' "$SIGNING_XCCONFIG"
}

# An always() workflow step is the second cleanup line of defense after the EXIT/signal traps.
if [[ "${1:-}" == cleanup ]]; then
  remove_signing_xcconfig
  [[ -z "${PUTIA_TESTFLIGHT_STATE:-}" ]] || python3 "$HELPER" cleanup "$PUTIA_TESTFLIGHT_STATE"
  exit 0
fi
fail() { printf '%s\n' "$1" >&2; exit 1; }
[[ $# == 2 ]] || fail 'Usage: testflight-ci.sh archive|upload BUILD_NUMBER'
ACTION="$1"
BUILD_NUMBER="$2"
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_EVENT_NAME:-}" == workflow_dispatch && "${GITHUB_REF:-}" == refs/heads/main ]] ||
  fail 'Signing is only allowed in a manual GitHub Actions run with main selected.'
[[ "${TESTFLIGHT_SIGNING_ENABLED:-}" == true ]] || fail 'Owner must explicitly enable TESTFLIGHT_SIGNING_ENABLED.'
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ && -d "${RUNNER_TEMP:-}" ]] ||
  fail 'Missing GitHub-hosted runner temporary-directory metadata.'
[[ "$(uname -s)" == Darwin ]] || fail 'Signing requires the macOS runner.'
cd "$ROOT"
[[ -f ios/project.yml ]] || fail 'No iOS app project exists yet (ios/project.yml); there is nothing to sign.'
[[ "$(git rev-parse HEAD)" == "${GITHUB_SHA:-}" ]] || fail 'Checkout must match the exact manually selected commit.'
for tool in python3 xcodegen xcodebuild xcrun security codesign openssl ditto grep; do
  command -v "$tool" >/dev/null || fail "Missing required tool: $tool"
done
python3 "$HELPER" preflight "$ACTION" "$BUILD_NUMBER"
[[ "$(xcodebuild -version | head -n 1)" == 'Xcode 26.6' ]] || fail 'This workflow requires the pinned Xcode 26.6.'
[[ "$(xcrun --sdk iphoneos --show-sdk-version)" == 26.* ]] || fail 'This workflow requires an iOS 26 SDK.'

WORK="$(mktemp -d "$RUNNER_TEMP/putia-testflight.$GITHUB_RUN_ID.$GITHUB_RUN_ATTEMPT.XXXXXX")"
STAGE='initializing temporary signing storage'
finish() {
  result=$?
  trap - EXIT INT TERM
  if ! remove_signing_xcconfig; then
    [[ "$result" != 0 ]] || result=1
  fi
  if ! python3 "$HELPER" cleanup "$WORK"; then
    [[ "$result" != 0 ]] || result=1
  fi
  if [[ "$result" != 0 ]]; then
    printf 'Manual signing failed while %s (exit %s). Private tool output is not printed; cleanup was attempted.\n' "$STAGE" "$result" >&2
  fi
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$HELPER" init-state "$WORK"
printf 'PUTIA_TESTFLIGHT_STATE=%s\n' "$WORK" >> "$GITHUB_ENV"
LOG="$WORK/private-tools.log"
quiet() { "$@" >> "$LOG" 2>&1; }
KEYCHAIN="$WORK/signing.keychain-db"
ARCHIVE="$WORK/Putia.xcarchive"
EXPORT="$WORK/export"
P12_PASSWORD="$APPLE_DISTRIBUTION_P12_PASSWORD"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"

STAGE='decoding owner-supplied signing files'
python3 "$HELPER" decode APPLE_DISTRIBUTION_P12_BASE64 "$WORK/distribution.p12"
python3 "$HELPER" decode APPLE_APP_STORE_PROFILE_BASE64 "$WORK/profile.mobileprovision"
unset APPLE_DISTRIBUTION_P12_BASE64 APPLE_DISTRIBUTION_P12_PASSWORD APPLE_APP_STORE_PROFILE_BASE64
if [[ "$ACTION" == upload ]]; then
  mkdir "$WORK/private_keys"
  python3 "$HELPER" decode ASC_PRIVATE_KEY_BASE64 "$WORK/private_keys/AuthKey_$ASC_KEY_ID.p8"
  quiet openssl pkey -in "$WORK/private_keys/AuthKey_$ASC_KEY_ID.p8" -noout -check
fi
unset ASC_PRIVATE_KEY_BASE64

STAGE='validating the App Store provisioning profile'
security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist" 2>> "$LOG"
PROFILE_UUID="$(python3 "$HELPER" profile "$WORK/profile.plist")"

STAGE='preserving the original keychain search list'
security list-keychains -d user > "$WORK/keychains.txt" 2>> "$LOG"
python3 "$HELPER" save-keychains "$WORK" "$WORK/keychains.txt" > "$WORK/keychain-paths.txt"
ORIGINAL_KEYCHAINS=()
while IFS= read -r path; do ORIGINAL_KEYCHAINS+=("$path"); done < "$WORK/keychain-paths.txt"

STAGE='importing and validating the temporary distribution identity'
quiet security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
quiet security set-keychain-settings -lut 3600 "$KEYCHAIN"
quiet security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
quiet security import "$WORK/distribution.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -t cert -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security
unset P12_PASSWORD
quiet security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
unset KEYCHAIN_PASSWORD
security find-identity -v -p codesigning "$KEYCHAIN" > "$WORK/identities.txt" 2>> "$LOG"
IDENTITY="$(python3 "$HELPER" identity "$WORK/profile.plist" "$WORK/identities.txt")"
quiet security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
python3 "$HELPER" install-profile "$WORK" "$PROFILE_UUID" profile.mobileprovision

STAGE='preparing app-target-only signing settings'
mkdir -p "$(dirname "$SIGNING_XCCONFIG")"
printf '%s\n' \
  'PUTIA_CODE_SIGN_STYLE = Manual' \
  "PUTIA_DEVELOPMENT_TEAM = $PUTIA_TEAM_ID" \
  "PUTIA_APP_BUNDLE_ID = $PUTIA_BUNDLE_ID" \
  "PUTIA_PROVISIONING_PROFILE = $PROFILE_UUID" \
  "PUTIA_CODE_SIGN_IDENTITY = $IDENTITY" \
  "PUTIA_OTHER_CODE_SIGN_FLAGS = --keychain $KEYCHAIN" \
  "CURRENT_PROJECT_VERSION = $BUILD_NUMBER" > "$SIGNING_XCCONFIG"

STAGE='archiving the manually signed Release app'
(cd "$ROOT/ios" && quiet xcodegen generate)
# Do not pass signing settings globally: Swift package targets cannot use the app's
# provisioning profile. The app target reads them from the file written above.
if xcodebuild archive \
  -project "$ROOT/ios/Putia.xcodeproj" -scheme Putia -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$WORK/DerivedData" \
  > "$WORK/private-archive.log" 2>&1; then
  :
else
  status=$?
  # Prints fixed diagnostic codes only, never log text.
  python3 "$ROOT/scripts/archive-diagnostics.py" "$WORK/private-archive.log" || true
  exit "$status"
fi

verify_app() {
  local app="$1" label="$2"
  # Only these hand-written substeps reach the job log; Apple tool output stays private.
  STAGE="verifying $label: Release bundle contents"
  quiet python3 "$ROOT/scripts/verify-ios-bundle.py" "$app"
  verify_signed_bundle "$app" "$label" "$PROFILE_UUID" "$PUTIA_BUNDLE_ID"
}

# Signature, entitlements, certificate and embedded profile of the app bundle.
verify_signed_bundle() {
  local app="$1" label="$2" expected_profile="$3" bundle_id="$4" actual_profile_uuid
  STAGE="verifying $label: strict code signature"
  quiet codesign --verify --deep --strict "$app"
  STAGE="verifying $label: extracting XML entitlements"
  # Current codesign defaults to a DER representation; request a plist explicitly.
  codesign --display --entitlements - --xml "$app" > "$WORK/$label-entitlements.plist" 2>> "$LOG"
  STAGE="verifying $label: reading signature metadata"
  codesign --display --verbose=4 "$app" > "$WORK/$label-signature.txt" 2>&1
  STAGE="verifying $label: extracting the signing certificate"
  # This optional argument must share its token with the flag; a separate token is read as a code path.
  quiet codesign --display "--extract-certificates=$WORK/$label-cert" "$app"
  STAGE="verifying $label: decoding the embedded provisioning profile"
  security cms -D -i "$app/embedded.mobileprovision" > "$WORK/$label-profile.plist" 2>> "$LOG"
  STAGE="verifying $label: validating the embedded provisioning profile"
  actual_profile_uuid="$(PUTIA_BUNDLE_ID="$bundle_id" python3 "$HELPER" profile "$WORK/$label-profile.plist")"
  [[ "$actual_profile_uuid" == "$expected_profile" ]] || fail 'Actual embedded profile differs.'
  STAGE="verifying $label: matching signed metadata, entitlements and certificate"
  PUTIA_BUNDLE_ID="$bundle_id" python3 "$HELPER" verify-app "$app" "$WORK/$label-profile.plist" \
    "$WORK/$label-entitlements.plist" "$WORK/$label-signature.txt" "$BUILD_NUMBER" "$IDENTITY" "$WORK/${label}-cert0"
  printf 'Signed %s bundle verification passed.\n' "$label"
}
STAGE='verifying the signed archive bundle'
verify_app "$ARCHIVE/Products/Applications/Putia.app" archive

STAGE='exporting a manually signed App Store Connect IPA'
python3 "$HELPER" export-options "$WORK/profile.plist" "$IDENTITY" "$WORK/ExportOptions.plist"
quiet xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$WORK/ExportOptions.plist"
shopt -s nullglob
IPAS=("$EXPORT"/*.ipa)
[[ ${#IPAS[@]} == 1 ]] || fail 'Expected exactly one exported IPA.'
STAGE='verifying the exported IPA bundle'
quiet ditto -x -k "${IPAS[0]}" "$WORK/unpacked"
APPS=("$WORK/unpacked/Payload/"*.app)
[[ ${#APPS[@]} == 1 ]] || fail 'Expected exactly one application in the exported IPA.'
verify_app "${APPS[0]}" export

if [[ "$ACTION" == upload ]]; then
  STAGE='checking the installed App Store upload CLI'
  # Apple documents altool for App Store uploads. Check this pinned Xcode's actual CLI
  # before using its legacy-compatible API-key syntax; never enable provisioning updates.
  xcrun altool --help > "$WORK/altool-help.txt" 2>&1
  grep -q -- '--upload-app' "$WORK/altool-help.txt" || fail 'Pinned altool has no documented upload-app command; review its current CLI.'
  # New altool versions use kebab-case; older Xcode builds document camel-case.
  # Select only a spelling advertised by the actual installed tool.
  if grep -q -- '--api-key' "$WORK/altool-help.txt" && grep -q -- '--api-issuer' "$WORK/altool-help.txt"; then
    AUTH_FLAGS=(--api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID")
  elif grep -q -- '--apiKey' "$WORK/altool-help.txt" && grep -q -- '--apiIssuer' "$WORK/altool-help.txt"; then
    AUTH_FLAGS=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
  else
    fail 'Pinned altool has no documented API-key flags; review its current CLI.'
  fi
  if grep -q -- '--platform' "$WORK/altool-help.txt"; then
    PLATFORM_FLAG=--platform
  else
    # -t is Apple's documented App Store upload platform option.
    PLATFORM_FLAG=-t
  fi
  STAGE='uploading the explicitly requested IPA to App Store Connect'
  # The private_keys directory is a documented altool lookup location relative to cwd.
  if (cd "$WORK" && xcrun altool --upload-app -f "${IPAS[0]}" "$PLATFORM_FLAG" ios \
    "${AUTH_FLAGS[@]}" --output-format json > "$WORK/private-upload.log" 2>&1); then
    :
  else
    status=$?
    # Prints Apple's ITMS error codes and fixed diagnostic codes only, never log text.
    python3 "$ROOT/scripts/archive-diagnostics.py" --upload "$WORK/private-upload.log" || true
    exit "$status"
  fi
  printf 'IPA upload command succeeded. Apple processing, TestFlight access, and iPhone acceptance testing remain separate.\n'
else
  printf 'Signed archive and exported IPA verified. Archive mode performed no upload; temporary products will now be deleted.\n'
fi
