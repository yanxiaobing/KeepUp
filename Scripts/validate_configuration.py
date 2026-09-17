"""Validate bundled catalog references and translations without Xcode or PunchCard."""
import json
import math
from pathlib import Path

root = Path(__file__).resolve().parent.parent
resources = root / "KeepUp/Resources"
cards = json.loads((resources / "cards.json").read_text())
energy = json.loads((resources / "activity-energy.json").read_text())
themes = json.loads((resources / "themes.json").read_text())
strings = json.loads((resources / "Localizable.xcstrings").read_text())["strings"]
assets = {path.stem for path in (resources / "Assets.xcassets").rglob("*.imageset")}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def unique(values, description):
    require(len(values) == len(set(values)), "Duplicate " + description)


def translated(key):
    for language in ("en", "zh-Hans"):
        text = strings.get(key, {}).get("localizations", {}).get(language, {}).get("stringUnit", {})
        require(text.get("state") == "translated" and text.get("value"), f"Missing {language} translation: {key}")


require(cards["version"] == energy["version"] == 1, "Unsupported configuration version")
items = cards["items"]
require(items and energy["coefficients"] and energy["foods"] and themes, "Empty configuration")
unique([item["number"] for item in items], "card number")
unique([item["card"]["id"] for item in items], "card ID")
unique([item["card"]["sortOrder"] for item in items], "card sort order")
for item in items:
    card = item["card"]
    translated(card["titleKey"])
    translated("unit." + card["unit"])
    require(item["artwork"] in assets and item["sport"] in assets, f"Missing card artwork: {card['id']}")
unique([item["id"] for item in cards["legacyStarters"]], "legacy card ID")
for starter in cards["legacyStarters"]:
    require(any(item["card"]["id"] == starter["id"] and item["card"]["unit"] == starter["unit"] for item in items), "Invalid legacy reference")
unique([item["cardNumber"] for item in energy["coefficients"]], "energy card number")
for coefficient in energy["coefficients"]:
    require(any(item["number"] == coefficient["cardNumber"] and item["card"]["unit"] not in ("none", "kilograms") for item in items), "Invalid energy card reference")
    require(all(math.isfinite(coefficient[key]) and coefficient[key] > 0 for key in ("calories", "units")), "Invalid energy coefficient")
foods = energy["foods"]
unique([food["id"] for food in foods], "food ID")
unique([food["localizationKey"] for food in foods], "food localization key")
for food in foods:
    require(math.isfinite(food["calories"]) and food["calories"] >= 1, "Invalid food energy")
    for form in ("one", "many"):
        translated(food["localizationKey"] + "." + form)
require(energy["maxFoodServings"] > 0, "Invalid serving limit")
for key in ("smallCalorieFoodID", "overflowFoodID"):
    require(energy[key] in {food["id"] for food in foods}, "Invalid fallback food: " + key)
unique([theme["id"] for theme in themes], "theme ID")
require(any(theme["id"] == 0 for theme in themes), "Missing default theme")
for theme in themes:
    require(theme["city_image"] in assets, "Missing theme artwork")
    translated(f"theme.city.{theme['id']}")
    translated(f"theme.description.{theme['id']}")
    for key in ("calendar_background_color", "month_color", "day_color"):
        value = theme[key]
        require(len(value) == 6 and all(c in "0123456789abcdefABCDEF" for c in value), "Invalid theme color")
print(f"Validated {len(items)} cards, {len(energy['coefficients'])} coefficients, {len(foods)} foods and {len(themes)} themes.")
