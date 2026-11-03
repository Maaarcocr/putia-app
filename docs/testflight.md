# TestFlight from GitHub-hosted macOS

The release pipeline is manual and runs on GitHub's Mac runners, so no Mac is required. It is the same hardened pipeline as the owner's Ammutta app, with Putia's bundle rules and without a widget extension.

Nothing in this repository creates Apple credentials, sets secrets or uploads a build on its own.

## What runs where

| File | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | On every push and PR: offline pipeline safety tests and the string check (Linux), server tests against a local Worker, core tests on Linux, and on `macos-26` an unsigned Release build for a device, bundle rules, and unit and UI tests in English and Italian |
| `.github/workflows/testflight.yml` | **Manual dispatch from `main` only.** `archive` (the default) signs, verifies and then deletes the IPA. `upload` also sends it to App Store Connect |
| `scripts/testflight-ci.sh` | Orchestration: temporary keychain, manual signing, archive, export, verification, optional upload and guaranteed cleanup |
| `scripts/testflight-signing.py` | Offline validation of the profile, identity and export options, plus cleanup. Never prints secret material |
| `scripts/validate-archive-config.py` | Team ID, bundle ID and build-number checks before any secret is touched |
| `scripts/archive-diagnostics.py` | On a failure, prints fixed diagnostic codes and Apple's ITMS codes, never log text |
| `ios/Config/Putia.xcconfig` | App-target signing variables. The workflow writes `Signing.local.xcconfig` next to it before archiving and always deletes it, so signing applies to the app target only and never to the Swift package targets |
| `scripts/verify-ios-bundle.py` | Checks the *built* app: no ATS exceptions, no tracking, exactly the declared data (photos and user content, unlinked, for app functionality), `en` and `it` localizations, compiled icon, iPhone only, export-compliance flag |
| `scripts/check-testflight-tools.sh` | Confirms the pinned Xcode still has the CLI options the pipeline needs |
| `scripts/test-ios.sh` | Simulator unit and UI tests, once per shipped language (Italian in dark mode) |
| `scripts/test_testflight_ci.py` | Offline tests of all of the above with fake Apple tools and made-up credentials |

## 1. Apple setup (done)

- **App ID** `com.rudilosso.putia` on team `2R27Z5A8V6`, with one capability: **Sign in with Apple** (`ios/App/Putia.entitlements`). No push, iCloud or HealthKit.
- **App Store distribution profile** "Putia App Store" for that App ID, signed with the team's Apple Distribution certificate (expires October 2027). It must be made again after a capability changes, and `APPLE_APP_STORE_PROFILE_BASE64` updated with it: an archive whose profile lacks Sign in with Apple fails with `ARCHIVE_PROVISIONING_MISMATCH`.
- **Sign in with Apple key** (Certificates, IDs & Profiles → Keys), enabled for Sign in with Apple with `com.rudilosso.putia` as its primary App ID. The server uses it (docs/architecture.md, "Deploying"); its `.p8` is never committed.
- **App Store Connect app** "Putia" (Apple ID 6829458173, SKU `putia`), primary language English, with an Italian localization.
- Reused from the team: the Apple Distribution certificate (`.p12`) and the App Store Connect team API key (`.p8`).

Before an external TestFlight group or the App Store, the app needs a privacy policy URL and the App Privacy answers below.

## 2. Repository configuration

**Settings → Secrets and variables → Actions.** Upload secrets from files with `gh secret set NAME < file`; never paste them into issues or chat.

Secrets:

| Name | Value | Needed for |
| --- | --- | --- |
| `APPLE_DISTRIBUTION_P12_BASE64` | Base64 of the distribution `.p12` | archive, upload |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | Its export password | archive, upload |
| `APPLE_APP_STORE_PROFILE_BASE64` | Base64 of Putia's `.mobileprovision` | archive, upload |
| `ASC_PRIVATE_KEY_BASE64` | Base64 of the team API key `.p8` | upload |
| `ASC_KEY_ID` | API key ID | upload |
| `ASC_ISSUER_ID` | Issuer UUID | upload |

Variables (not secret):

| Name | Value |
| --- | --- |
| `PUTIA_TEAM_ID` | `2R27Z5A8V6` |
| `PUTIA_BUNDLE_ID` | `com.rudilosso.putia`. The placeholder `dev.putia.*` is rejected |
| `TESTFLIGHT_SIGNING_ENABLED` | `true` once the above is in place |
| `TESTFLIGHT_REQUIRE_ENVIRONMENT_APPROVAL` | Optional. `true` only after creating a `testflight` environment with required reviewers |

This repository is **public**. Anyone with write access can change workflows and so reach repository secrets: keep write access to trusted people and protect `main`. Pull requests from forks never receive secrets, and the signing workflow only runs by manual dispatch from `main`.

## 3. Run it

1. Make sure `main` is green in **Verify**.
2. **Actions → Manual TestFlight → Run workflow** on `main`:
   - **archive** with a new build number (1–9999) for a dry run;
   - when that passes, **upload** with a fresh build number.
3. In App Store Connect, wait for processing, then:
   - the build declares no non-exempt encryption, so no export-compliance question should come up;
   - App Privacy: **User ID** (from Sign in with Apple), **Photos** and **Other User Content**, collected for **App Functionality**, **linked** to the user, **not used for tracking**;
   - the internal TestFlight group "Me" has automatic distribution: each processed build reaches its testers by itself.

## Verification boundary

The offline tests prove the orchestration, input checks, redaction and cleanup with fakes. They do **not** prove that the certificate, profile or API key work, nor anything about Apple's processing or devices. Only an `archive` run, then an `upload` run and installs on real iPhones, show that.
