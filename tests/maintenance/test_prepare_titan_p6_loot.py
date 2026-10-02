import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("p6_loot", ROOT / "tools/prepare-titan-p6-loot.py")
loot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(loot)


class PrepareP6LootTests(unittest.TestCase):
    def run_lua(self, script):
        lua = shutil.which("lua5.1") or shutil.which("lua")
        if not lua:
            candidate = Path(r"C:\Program Files (x86)\Lua\5.1\lua.exe")
            if candidate.exists():
                lua = str(candidate)
        if not lua:
            self.skipTest("Lua runtime unavailable; run the repository Lua checks")
        with tempfile.TemporaryDirectory() as directory:
            script_path = Path(directory) / "integration.lua"
            script_path.write_text(script, encoding="utf-8")
            result = subprocess.run([lua, str(script_path)], cwd=ROOT, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_same_boss_verified_drops_share_one_pool(self):
        source = io.StringIO(
            "boss,item_id,observed_mode,verified,evidence\n"
            "1,90002,normal,yes,fixture\n"
            "1,90001,hard,yes,fixture\n"
            "1,90002,hard,yes,fixture\n"
            "2,90002,normal,yes,fixture\n"
        )
        pools = loot.read_drops(source, require_complete=False)
        self.assertEqual(pools, {1: [90001, 90002], 2: [90002]})
        lua = loot.render_lua(pools)
        self.assertIn("raid.N.boss1 = { 90001, 90002 }", lua)
        self.assertIn("raid.N.boss2 = { 90002 }", lua)
        self.assertNotIn("N10", lua)
        self.assertNotIn("N25", lua)
        self.assertNotIn("raid.H", lua)

    def test_complete_boss_coverage_is_required_unless_explicitly_partial(self):
        with self.assertRaisesRegex(ValueError, "boss coverage missing"):
            loot.read_drops(io.StringIO("boss,item_id,observed_mode,verified,evidence\n1,90001,normal,yes,fixture\n"))
        rows = "".join(f"{boss},{90000 + boss},normal,yes,fixture\n" for boss in range(1, 15))
        pools = loot.read_drops(io.StringIO("boss,item_id,observed_mode,verified,evidence\n" + rows))
        self.assertEqual(len(pools), 14)

    def test_pending_guessed_or_malformed_rows_cannot_generate_a_pool(self):
        header = "boss,item_id,observed_mode,verified,evidence\n"
        for row in (
            "1,90001,normal,pending,fixture",
            "1,90001,normal,yes,",
            "1,90001,10,yes,fixture",
            "1,90001,H25,yes,fixture",
            "0,90001,normal,yes,fixture",
            "15,90001,normal,yes,fixture",
            "1,-1,normal,yes,fixture",
            "1,1e4,normal,yes,fixture",
            "1,90001;print(1),normal,yes,fixture",
            "1,90001,normal,yes,fixture,extra",
            "1,90001,normal,yes",
        ):
            with self.subTest(row=row), self.assertRaises(ValueError):
                loot.read_drops(io.StringIO(header + row + "\n"), require_complete=False)
        with self.assertRaises(ValueError):
            loot.read_drops(io.StringIO(header), require_complete=False)

    def test_cli_never_overwrites_output_or_writes_invalid_input(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.csv"
            output = Path(directory) / "candidate.lua"
            source.write_text("boss,item_id,observed_mode,verified,evidence\n1,90001,normal,yes,fixture\n", encoding="utf-8")
            command = [str(source), "--output", str(output), "--allow-partial"]
            self.assertEqual(loot.main(command), 0)
            original = output.read_bytes()
            self.assertEqual(loot.main(command), 1)
            self.assertEqual(output.read_bytes(), original)
            source.write_text("boss,item_id,observed_mode,verified,evidence\n1,90001,normal,pending,fixture\n", encoding="utf-8")
            rejected = Path(directory) / "rejected.lua"
            self.assertEqual(loot.main([str(source), "--output", str(rejected), "--allow-partial"]), 1)
            self.assertFalse(rejected.exists())

    def test_generated_pool_works_with_real_wishlist_and_price_modules(self):
        pools = loot.read_drops(io.StringIO(
            "boss,item_id,observed_mode,verified,evidence\n"
            "1,90001,normal,yes,fixture\n1,90002,hard,yes,fixture\n"
        ), require_complete=False)
        script = '''BG = {IsTitan = true, BGNext = {}, Loot = {ULDtitan = {N = {}}}}
%s
local Wishlist = dofile("Core/BGNext/Wishlist.lua")
local Prices = dofile("Core/BGNext/AuctionPriceCatalog.lua")
local difficulty = {"N"}
for _, id in ipairs({90001, 90002}) do
    local drop = Wishlist.resolveDrop(id, difficulty, BG.Loot.ULDtitan, 14,
        function(a, b) return a == b end, 1, 1)
    assert(drop and drop.bossIndex == 1 and drop.difficultyIndex == 1)
end
local prices = Prices.build({raidId = "ULDtitan", difficulties = difficulty,
    bosses = {{id = "boss1", name = "Fixture"}}, loot = BG.Loot.ULDtitan})
assert(prices.byItem[90001] and prices.byItem[90002])
assert(#prices.groups[1].items == 2)
assert(BG.Loot.ULDtitan.H == nil and BG.Loot.ULDtitan.N10 == nil)
''' % loot.render_lua(pools)
        self.run_lua(script)

    def test_candidate_is_safe_when_catalog_is_missing_or_not_titan(self):
        candidate = loot.render_lua({1: [90001]})
        self.run_lua('''local loadCandidate = assert(loadstring([=[%s]=]))
BG = nil
assert(pcall(loadCandidate))
for _, state in ipairs({{}, {IsTitan = false}, {IsTitan = true},
    {IsTitan = true, Loot = {}}, {IsTitan = true, Loot = {ULDtitan = {N = 1}}}}) do
    BG = state
    assert(pcall(loadCandidate))
end
BG = {IsTitan = false, Loot = {ULDtitan = {N = {boss1 = {123}}}}}
assert(pcall(loadCandidate))
assert(BG.Loot.ULDtitan.N.boss1[1] == 123)
''' % candidate)

    def test_malformed_quotes_are_rejected_instead_of_becoming_evidence(self):
        for row in ('1,90001,normal,yes,"fixture"garbage\n',
                    '1,90001,normal,yes,"unterminated\n'):
            with self.subTest(row=row), self.assertRaises(ValueError):
                loot.read_drops(io.StringIO("boss,item_id,observed_mode,verified,evidence\n" + row),
                                require_complete=False)


if __name__ == "__main__":
    unittest.main()
