#!/usr/bin/env python3
"""Report string literals passed to SwiftUI Text/Label/Toggle and String(localized:)
that are absent from the English Localizable.strings catalog.

SwiftUI localizes a bare `Text("literal")` by using the literal as the lookup
key, so any literal shown to the user but missing from the catalog ships
untranslated. This is a heuristic report, not a gate: dynamic strings and
literals deliberately not localized will show up. Review the output rather than
trusting a pass/fail alone.

    python3 scripts/check-swift-strings.py
"""

import os
import re
import sys

ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
# First string argument of Text(...), Label(...), Toggle(...), and String(localized: ...)
LITERAL_CALL = re.compile(
    r'(?:\bText|\bLabel|\bToggle|String\(localized:)\s*\(\s*"((?:[^"\\]|\\.)*)"'
)
INTERPOLATION = re.compile(r'\\\(')
# Literals shown to the user that are proper nouns / brand names and must not be
# translated. Everything else that reaches the UI needs a catalog entry.
PROPER_NOUNS = {"AirBeep", "LocalDevVPN"}
APP_DIR = "airbeep"


def catalog_keys(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return {m.group(1) for m in ENTRY.finditer(text)}


def swift_sources():
    for root, dirs, files in os.walk(APP_DIR):
        dirs[:] = [d for d in dirs if not d.endswith(".lproj")]
        for name in files:
            if name.endswith(".swift"):
                yield os.path.join(root, name)


def main():
    en = catalog_keys("airbeep/en.lproj/Localizable.strings")
    missing = {}
    for path in swift_sources():
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for match in LITERAL_CALL.finditer(text):
            literal = match.group(1)
            if INTERPOLATION.search(literal):
                continue  # dynamic key, cannot be checked statically
            if literal in PROPER_NOUNS:
                continue
            if literal not in en:
                missing.setdefault(literal, []).append(path)

    if not missing:
        print("OK: every static Text/Label/Toggle/localized literal is in the EN catalog")
        return 0

    print(f"{len(missing)} literal(s) not found in EN catalog (review — some may be intentional):")
    for literal in sorted(missing):
        print(f"  {literal[:100]!r}")
        for path in missing[literal]:
            print(f"      <- {path}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
