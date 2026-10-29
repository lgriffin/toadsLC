"""Write fixtures/priority.test.json: a made-up priority for every item in the TBC raid loot
tables, to try the addon's tooltips, sessions and /tlc sim before the real list exists.

    python3 tools/make_test_priorities.py                          # downloads wow-classic-items from npm
    python3 tools/make_test_priorities.py --source path/to/data.json

THESE ARE NOT THE GUILD'S PRIORITIES. Each item gets a plausible order from its tooltip:
armour type, weapon type, class restriction and stats (spell power, healing, defense,
strength, agility...). Tier tokens list the classes that can use them. Anything the tooltip
says nothing about (random-enchant items, quest items) goes to everyone.
The first item keeps the hand-written Dragonspine Trophy priority from priority.sample.json.
"""
import argparse
import json
import re
from pathlib import Path

from build_loot import PACKAGE, load_source

ROOT = Path(__file__).resolve().parent.parent
LOOT = ROOT / "data" / "tbc-raid-loot.json"
SAMPLE = ROOT / "fixtures" / "priority.sample.json"
OUT = ROOT / "fixtures" / "priority.test.json"

ARMOUR = {"Cloth": {"Priest", "Mage", "Warlock"}, "Leather": {"Rogue", "Druid"},
          "Mail": {"Hunter", "Shaman"}, "Plate": {"Warrior", "Paladin"}}
WEAPON = {
    "Dagger": {"Rogue", "Warrior", "Hunter", "Mage", "Warlock", "Priest", "Druid", "Shaman"},
    "Fist Weapon": {"Rogue", "Warrior", "Hunter", "Shaman", "Druid"},
    "One-Handed Axe": {"Warrior", "Paladin", "Hunter", "Shaman", "Rogue"},
    "One-Handed Sword": {"Warrior", "Paladin", "Hunter", "Rogue", "Mage", "Warlock"},
    "One-Handed Mace": {"Warrior", "Paladin", "Rogue", "Priest", "Shaman", "Druid"},
    "Two-Handed Axe": {"Warrior", "Paladin", "Hunter", "Shaman"},
    "Two-Handed Sword": {"Warrior", "Paladin", "Hunter"},
    "Two-Handed Mace": {"Warrior", "Paladin", "Shaman", "Druid"},
    "Polearm": {"Warrior", "Paladin", "Hunter", "Druid"},
    "Staff": {"Priest", "Mage", "Warlock", "Shaman", "Druid", "Hunter", "Warrior"},
    "Shield": {"Warrior", "Paladin", "Shaman"},
    "Wand": {"Priest", "Mage", "Warlock"},
    "Bow": {"Hunter", "Warrior", "Rogue"}, "Gun": {"Hunter", "Warrior", "Rogue"},
    "Crossbow": {"Hunter", "Warrior", "Rogue"}, "Thrown": {"Warrior", "Rogue"},
    "Libram": {"Paladin"}, "Idol": {"Druid"}, "Totem": {"Shaman"},
}

# Each role's specs, best fit first; the tiers are cut from these lists.
ROLES = {
    "tank": [["Warrior:Protection"], ["Druid:Feral-Tank", "Paladin:Protection"]],
    "healer": [["Priest:Holy", "Druid:Restoration"], ["Paladin:Holy", "Shaman:Restoration", "Priest:Discipline"]],
    "caster": [["Mage:*", "Warlock:*"], ["Priest:Shadow", "Shaman:Elemental", "Druid:Balance"]],
    "agility": [["Rogue:*", "Hunter:*"], ["Druid:Feral-Cat", "Shaman:Enhancement"]],
    "strength": [["Warrior:DPS"], ["Paladin:Retribution", "Shaman:Enhancement"]],
    "attack": [["Rogue:*", "Warrior:DPS"], ["Hunter:*", "Shaman:Enhancement", "Paladin:Retribution", "Druid:Feral-Cat"]],
}


def stats(lines):
    text = " ".join(lines).lower()
    has = lambda *words: any(w in text for w in words)  # noqa: E731
    if has("defense rating", "dodge rating", "parry rating", "block rating", "block value"):
        return "tank"
    if has("healing", "mana per 5", "spirit") and not has("hit rating", "spell hit"):
        if has("spell power", "intellect", "healing", "mana per 5"):
            return "healer"
    if has("spell power", "spell damage", "spell hit", "spell critical", "spell haste", "spell penetration"):
        return "caster"
    if has("intellect") and not has("agility", "strength", "attack power"):
        return "caster"
    if has("agility"):
        return "agility"
    if has("strength"):
        return "strength"
    if has("attack power", "expertise", "armor penetration", "hit rating", "critical strike rating", "haste rating"):
        return "attack"
    return None


def class_line(lines):
    for line in lines:
        if line.startswith("Classes: "):
            return {c.strip() for c in line[len("Classes: "):].split(",")}
    return None


def class_of(token):
    return "Warrior" if token == "Warrior:DPS" else token.split(":")[0]


def priority_for(src):
    lines = [l["label"] for l in src["tooltip"]]
    allowed = class_line(lines)
    sub = src.get("subclass")
    if src.get("class") == "Weapon" or sub in ("Shield", "Libram", "Idol", "Totem"):
        usable = WEAPON.get(sub)
        allowed = (allowed & usable) if allowed and usable else (allowed or usable)
    preferred = ARMOUR.get(sub) if src.get("class") == "Armor" and src.get("slot") != "Back" else None
    if src.get("slot") == "Non-equippable":
        if allowed:  # tier tokens
            return [[{"spec": f"{c}:*"} for c in sorted(allowed)]]
        return [[{"spec": "ANY"}]]
    if sub in ("Bow", "Gun", "Crossbow"):
        return [[{"spec": "Hunter:*"}], [{"spec": "Rogue:*"}, {"spec": "Warrior:DPS"}]]
    if sub == "Thrown":
        return [[{"spec": "Rogue:*"}, {"spec": "Warrior:DPS"}]]
    role = stats(lines)
    if role is None:
        if allowed and len(allowed) < 4:  # relics, class-restricted pieces
            return [[{"spec": f"{c}:*"} for c in sorted(allowed)]]
        if preferred:
            return [[{"spec": f"{c}:*"} for c in sorted(preferred & (allowed or preferred))], [{"spec": "ANY"}]]
        return [[{"spec": "ANY"}]]
    tiers = []
    rest = []
    for group in ROLES[role]:
        tier = [t for t in group if not allowed or class_of(t) in allowed]
        if preferred:  # the armour's own wearers first, everyone else who can use it after
            rest += [t for t in tier if class_of(t) not in preferred]
            tier = [t for t in tier if class_of(t) in preferred]
        if tier:
            tiers.append(tier)
    restricted = class_line(lines)
    if restricted:  # a class the item names but the stats did not pick still gets a tier
        named = {class_of(t) for tier in tiers + [rest] for t in tier}
        rest += [f"{c}:*" for c in sorted(restricted - named)]
    if rest:
        tiers.append(rest)
    if not tiers and allowed and len(allowed) < 4:  # Libram of Souls Redeemed: spell power, but Paladin only
        return [[{"spec": f"{c}:*"} for c in sorted(allowed)]]
    if not tiers:
        return [[{"spec": "ANY"}]]
    return [[{"spec": t} for t in tier] for tier in tiers]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", help=f"a local copy of {PACKAGE}'s data/json/data.json")
    args = ap.parse_args()
    source = {i["itemId"]: i for i in load_source(args.source)}
    loot = json.loads(LOOT.read_text())
    sample = json.loads(SAMPLE.read_text())
    hand = {i["itemId"]: i for i in sample["items"]}
    items = []
    for it in loot["items"]:
        if it["itemId"] in hand:
            items.append(hand[it["itemId"]])
            continue
        items.append({"itemId": it["itemId"], "name": it["name"], "zone": it["zone"], "boss": it["boss"],
                      "phase": it["phase"], "priority": priority_for(source[it["itemId"]])})
    items.sort(key=lambda i: (i["itemId"] not in hand,))
    doc = {"format": "toads-loot-priority", "version": 1, "exportedAt": "2026-10-29T00:00:00Z",
           "guild": sample["guild"], "rules": sample["rules"], "council": sample["council"],
           "items": items, "members": sample["members"]}
    # one item per line: small enough to paste into the game, still diffable
    body = ",\n".join(json.dumps(i, ensure_ascii=False, separators=(",", ":")) for i in items)
    head = json.dumps({k: v for k, v in doc.items() if k not in ("items", "members")},
                      ensure_ascii=False, separators=(",", ":"))[:-1]
    OUT.write_text(f'{head},"items":[\n{body}\n],"members":{json.dumps(doc["members"], separators=(",", ":"))}}}\n')
    print(f"{OUT.relative_to(ROOT)}: {len(items)} items")


if __name__ == "__main__":
    main()
