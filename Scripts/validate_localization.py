"""Check committed string catalogs without modifying them or requiring Xcode."""
import json
import re
from collections import Counter
from pathlib import Path


def format_arguments(value):
    """Compare argument positions and types, allowing translators to reorder them."""
    arguments = Counter()
    next_position = 1
    for match in re.finditer(r"%%|%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|ll|h|l|L|z|t|j)?([@diuoxXfFeEgGaAcCsSp])", value):
        if match.group() == "%%":
            continue
        position = int(match[1]) if match[1] else next_position
        if not match[1]:
            next_position += 1
        arguments[(position, (match[2] or "") + match[3])] += 1
    return arguments


root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "KeepUp/Resources/Localizable.xcstrings").read_text())["strings"]
errors = []
for key, entry in catalog.items():
    if entry.get("shouldTranslate") is False:
        continue
    english = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value", "")
    expected_arguments = format_arguments(english)
    if format_arguments(key) and format_arguments(key) != expected_arguments:
        errors.append(f"{key}: English format arguments differ from the key")
    for language in ("en", "zh-Hans"):
        unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
        if not unit.get("value") or unit.get("state") != "translated":
            errors.append(f"{key}: missing {language} translation")
        elif format_arguments(unit["value"]) != expected_arguments:
            errors.append(f"{key}: {language} format arguments differ from English")

for path in (root / "KeepUp").rglob("*.swift"):
    source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', "", path.read_text())
    source = re.sub(r'\baccessibilityIdentifier\s*=.*', "", source)
    for key in re.findall(r'"((?:app|nav|calendar|entry|history|profile|settings|stats|action|error|language|card|unit)\.[A-Za-z][A-Za-z0-9.]*)"', source):
        if key not in catalog:
            errors.append(f"{path.relative_to(root)}: missing key {key}")
    # Runtime helper calls are not extracted by Xcode. Include format keys and
    # all feature namespaces, while leaving dynamically constructed keys to
    # validate_configuration.py and the feature-specific checks.
    for key in re.findall(r'\blocalized\("([^"\\]+)"\s*,', source):
        if key not in catalog:
            errors.append(f"{path.relative_to(root)}: missing key {key}")
    # Error keys travel through the controller before becoming localized Text.
    for key in re.findall(r'\berrorKey\s*=\s*"([^"\\]+)"', source):
        if key not in catalog:
            errors.append(f"{path.relative_to(root)}: missing error key {key}")
    for key in re.findall(r'\b(?:Text|Button|Label|Toggle|Picker|LocalizedStringKey)\("([^"\\]+)"', source):
        if re.fullmatch(r"[a-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)+(?: .*)?", key) and key not in catalog:
            errors.append(f"{path.relative_to(root)}: missing key {key}")

if errors:
    raise SystemExit("\n".join(errors))
print(f"Validated {len(catalog)} catalog entries for English and Simplified Chinese.")
