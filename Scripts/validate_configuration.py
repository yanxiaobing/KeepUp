"""Validate bundled catalog references and translations without Xcode or PunchCard."""
import json
import math
import plistlib
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

iaap = json.loads((resources / "iaap.json").read_text())
require(all(isinstance(iaap[key], dict) for key in ("system", "ads")), "Invalid IAAP extension objects")
require(iaap["system"].get("isBanana") is False, "KeepUp system.isBanana must be false")
skus = iaap["skus"]
unique([sku["pid"] for sku in skus], "IAAP product ID")
for sku in skus:
    require(sku["pid"].startswith("com.bestlife.keepup.") and not any(c.isspace() for c in sku["pid"]), "Foreign IAAP product ID")
    require(sku["type"] in ("lifetime", "subscribe", "consumable"), "Unsupported IAAP product type")
pages = iaap["iaaps"]
unique([page["type"] for page in pages], "IAAP page type")
require({page["type"] for page in pages} == {"guide", "launch", "limited", "vip"}, "Invalid IAAP entries")
for page in pages:
    require(page.get("place") == {"guide": "引导页", "launch": "冷启动", "limited": "功能拦截", "vip": "会员页"}[page["type"]], "Missing IAAP scene name")
    pids = page["iap"]["pids"]
    unique(pids, "IAAP page product ID")
    require(set(pids) <= {sku["pid"] for sku in skus}, "Unknown IAAP page product")
    for key in ("closeAlpha", "priceAlpha"):
        if key in page:
            require(math.isfinite(page[key]) and 0 <= page[key] <= 1, "Invalid IAAP opacity")
    interval = page["iap"].get("timeInterval", 5)
    require(math.isfinite(interval) and 0 <= interval <= 3600, "Invalid IAAP carousel interval")
legacy = json.loads((resources / "membership.json").read_text())
require({offer["id"] for offer in legacy["offers"]} <= {sku["pid"] for sku in skus}, "Bundled IAAP lost a historical product")
print(f"Validated {len(skus)} IAAP products and {len(pages)} entry pages.")

# The shipped fallback stays inert until the advertising strategy is enabled explicitly.
ads = iaap["ads"]
info = plistlib.loads((root / "Config/Info.plist").read_bytes())
require(ads.get("enabled") is False, "Bundled advertising must remain disabled")
require(ads.get("admobAppId") == info["GADApplicationIdentifier"], "AdMob app ID mismatch")
for slot, key in (("splash", "KeepUpAdMobAppOpenAdUnitID"), ("insert", "KeepUpAdMobInterstitialAdUnitID"), ("reward", "KeepUpAdMobRewardedAdUnitID")):
    require(ads[slot].get("enabled") is False, "Bundled ad placement must remain disabled: " + slot)
    require(ads[slot].get("oversea") == info[key], "AdMob placement ID mismatch: " + slot)
    require(ads[slot].get("mainland") == "", "Unexpected mainland placement")
require(ads.get("gromoreAppId") == "", "GroMore must remain unconfigured")
require("policy" not in ads, "Unsupported ads.policy must not be shipped")
require(all("reward" not in page for page in pages if page["type"] != "limited"), "Unexpected reward on another IAAP entry")
limited = next(page for page in pages if page["type"] == "limited")
require(limited.get("hideFuncBtn") is False and limited.get("showGiveUp") is False, "Limited reward action must be visible")
reward = limited["reward"]
require(reward.get("enabled") is False, "Limited reward must stay disabled")
require(type(reward.get("count")) is int and reward["count"] == 1, "Limited reward count must be one")
require(reward.get("hideGiveUpWhenNoAd") is False, "Limited no-fill bypass must stay visible")
for slot, key in (("rewardId", "KeepUpAdMobRewardedAdUnitID"), ("insertId", "KeepUpAdMobInterstitialAdUnitID")):
    require(reward[slot].get("enabled") is False, "Limited ad placement must stay disabled: " + slot)
    require(reward[slot].get("oversea") == info[key], "Foreign limited ad placement: " + slot)
    require(reward[slot].get("mainland") == "", "Unexpected limited mainland placement")
require([page["type"] for page in pages] == ["guide", "launch", "limited", "vip"], "IAAP page order must start with guide")
require(iaap == json.loads((root / "docs/config/keepup-iaap.1.0.0.json").read_text()), "IAAP handoff differs from bundled fallback")
print("Validated disabled advertising switches, existing IAAP pages, independent resource IDs and complete handoff JSON.")

# Dynamic localized(...) calls are not all collected by Xcode's string extraction.
for key in ("membership.todayRemaining", "membership.cloudDescription", "membership.introTrial %@ %@",
            "membership.introUpfront %@ %@ %@", "membership.introRecurring %@ %@ %@"):
    translated(key)
