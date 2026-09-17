"""Check committed string catalogs without modifying them or requiring Xcode."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "KeepUp/Resources/Localizable.xcstrings").read_text())["strings"]
errors = []
for key, entry in catalog.items():
    if entry.get("shouldTranslate") is False:
        continue
    for language in ("en", "zh-Hans"):
        unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
        if not unit.get("value") or unit.get("state") != "translated":
            errors.append(f"{key}: missing {language} translation")

for path in (root / "KeepUp").rglob("*.swift"):
    source = re.sub(r'\.accessibilityIdentifier\("[^"\n]*"\)', "", path.read_text())
    for key in re.findall(r'"((?:app|nav|calendar|entry|history|profile|settings|stats|action|error|language|card|unit)\.[A-Za-z][A-Za-z0-9.]*)"', source):
        if key not in catalog:
            errors.append(f"{path.relative_to(root)}: missing key {key}")

if errors:
    raise SystemExit("\n".join(errors))
print(f"Validated {len(catalog)} catalog entries for English and Simplified Chinese.")
