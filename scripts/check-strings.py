#!/usr/bin/env python3
"""Fail when the app's String Catalogs and code drift apart.

- Every key used in ios/App/Sources/Support/L10n.swift exists in Localizable.xcstrings,
  translated into every shipped language, and no catalog key is unused.
- Every permission purpose string in Info.plist is translated in each InfoPlist.strings.
- Views never pass raw string literals to SwiftUI text APIs; they go through L10n.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'ios' / 'App'
LANGUAGES = ('en', 'it')
FORMAT_SPECIFIER = re.compile(r'%(?:\d+\$)?(?:lld|ld|d|@|lf|f)')
RAW_TEXT_API = re.compile(
    r'\b(Text|Button|Label|Section|Toggle|Picker|Stepper|TextField|LabeledContent|'
    r'ContentUnavailableView|Tab|navigationTitle|confirmationDialog|alert|accessibilityLabel)\(\s*"'
)


def normalize(key):
    return FORMAT_SPECIFIER.sub('%', re.sub(r'\\\([^)]*\)', '%', key))


def units(entry):
    """All string units of one localization, including plural variations."""
    if 'stringUnit' in entry:
        yield entry['stringUnit']
    for variation in entry.get('variations', {}).values():
        for case in variation.values():
            yield from units(case)


def check_catalog(path, required, errors, allow_unused=False):
    catalog = json.loads(path.read_text(encoding='utf-8'))
    strings = catalog['strings']
    by_normalized = {normalize(key): key for key in strings}
    for key in sorted(required):
        actual = by_normalized.get(normalize(key))
        if actual is None:
            errors.append(f'{path.name}: missing key "{key}"')
            continue
        localizations = strings[actual].get('localizations', {})
        for language in LANGUAGES:
            found = list(units(localizations.get(language, {})))
            if not found or any(unit.get('state') != 'translated' or not unit.get('value') for unit in found):
                errors.append(f'{path.name}: "{actual}" is not translated into {language}')
    if not allow_unused:
        used = {normalize(key) for key in required}
        for key in sorted(strings):
            if normalize(key) not in used:
                errors.append(f'{path.name}: unused key "{key}"')


def main():
    if not (APP / 'Sources').is_dir():
        print('No app sources yet; nothing to check')
        return 0
    errors = []

    l10n = (APP / 'Sources' / 'Support' / 'L10n.swift').read_text(encoding='utf-8')
    code_keys = set(re.findall(r'"((?:[^"\\]|\\.)*)"', l10n))
    check_catalog(APP / 'Resources' / 'Localizable.xcstrings', code_keys, errors)


    info = (APP / 'Info.plist').read_text(encoding='utf-8')
    for key in re.findall(r'<key>(NS\w+UsageDescription)</key>', info):
        for language in LANGUAGES:
            strings = APP / 'Resources' / f'{language}.lproj' / 'InfoPlist.strings'
            if f'"{key}" = "' not in strings.read_text(encoding='utf-8'):
                errors.append(f'{strings.relative_to(ROOT)}: missing permission string {key}')

    for source in sorted((APP / 'Sources').rglob('*.swift')):
        if source.name == 'L10n.swift':
            continue
        for number, line in enumerate(source.read_text(encoding='utf-8').splitlines(), 1):
            if RAW_TEXT_API.search(line):
                errors.append(f'{source.relative_to(ROOT)}:{number}: raw string literal in UI text; add it to L10n')

    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'String catalogs OK: {len(code_keys)} UI keys in {", ".join(LANGUAGES)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
