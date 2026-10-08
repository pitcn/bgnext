"""Prepare reviewed Titan P6 loot locally; never fetch addon data or install it."""

import argparse
import csv
from pathlib import Path
import re
import sys

FIELDS = {"boss", "item_id", "observed_mode", "verified", "evidence"}
BOSSES = set(range(1, 15))


def positive_integer(value, maximum):
    if not re.fullmatch(r"[0-9]+", value or ""):
        raise ValueError("expected a positive decimal integer")
    result = int(value)
    if not 1 <= result <= maximum:
        raise ValueError(f"expected a value between 1 and {maximum}")
    return result


def read_drops(source, require_complete=True):
    reader = csv.DictReader(source, strict=True)
    try:
        return _read_pools(reader, require_complete)
    except csv.Error as exc:
        raise ValueError(f"line {reader.line_num}: malformed CSV: {exc}") from exc


def _read_pools(reader, require_complete):
    if reader.fieldnames is None or set(reader.fieldnames) != FIELDS or len(reader.fieldnames) != len(FIELDS):
        raise ValueError("required CSV columns: boss,item_id,observed_mode,verified,evidence")
    pools = {}
    for row in reader:
        if None in row or any(value is None for value in row.values()):
            raise ValueError(f"line {reader.line_num}: malformed CSV row")
        row = {key: value.strip() for key, value in row.items()}
        try:
            boss = positive_integer(row["boss"], 14)
            item_id = positive_integer(row["item_id"], 2147483647)
            if row["verified"] != "yes" or not row["evidence"]:
                raise ValueError("each drop must be verified=yes with a source reference")
            if row["observed_mode"] not in {"normal", "hard"}:
                raise ValueError("observed_mode must be normal or hard; both use the same P6 pool")
        except ValueError as exc:
            raise ValueError(f"line {reader.line_num}: {exc}") from exc
        pools.setdefault(boss, set()).add(item_id)
    if not pools:
        raise ValueError("no verified drops supplied")
    missing = BOSSES - pools.keys()
    if require_complete and missing:
        raise ValueError("boss coverage missing: " + ",".join(map(str, sorted(missing))))
    return {boss: sorted(pools[boss]) for boss in sorted(pools)}


def render_lua(pools):
    lines = [
        "-- Locally prepared Titan P6 candidate; review the source CSV before loading.",
        "-- One 25-player pool per boss; mechanic hard mode is not a separate raid difficulty.",
        "-- Boss coverage does not prove that every drop is present.",
        'if type(BG) ~= "table" or not BG.IsTitan then return end',
        'local raid = type(BG.Loot) == "table" and BG.Loot.ULDtitan',
        'if type(raid) ~= "table" or type(raid.N) ~= "table" then return end',
    ]
    for boss, items in sorted(pools.items()):
        lines.append(f"raid.N.boss{boss} = {{ " + ", ".join(map(str, items)) + " }")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="reviewed CSV, not a reference addon's source")
    parser.add_argument("--output", required=True, type=Path, help="new local Lua candidate file")
    parser.add_argument("--allow-partial", action="store_true", help="explicitly permit missing boss pools for review")
    args = parser.parse_args(argv)
    try:
        with args.source.open(encoding="utf-8-sig", newline="") as source:
            pools = read_drops(source, require_complete=not args.allow_partial)
        candidate = render_lua(pools)
        # Validate the entire input before writing; never overwrite an existing file.
        with args.output.open("x", encoding="utf-8", newline="\n") as output:
            output.write(candidate)
    except (OSError, ValueError) as exc:
        print(f"P6 candidate rejected: {exc}", file=sys.stderr)
        return 1
    print(f"Prepared {len(pools)}/14 boss pools, {sum(map(len, pools.values()))} boss/item pairs; review required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
