"""Validate the sample documents and a real addon export against the JSON Schemas.

    python3 tools/contract.py            # needs jsonschema and lua5.1 on PATH
"""
import json
import subprocess
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent


def check(schema_name, doc, label):
    schema = json.loads((ROOT / "schemas" / schema_name).read_text())
    errors = sorted(Draft202012Validator(schema).iter_errors(doc), key=lambda e: list(e.path))
    for e in errors:
        print(f"{label}: {'/'.join(map(str, e.path)) or '(root)'}: {e.message}")
    print(f"{label}: {'ok' if not errors else 'FAILED'}")
    return not errors


def main():
    ok = True
    ok &= check("priority.json", json.loads((ROOT / "fixtures/priority.sample.json").read_text()), "priority sample")
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
