"""Build the release zip that players unzip into Interface/AddOns.

    python3 tools/package.py            # writes build/ToadsLC-<version>.zip
    python3 tools/package.py --check    # only checks the .toc against the folder

The zip holds one top-level folder, ToadsLC/, named like its .toc (the client skips an
addon whose folder and .toc names differ). Inside it are the .toc and exactly the files the
.toc lists, in the client's backslash-free layout; specs, tools, schemas, fixtures and the
loot JSON stay out. It fails if the .toc lists a missing file, or if a Lua file in the folder
is not listed (the client would never load it). Entries carry a fixed timestamp, so the same
tree always gives the same zip.
"""
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = "ToadsLC"
FIXED_TIME = (2026, 1, 1, 0, 0, 0)


def read_toc(addon_dir):
    """(metadata, files) from the folder's .toc; files are relative paths with forward slashes."""
    toc = addon_dir / f"{addon_dir.name}.toc"
    meta, files = {}, []
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        m = re.match(r"^##\s*([^:]+):\s*(.*)$", line)
        if m:
            meta[m.group(1).strip()] = m.group(2).strip()
        elif line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return meta, files


def problems(addon_dir):
    """Everything that would stop the client loading the folder as the .toc says."""
    found = []
    toc = addon_dir / f"{addon_dir.name}.toc"
    if not toc.is_file():
        return [f"{toc.name} is missing: the .toc must be named after its folder"]
    meta, files = read_toc(addon_dir)
    for key in ("Interface", "Title", "Version"):
        if not meta.get(key):
            found.append(f"{toc.name} has no ## {key}")
    for n in (meta.get("Interface") or "").split(","):
        if n.strip() and not re.fullmatch(r"\d{5,6}", n.strip()):
            found.append(f"## Interface {n.strip()!r} is not a client build number")
    if not re.fullmatch(r"\d+\.\d+\.\d+", meta.get("Version", "")):
        found.append(f"## Version {meta.get('Version')!r} is not x.y.z")
    seen = set()
    for f in files:
        if f in seen:
            found.append(f"{f} is listed twice")
        seen.add(f)
        if not (addon_dir / f).is_file():
            found.append(f"{f} is listed in the .toc but does not exist")
    for path in sorted(addon_dir.rglob("*.lua")):
        rel = path.relative_to(addon_dir).as_posix()
        if rel not in seen:
            found.append(f"{rel} is not listed in the .toc, so the client never loads it")
    return found


def build(addon_dir, out_dir):
    meta, files = read_toc(addon_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{addon_dir.name}-{meta['Version']}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in [f"{addon_dir.name}.toc"] + files:
            info = zipfile.ZipInfo(f"{addon_dir.name}/{rel}", FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, (addon_dir / rel).read_bytes())
    return out


def main(argv):
    addon_dir = ROOT / ADDON
    found = problems(addon_dir)
    for p in found:
        print(f"package: {p}", file=sys.stderr)
    if found:
        return 1
    if "--check" in argv:
        print("package: ok")
        return 0
    out = build(addon_dir, ROOT / "build")
    print(out.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
