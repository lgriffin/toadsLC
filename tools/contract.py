"""Validate the sample documents, the TBC raid loot tables and a real addon export against the JSON Schemas.

    python3 tools/contract.py            # needs jsonschema and lua5.1 on PATH
"""
import json
import subprocess
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

from resolve_items import LootTable, resolve

ROOT = Path(__file__).resolve().parent.parent


def check(schema_name, doc, label):
    schema = json.loads((ROOT / "schemas" / schema_name).read_text())
    errors = sorted(Draft202012Validator(schema).iter_errors(doc), key=lambda e: list(e.path))
    for e in errors:
        print(f"{label}: {'/'.join(map(str, e.path)) or '(root)'}: {e.message}")
    print(f"{label}: {'ok' if not errors else 'FAILED'}")
    return not errors


def check_loot(loot, priority):
    """Bosses belong to their zone, token links point both ways, and the sample's items agree with the tables."""
    problems = []
    bosses = {z["name"]: set(z["bosses"]) | {"Trash", None} for z in loot["zones"]}
    by_id = {it["itemId"]: it for it in loot["items"]}
    for it in loot["items"]:
        if it["boss"] not in bosses.get(it["zone"], ()):
            problems.append(f"{it['itemId']}: {it['boss']!r} is not a boss of {it['zone']!r}")
        for field, back in (("rewards", "tokens"), ("tokens", "rewards")):
            for other in it.get(field, []):
                if it["itemId"] not in by_id.get(other, {}).get(back, []):
                    problems.append(f"{it['itemId']}: {field} lists {other}, which does not link back")
    for item in priority["items"]:
        hit = by_id.get(item.get("itemId"))
        want = {k: item.get(k) for k in ("name", "zone", "boss", "phase")}
        if not hit or {k: hit[k] for k in want} != want:
            problems.append(f"priority sample {item.get('itemId')}: {want} does not match the loot tables")
    # The sample's items, stripped to their names, resolve back to the same IDs and bosses.
    names = {"items": [{"name": it["name"]} for it in priority["items"]]}
    problems += resolve(names, LootTable(loot))
    for got, item in zip(names["items"], priority["items"]):
        if got.get("itemId") != item.get("itemId") or got.get("boss") != item.get("boss"):
            problems.append(f"resolve_items: {item['name']!r} resolved to {got}")
    for p in problems:
        print(f"loot tables: {p}")
    print(f"loot tables: {'ok' if not problems else 'FAILED'}")
    return not problems


def main():
    ok = True
    priority = json.loads((ROOT / "fixtures/priority.sample.json").read_text())
    loot = json.loads((ROOT / "data/tbc-raid-loot.json").read_text())
    ok &= check("priority.json", priority, "priority sample")
    ok &= check("loot.json", loot, "loot schema") and check_loot(loot, priority)
    test_list = json.loads((ROOT / "fixtures/priority.test.json").read_text())
    ok &= check("priority.json", test_list, "test priority list")
    if len(test_list["items"]) != len(loot["items"]):
        print("test priority list: does not cover the loot tables; run tools/make_test_priorities.py")
        ok = False
    ok &= check("session.json", json.loads((ROOT / "fixtures/session.sample.json").read_text()), "session sample")
    out = subprocess.run(["lua5.1", "tools/export_sample.lua"], cwd=ROOT, check=True, capture_output=True, text=True)
    export = json.loads(out.stdout)
    ok &= check("session.json", export, "addon export")
    if len(export["sessions"]) != 2:
        print("addon export: expected 2 sessions")
        ok = False
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
