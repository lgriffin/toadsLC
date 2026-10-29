"""Tests for the Python tools: the release packager and the item resolver.

    python3 -m unittest discover -s tests
"""
import json
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import package  # noqa: E402
from resolve_items import LootTable, name_key, resolve  # noqa: E402


class PackageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def fake_addon(self, toc_body, files=("core/A.lua",), name="ToadsLC"):
        d = self.tmp / name
        for f in files:
            (d / f).parent.mkdir(parents=True, exist_ok=True)
            (d / f).write_text("-- " + f)
        (d / f"{name}.toc").write_text(toc_body)
        return d

    def test_the_real_addon_folder_packages_cleanly(self):
        self.assertEqual([], package.problems(ROOT / "ToadsLC"))

    def test_zip_holds_one_toadslc_folder_with_the_toc_and_only_its_files(self):
        out = package.build(ROOT / "ToadsLC", self.tmp)
        meta, files = package.read_toc(ROOT / "ToadsLC")
        self.assertEqual(f"ToadsLC-{meta['Version']}.zip", out.name)
        with zipfile.ZipFile(out) as z:
            names = z.namelist()
        self.assertEqual(["ToadsLC/ToadsLC.toc"] + [f"ToadsLC/{f}" for f in files], names)
        self.assertTrue(all(n.startswith("ToadsLC/") for n in names))
        self.assertFalse(any(n.endswith((".json", ".py", "_spec.lua")) for n in names))

    def test_zip_is_the_same_bytes_every_build(self):
        a = package.build(ROOT / "ToadsLC", self.tmp / "a").read_bytes()
        b = package.build(ROOT / "ToadsLC", self.tmp / "b").read_bytes()
        self.assertEqual(a, b)

    def test_a_release_version_is_stamped_into_the_zipped_toc_only(self):
        out = package.build(ROOT / "ToadsLC", self.tmp, "9.8.7")
        self.assertEqual("ToadsLC-9.8.7.zip", out.name)
        with zipfile.ZipFile(out) as z:
            toc = z.read("ToadsLC/ToadsLC.toc").decode()
        self.assertIn("## Version: 9.8.7\n", toc)
        self.assertIn("## Interface:", toc)
        self.assertNotIn("9.8.7", (ROOT / "ToadsLC" / "ToadsLC.toc").read_text())

    def test_reports_a_missing_unlisted_or_doubled_file(self):
        d = self.fake_addon(
            "## Interface: 20505\n## Title: T\n## Version: 1.0.0\n\ncore\\A.lua\ncore\\A.lua\ncore\\Gone.lua\n",
            files=("core/A.lua", "core/Extra.lua"))
        found = package.problems(d)
        self.assertIn("core/A.lua is listed twice", found)
        self.assertIn("core/Gone.lua is listed in the .toc but does not exist", found)
        self.assertIn("core/Extra.lua is not listed in the .toc, so the client never loads it", found)

    def test_reports_a_toc_not_named_after_its_folder(self):
        d = self.fake_addon("## Interface: 20505\n", name="ToadsLC")
        (d / "ToadsLC.toc").rename(d / "Toads.toc")
        self.assertIn("must be named after its folder", package.problems(d)[0])

    def test_reports_bad_metadata(self):
        d = self.fake_addon("## Interface: 2.5.5\n## Version: v1\n\ncore\\A.lua\n")
        found = package.problems(d)
        self.assertIn("ToadsLC.toc has no ## Title", found)
        self.assertIn("## Interface '2.5.5' is not a client build number", found)
        self.assertIn("## Version 'v1' is not x.y.z", found)

    def test_accepts_several_interface_numbers(self):
        d = self.fake_addon("## Interface: 20505, 20506\n## Title: T\n## Version: 1.2.3\n\ncore\\A.lua\n")
        self.assertEqual([], package.problems(d))


class ResolveItemsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.table = LootTable(json.loads((ROOT / "data" / "tbc-raid-loot.json").read_text()))

    def test_name_key_ignores_case_spacing_and_curly_apostrophes(self):
        self.assertEqual(name_key("Magtheridon's Head"), name_key("  magtheridon’s   HEAD "))

    def test_fills_id_zone_boss_and_phase_from_a_name(self):
        doc = {"items": [{"name": "dragonspine trophy"}]}
        self.assertEqual([], resolve(doc, self.table))
        item = doc["items"][0]
        self.assertEqual((28830, "Gruul's Lair", "Gruul the Dragonkiller"), (item["itemId"], item["zone"], item["boss"]))

    def test_rejects_an_id_whose_name_differs(self):
        doc = {"items": [{"itemId": 28830, "name": "Hearthstone"}]}
        problems = resolve(doc, self.table)
        self.assertEqual(1, len(problems))
        self.assertIn("is 'Dragonspine Trophy', not 'Hearthstone'", problems[0])

    def test_lists_unknown_names_and_keeps_the_entry(self):
        doc = {"items": [{"name": "Thunderfury, Blessed Blade of the Windseeker"}]}
        problems = resolve(doc, self.table)
        self.assertIn("is not in the TBC raid loot tables", problems[0])
        self.assertEqual([{"name": "Thunderfury, Blessed Blade of the Windseeker"}], doc["items"])

    def test_a_shared_name_that_drops_together_becomes_one_entry_per_id(self):
        doc = {"items": [{"name": "Magtheridon's Head", "priority": [["ANY"]]}]}
        self.assertEqual([], resolve(doc, self.table))
        ids = sorted(i["itemId"] for i in doc["items"])
        self.assertEqual(2, len(ids))
        self.assertTrue(all(i["priority"] == [["ANY"]] for i in doc["items"]))


if __name__ == "__main__":
    unittest.main()
