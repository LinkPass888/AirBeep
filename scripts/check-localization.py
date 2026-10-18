#!/usr/bin/env python3
"""Validate the Localizable.strings pair and its use from Swift sources.

Checks that both files parse as `key = value;` entries, that their key sets are
identical, that no key is duplicated, that %-style format placeholders line up
between the two languages, and that every `String(localized:)` key used in the
Swift sources actually exists in both catalogs. Run from the repository root:

    python3 scripts/check-localization.py
"""

import os
import re
import sys

ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT = re.compile(r"//[^\n]*")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[@sduf]")
LOCALIZED_CALL = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')

APP_DIR = "airbeep"


def parse(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    text = LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))

    entries = {}
    duplicates = []
    for match in ENTRY.finditer(text):
        key, value = match.group(1), match.group(2)
        if key in entries:
            duplicates.append(key)
        entries[key] = value

    residual = ENTRY.sub("", text).strip()
    return entries, duplicates, residual


def swift_sources():
    """Swift files under the app directory, skipping .lproj catalogs."""
    for root, dirs, files in os.walk(APP_DIR):
        dirs[:] = [d for d in dirs if not d.endswith(".lproj")]
        for name in files:
            if name.endswith(".swift"):
                yield os.path.join(root, name)


def used_keys():
    """Map each `String(localized:)` key to the files that use it."""
    used = {}
    for path in swift_sources():
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for match in LOCALIZED_CALL.finditer(text):
            used.setdefault(match.group(1), []).append(path)
    return used


def main():
    pairs = [
        ("airbeep/en.lproj/Localizable.strings", "airbeep/zh-Hans.lproj/Localizable.strings"),
    ]
    failed = False

    for en_path, zh_path in pairs:
        print(f"== {en_path} <-> {zh_path}")
        en, en_dups, en_residual = parse(en_path)
        zh, zh_dups, zh_residual = parse(zh_path)
        print(f"   EN keys: {len(en)}  ZH keys: {len(zh)}")

        if en_residual:
            failed = True
            print(f"   !! unparsed content in EN: {en_residual[:300]!r}")
        if zh_residual:
            failed = True
            print(f"   !! unparsed content in ZH: {zh_residual[:300]!r}")
        for key in en_dups:
            failed = True
            print(f"   !! duplicate EN key: {key[:80]!r}")
        for key in zh_dups:
            failed = True
            print(f"   !! duplicate ZH key: {key[:80]!r}")

        for key in sorted(set(en) - set(zh)):
            failed = True
            print(f"   !! missing in ZH: {key[:90]!r}")
        for key in sorted(set(zh) - set(en)):
            failed = True
            print(f"   !! missing in EN: {key[:90]!r}")

        for key in sorted(set(en) & set(zh)):
            en_ph = PLACEHOLDER.findall(en[key])
            zh_ph = PLACEHOLDER.findall(zh[key])
            if en_ph != zh_ph:
                failed = True
                print(f"   !! placeholder mismatch {key[:70]!r}: en={en_ph} zh={zh_ph}")

        # Every String(localized:) key referenced from Swift must exist in both
        # catalogs, otherwise that string ships untranslated at runtime.
        used = used_keys()
        print(f"   String(localized:) keys referenced in Swift: {len(used)}")
        for key in sorted(set(used) - set(en)):
            failed = True
            print(f"   !! referenced but missing from EN: {key[:90]!r} <- {used[key]}")
        for key in sorted(set(used) - set(zh)):
            failed = True
            print(f"   !! referenced but missing from ZH: {key[:90]!r} <- {used[key]}")

        if not failed:
            print("   OK: identical keys, no duplicates, placeholders consistent, all Swift references present")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
