#!/usr/bin/env python3
"""Check actual Release bundle contents against Putia's product rules, not just source files.

Putia ships in English and Italian and sends only the wardrobe the person builds (photos and
records) to its own studio server, for app functionality. These checks catch regressions in the
built product: transport exceptions, tracking or undeclared data collection, missing
localizations, missing icon or export-compliance metadata.
"""
from pathlib import Path
import plistlib
import sys

REQUIRED_LOCALIZATIONS = ("en", "it")
# What the app sends to the studio server (docs/product-spec.md §7). Never linked to an identity,
# never used for tracking, only for app functionality.
DECLARED_DATA = {
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypeOtherUserContent",
}


def verify(path):
    bundle = Path(path)
    info = plistlib.loads((bundle/'Info.plist').read_bytes())
    if 'NSAppTransportSecurity' in info:
        raise ValueError('The app talks only to its own HTTPS server; no App Transport Security exceptions')
    if info.get('UIDeviceFamily') != [1]:
        raise ValueError(f"Putia targets iPhone only; actual UIDeviceFamily={info.get('UIDeviceFamily')!r}")
    icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
    if icon.get('CFBundleIconName') != 'AppIcon' or not (bundle/'Assets.car').is_file():
        raise ValueError('Compiled AppIcon is missing from the actual application bundle')
    if info.get('ITSAppUsesNonExemptEncryption') is not False:
        raise ValueError('Set ITSAppUsesNonExemptEncryption to NO; Putia uses only standard HTTPS')
    privacy = plistlib.loads((bundle/'PrivacyInfo.xcprivacy').read_bytes())
    if privacy.get('NSPrivacyTracking') is not False or privacy.get('NSPrivacyTrackingDomains', []) != []:
        raise ValueError('Privacy manifest must declare no tracking and no tracking domains')
    collected = privacy.get('NSPrivacyCollectedDataTypes', [])
    if {entry.get('NSPrivacyCollectedDataType') for entry in collected} != DECLARED_DATA or len(collected) != len(DECLARED_DATA):
        raise ValueError('Privacy manifest must declare exactly the photos and user content sent to the studio server')
    for entry in collected:
        if (entry.get('NSPrivacyCollectedDataTypeLinked') is not False or entry.get('NSPrivacyCollectedDataTypeTracking') is not False
                or entry.get('NSPrivacyCollectedDataTypePurposes') != ['NSPrivacyCollectedDataTypePurposeAppFunctionality']):
            raise ValueError('Declared data must be unlinked, not for tracking, and only for app functionality')
    missing = [lang for lang in REQUIRED_LOCALIZATIONS if not (bundle/f'{lang}.lproj').is_dir()]
    if missing:
        raise ValueError(f"Compiled localizations are missing: {', '.join(missing)}")
    if not info.get('CFBundleShortVersionString') or not info.get('CFBundleVersion'):
        raise ValueError('Version/build metadata is missing')
    return True


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: verify-ios-bundle.py PATH/Putia.app')
    verify(sys.argv[1])
    print('Release bundle has compiled icon, en/it localizations, iPhone metadata, no transport exceptions, '
          'no tracking, exactly the declared data, and export-compliance metadata')
