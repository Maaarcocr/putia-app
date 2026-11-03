#!/usr/bin/env python3
"""Check actual Release bundle contents against Putia's product rules, not just source files.

Putia ships in English and Italian, on iPhone, and talks only to its own HTTPS server. These
checks catch regressions in the built product: transport exceptions, missing localizations,
missing icon or export-compliance metadata.
"""
from pathlib import Path
import plistlib
import sys

REQUIRED_LOCALIZATIONS = ("en", "it")


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
    print('Release bundle has compiled icon, en/it localizations, iPhone metadata, no transport exceptions '
          'and export-compliance metadata')
