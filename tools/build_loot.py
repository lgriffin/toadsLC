"""Build data/tbc-raid-loot.json, the TBC raid loot tables (Karazhan to Sunwell Plateau).

    python3 tools/build_loot.py                         # downloads wow-classic-items from npm
    python3 tools/build_loot.py --source path/to/data.json

Items, names, quality, slot and item level come from the wow-classic-items package
(MIT, scraped from Wowhead). data/loot/overrides.json supplies the raid list, boss names
and the drops the scrape gets wrong. Tier tokens and quest items (Magtheridon's Head,
Verdant Sphere) are linked to the pieces they turn into, both ways, the way Gargul links them.
"""
import argparse
import base64
import hashlib
import io
import json
import re
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "tbc-raid-loot.json"
OVERRIDES = ROOT / "data" / "loot" / "overrides.json"

PACKAGE = "wow-classic-items@2.0.1"
TARBALL = "https://registry.npmjs.org/wow-classic-items/-/wow-classic-items-2.0.1.tgz"
INTEGRITY = "sha512-iAyZNcnHuZNqjTH3qG5jMQoZSLBi4Aq5XYbly0IU+vCJruXkSzHqB8ejGwRp/nFaIS1Ron2/ALYQNtdewd6ZVw=="

QUALITIES = ("Rare", "Epic", "Legendary")

TOKEN = re.compile(r"^(Helm|Pauldrons|Chestguard|Gloves|Leggings|Bracers|Belt|Boots) of the "
                   r"(Fallen|Vanquished|Forgotten) (Hero|Champion|Defender|Conqueror|Vanquisher|Protector)$")
TOKEN_SLOT = {"Helm": "Head", "Pauldrons": "Shoulder", "Chestguard": "Chest", "Gloves": "Hands",
              "Leggings": "Legs", "Bracers": "Wrist", "Belt": "Waist", "Boots": "Feet"}
TOKEN_CLASSES = {
    "Hero": {"Hunter", "Mage", "Warlock"}, "Champion": {"Paladin", "Rogue", "Shaman"},
    "Defender": {"Warrior", "Priest", "Druid"}, "Conqueror": {"Paladin", "Priest", "Warlock"},
    "Vanquisher": {"Rogue", "Mage", "Druid"}, "Protector": {"Warrior", "Hunter", "Shaman"},
}
# Item level of the tier pieces each token buys: T4, T5, T6, and the Sunwell T6 wrist/waist/feet.
TOKEN_ILVL = {"Fallen": 120, "Vanquished": 133, "Forgotten": 146}
SUNWELL_SLOTS = {"Wrist", "Waist", "Feet"}

# Quest items handed in for a choice of reward: quest name -> the drops that start it.
QUEST_TOKENS = {
    "The Fall of Magtheridon": [32385, 32386],
    "Kael'thas and the Verdant Sphere": [32405],
}


def load_source(path):
    if path:
        return json.loads(Path(path).read_text())
    blob = urllib.request.urlopen(TARBALL).read()
    algo, digest = INTEGRITY.split("-", 1)
    if base64.b64encode(hashlib.new(algo, blob).digest()).decode() != digest:
        sys.exit(f"{TARBALL}: integrity check failed")
    with tarfile.open(fileobj=io.BytesIO(blob)) as tar:
        return json.load(tar.extractfile("package/data/json/data.json"))


def classes(item):
    for line in item["tooltip"]:
        if line["label"].startswith("Classes: "):
            return {c.strip() for c in line["label"][len("Classes: "):].split(",")}
    return set()


def is_set_piece(item):
    return any(re.search(r"\(0/\d+\)$", line["label"]) for line in item["tooltip"])


def build(source, overrides):
    errors = []
    zones = {z["id"]: z for z in overrides["zones"]}
    by_name = {z["name"]: z for z in overrides["zones"]}
    by_id = {it["itemId"]: it for it in source}
    fixes = {int(k): v for k, v in overrides["items"].items()}
    exclude = {int(k): v for k, v in overrides["exclude"].items()}

    for item_id, fix in list(fixes.items()) + [(k, {"name": v}) for k, v in exclude.items()]:
        have = by_id.get(item_id)
        if not have or have["name"] != fix["name"]:
            errors.append(f"override {item_id}: source has {have and have['name']!r}, expected {fix['name']!r}")
    for item_id, fix in fixes.items():
        zone = by_name.get(fix["zone"])
        if not zone or fix["boss"] not in zone["bosses"]:
            errors.append(f"override {item_id}: {fix['boss']!r} is not a boss of {fix['zone']!r}")

    items = {}
    for src in source:
        item_id = src["itemId"]
        if item_id in exclude:
            continue
        s = src.get("source") or {}
        if item_id in fixes:
            zone, boss = by_name[fixes[item_id]["zone"]], fixes[item_id]["boss"]
        else:
            ids = s.get("zone") if isinstance(s.get("zone"), list) else [s.get("zone")]
            zone = next((zones[z] for z in ids if z in zones), None)
            if not zone or src["quality"] not in QUALITIES or s.get("category") not in ("Boss Drop", "Zone Drop"):
                continue
            npc = s.get("name")
            if npc:
                boss = zone["aliases"].get(npc, npc)
                if boss != "Trash" and boss not in zone["bosses"]:
                    errors.append(f"{item_id} {src['name']}: unknown NPC {npc!r} in {zone['name']}")
            else:
                boss = None if zone["name"] in overrides["unattributed"] else "Trash"
        items[item_id] = entry(src, zone, boss)

    link_tokens(source, by_id, items, errors)
    if errors:
        sys.exit("\n".join(errors))

    order = {z["name"]: (i, {b: j for j, b in enumerate(z["bosses"])}) for i, z in enumerate(overrides["zones"])}

    def key(it):
        zi, bosses = order[it["zone"]]
        b = it["boss"]
        return zi, bosses.get(b, len(bosses) + (0 if b == "Trash" else 1)), "tokens" in it, it["itemId"]

    return {
        "format": "toads-raid-loot",
        "version": 1,
        "source": {
            "package": PACKAGE,
            "note": "Built by tools/build_loot.py from the wow-classic-items scrape of Wowhead plus data/loot/overrides.json.",
        },
        "zones": [{"name": z["name"], "phase": z["phase"], "bosses": z["bosses"]} for z in overrides["zones"]],
        "items": sorted(items.values(), key=key),
    }


def entry(src, zone, boss):
    return {
        "itemId": src["itemId"],
        "name": src["name"],
        "quality": src["quality"],
        "slot": src["slot"],
        "itemLevel": src.get("itemLevel"),
        "zone": zone["name"],
        "boss": boss,
        "phase": zone["phase"],
    }


def link_tokens(source, by_id, items, errors):
    rewards = {}
    for it in list(items.values()):
        m = TOKEN.match(it["name"])
        if not m:
            continue
        part, tier, group = m.groups()
        slot = TOKEN_SLOT[part]
        ilvl = 154 if tier == "Forgotten" and slot in SUNWELL_SLOTS else TOKEN_ILVL[tier]
        found = [src for src in source
                 if src["quality"] == "Epic" and src["slot"] == slot and src.get("itemLevel") == ilvl
                 and (src.get("source") or {}).get("category") in (None, "Vendor")
                 and len(classes(src)) == 1 and is_set_piece(src) and "Gladiator's" not in src["name"]
                 and classes(src) <= TOKEN_CLASSES[group]]
        if {c for src in found for c in classes(src)} != TOKEN_CLASSES[group]:
            errors.append(f"{it['itemId']} {it['name']}: tier pieces found for {sorted(c for s in found for c in classes(s))}")
        rewards[it["itemId"]] = [src["itemId"] for src in found]

    for src in source:
        for quest in (src.get("source") or {}).get("quests") or []:
            for token_id in QUEST_TOKENS.get(quest["name"], []):
                if src["itemId"] not in rewards.setdefault(token_id, []):
                    rewards[token_id].append(src["itemId"])
    for token_id in QUEST_TOKENS.values():
        for t in token_id:
            if t not in items or not rewards.get(t):
                errors.append(f"quest item {t}: missing from the loot table or has no rewards")

    for token_id, reward_ids in rewards.items():
        token = items[token_id]
        token["rewards"] = sorted(reward_ids)
        for rid in reward_ids:
            piece = items.get(rid) or entry(by_id[rid], {"name": token["zone"], "phase": token["phase"]}, token["boss"])
            piece.setdefault("tokens", []).append(token_id)
            piece["tokens"].sort()
            items[rid] = piece


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", help="wow-classic-items data/json/data.json (default: download the pinned package)")
    ap.add_argument("--check", action="store_true", help="fail if the committed file is out of date instead of writing it")
    args = ap.parse_args()

    doc = build(load_source(args.source), json.loads(OVERRIDES.read_text()))
    text = render(doc)
    if args.check:
        sys.exit(0 if OUT.exists() and OUT.read_text() == text else f"{OUT.relative_to(ROOT)} is out of date")
    OUT.write_text(text)
    counts = {}
    for it in doc["items"]:
        counts[it["zone"]] = counts.get(it["zone"], 0) + 1
    for zone, n in counts.items():
        print(f"{zone}: {n} items")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(doc['items'])} items)")


def render(doc):
    # One item per line keeps diffs readable when the overrides change.
    head = {k: v for k, v in doc.items() if k != "items"}
    lines = json.dumps(head, indent=2, ensure_ascii=False)[:-2]
    items = ",\n".join("    " + json.dumps(it, ensure_ascii=False) for it in doc["items"])
    return f'{lines},\n  "items": [\n{items}\n  ]\n}}\n'


if __name__ == "__main__":
    main()
