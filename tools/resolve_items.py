"""Fill itemId, zone, boss and phase on a priority list from the TBC raid loot tables.

    python3 tools/resolve_items.py priorities.json > resolved.json

Items are matched by itemId when they have one, otherwise by name (case and spacing
ignored). A tier piece or quest reward keeps its own ID and gets the zone, boss and phase
of the token that buys it. Names that match nothing, or more than one item, are listed on
stderr and left as they were; the exit status is 1 if any are.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOOT = ROOT / "data" / "tbc-raid-loot.json"


def name_key(name):
    return re.sub(r"\s+", " ", name.replace("’", "'")).strip().lower()


class LootTable:
    def __init__(self, doc):
        self.by_id = {it["itemId"]: it for it in doc["items"]}
        self.by_name = {}
        for it in doc["items"]:
            self.by_name.setdefault(name_key(it["name"]), []).append(it)

    def find(self, item_id=None, name=None):
        """The loot entry for an ID or a name, or (None, reason)."""
        if item_id is not None:
            hit = self.by_id.get(item_id)
            return (hit, None) if hit else (None, f"item {item_id} is not in the TBC raid loot tables")
        hits = self.by_name.get(name_key(name or ""), [])
        # Two IDs for one name (Magtheridon's Head, Warglaive of Azzinoth) are fine when they drop together.
        if len({(h["zone"], h["boss"]) for h in hits}) > 1:
            return None, f"{name!r} matches {len(hits)} items: {', '.join(str(h['itemId']) for h in hits)}"
        if not hits:
            return None, f"{name!r} is not in the TBC raid loot tables"
        return hits[0], None


def resolve(doc, table):
    problems = []
    for entry in doc.get("items", []):
        hit, why = table.find(entry.get("itemId"), entry.get("name"))
        if not hit:
            problems.append(why)
            continue
        for field in ("itemId", "zone", "boss", "phase"):
            entry[field] = hit[field]
    return problems


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    doc = json.loads(Path(sys.argv[1]).read_text())
    problems = resolve(doc, LootTable(json.loads(LOOT.read_text())))
    for p in problems:
        print(p, file=sys.stderr)
    json.dump(doc, sys.stdout, indent=2, ensure_ascii=False)
    print()
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
