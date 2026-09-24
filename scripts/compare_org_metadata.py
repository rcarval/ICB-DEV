#!/usr/bin/env python3
"""Compare metadata inventories between two Salesforce orgs via listMetadata.

Usage:
  python3 scripts/compare_org_metadata.py \
    --uat-org ICB-UAT \
    --sapsf-org ICB-SAPSF \
    --uat-manifest manifest/package-full-uat.xml \
    --sapsf-manifest manifest/package-full-sapsf.xml \
    --output snapshots/reports/UAT_vs_SAPSF_metadata_diff.xlsx
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime
from pathlib import Path

NS = {"md": "http://soap.sforce.com/2006/04/metadata"}

# Types that often fail or are huge / unsupported for listMetadata in some orgs
SKIP_TYPES = {
    "Profile",  # still list but can be large; keep enabled unless it fails
}


def parse_types_from_manifest(path: Path) -> list[str]:
    tree = ET.parse(path)
    root = tree.getroot()
    types: list[str] = []
    for t in root.findall("md:types", NS):
        name_el = t.find("md:name", NS)
        if name_el is not None and name_el.text:
            types.append(name_el.text.strip())
    # also try without namespace (some generators omit it inconsistently)
    if not types:
        for t in root.findall("types"):
            name_el = t.find("name")
            if name_el is not None and name_el.text:
                types.append(name_el.text.strip())
    return sorted(set(types))


def list_metadata(org: str, metadata_type: str) -> list[dict]:
    cmd = [
        "sf",
        "org",
        "list",
        "metadata",
        "-m",
        metadata_type,
        "-o",
        org,
        "--json",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        print(f"  TIMEOUT listing {metadata_type} on {org}", file=sys.stderr)
        return []

    if proc.returncode != 0:
        # many types return non-zero when empty or unsupported
        err = (proc.stderr or proc.stdout or "").strip()
        if err:
            print(f"  WARN {org}/{metadata_type}: {err[:200]}", file=sys.stderr)
        return []

    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(f"  INVALID JSON for {org}/{metadata_type}", file=sys.stderr)
        return []

    result = payload.get("result")
    if result is None:
        return []
    if isinstance(result, dict):
        # sometimes wrapped
        result = result.get("result") or result.get("fileProperties") or []
    if not isinstance(result, list):
        return []

    items = []
    for row in result:
        if not isinstance(row, dict):
            continue
        full_name = row.get("fullName") or row.get("fullName")
        if not full_name:
            continue
        items.append(
            {
                "fullName": full_name,
                "lastModifiedDate": row.get("lastModifiedDate") or "",
                "lastModifiedByName": row.get("lastModifiedByName") or "",
                "lastModifiedById": row.get("lastModifiedById") or "",
                "createdDate": row.get("createdDate") or "",
                "createdByName": row.get("createdByName") or "",
                "manageableState": row.get("manageableState") or "",
                "type": row.get("type") or metadata_type,
            }
        )
    return items


def inventory_org(org: str, types: list[str], cache_path: Path) -> dict[str, dict[str, dict]]:
    """Return map: type -> fullName -> props."""
    if cache_path.exists():
        print(f"Loading cache {cache_path}")
        with cache_path.open() as f:
            return json.load(f)

    inv: dict[str, dict[str, dict]] = {}
    for i, mtype in enumerate(types, 1):
        print(f"[{i}/{len(types)}] {org}: {mtype}")
        rows = list_metadata(org, mtype)
        inv[mtype] = {r["fullName"]: r for r in rows}
        print(f"    -> {len(rows)} components")

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    with cache_path.open("w") as f:
        json.dump(inv, f)
    return inv


def classify(uat_row: dict | None, sapsf_row: dict | None) -> str:
    if uat_row and not sapsf_row:
        return "OnlyInUAT"
    if sapsf_row and not uat_row:
        return "OnlyInSAPSF"
    assert uat_row and sapsf_row
    d1 = (uat_row.get("lastModifiedDate") or "")[:19]
    d2 = (sapsf_row.get("lastModifiedDate") or "")[:19]
    u1 = uat_row.get("lastModifiedByName") or ""
    u2 = sapsf_row.get("lastModifiedByName") or ""
    if d1 == d2 and u1 == u2:
        return "InBoth_SameDate"
    if d1 != d2 and u1 != u2:
        return "InBoth_DifferentDateAndUser"
    if d1 != d2:
        return "InBoth_DifferentDate"
    if u1 != u2:
        return "InBoth_DifferentUser"
    return "InBoth_SameDate"


def build_rows(uat: dict, sapsf: dict) -> list[dict]:
    all_types = sorted(set(uat.keys()) | set(sapsf.keys()))
    rows = []
    for mtype in all_types:
        names = set(uat.get(mtype, {}).keys()) | set(sapsf.get(mtype, {}).keys())
        for name in sorted(names):
            ur = uat.get(mtype, {}).get(name)
            sr = sapsf.get(mtype, {}).get(name)
            status = classify(ur, sr)
            rows.append(
                {
                    "MetadataType": mtype,
                    "FullName": name,
                    "ExistsInUAT": "Yes" if ur else "No",
                    "ExistsInSAPSF": "Yes" if sr else "No",
                    "LastModifiedDate_UAT": (ur or {}).get("lastModifiedDate", ""),
                    "LastModifiedBy_UAT": (ur or {}).get("lastModifiedByName", ""),
                    "LastModifiedById_UAT": (ur or {}).get("lastModifiedById", ""),
                    "LastModifiedDate_SAPSF": (sr or {}).get("lastModifiedDate", ""),
                    "LastModifiedBy_SAPSF": (sr or {}).get("lastModifiedByName", ""),
                    "LastModifiedById_SAPSF": (sr or {}).get("lastModifiedById", ""),
                    "DiffStatus": status,
                    "ManageableState_UAT": (ur or {}).get("manageableState", ""),
                    "ManageableState_SAPSF": (sr or {}).get("manageableState", ""),
                }
            )
    return rows


def write_excel(rows: list[dict], output: Path) -> None:
    try:
        from openpyxl import Workbook
        from openpyxl.styles import Font
    except ImportError:
        print("Installing openpyxl...", file=sys.stderr)
        subprocess.check_call([sys.executable, "-m", "pip", "install", "openpyxl", "-q"])
        from openpyxl import Workbook
        from openpyxl.styles import Font

    wb = Workbook()

    # Summary
    ws = wb.active
    ws.title = "Summary"
    status_counts = defaultdict(int)
    type_counts = defaultdict(lambda: defaultdict(int))
    for r in rows:
        status_counts[r["DiffStatus"]] += 1
        type_counts[r["MetadataType"]][r["DiffStatus"]] += 1

    ws.append(["GeneratedAt", datetime.utcnow().isoformat() + "Z"])
    ws.append(["TotalComponents", len(rows)])
    ws.append([])
    ws.append(["DiffStatus", "Count"])
    for k in sorted(status_counts.keys()):
        ws.append([k, status_counts[k]])
    ws.append([])
    ws.append(
        [
            "MetadataType",
            "OnlyInUAT",
            "OnlyInSAPSF",
            "InBoth_SameDate",
            "InBoth_DifferentDate",
            "InBoth_DifferentUser",
            "InBoth_DifferentDateAndUser",
            "Total",
        ]
    )
    for mtype in sorted(type_counts.keys()):
        c = type_counts[mtype]
        ws.append(
            [
                mtype,
                c.get("OnlyInUAT", 0),
                c.get("OnlyInSAPSF", 0),
                c.get("InBoth_SameDate", 0),
                c.get("InBoth_DifferentDate", 0),
                c.get("InBoth_DifferentUser", 0),
                c.get("InBoth_DifferentDateAndUser", 0),
                sum(c.values()),
            ]
        )
    for cell in ws[1]:
        cell.font = Font(bold=True)

    headers = [
        "MetadataType",
        "FullName",
        "ExistsInUAT",
        "ExistsInSAPSF",
        "LastModifiedDate_UAT",
        "LastModifiedBy_UAT",
        "LastModifiedById_UAT",
        "LastModifiedDate_SAPSF",
        "LastModifiedBy_SAPSF",
        "LastModifiedById_SAPSF",
        "DiffStatus",
        "ManageableState_UAT",
        "ManageableState_SAPSF",
    ]

    def add_sheet(title: str, filter_fn):
        sheet = wb.create_sheet(title)
        sheet.append(headers)
        for cell in sheet[1]:
            cell.font = Font(bold=True)
        for r in rows:
            if filter_fn(r):
                sheet.append([r[h] for h in headers])

    add_sheet("AllComponents", lambda r: True)
    add_sheet("AllDifferences", lambda r: r["DiffStatus"] != "InBoth_SameDate")
    add_sheet("OnlyInUAT", lambda r: r["DiffStatus"] == "OnlyInUAT")
    add_sheet("OnlyInSAPSF", lambda r: r["DiffStatus"] == "OnlyInSAPSF")
    add_sheet(
        "ModifiedDifferent",
        lambda r: r["DiffStatus"]
        in {
            "InBoth_DifferentDate",
            "InBoth_DifferentUser",
            "InBoth_DifferentDateAndUser",
        },
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    wb.save(output)
    print(f"Wrote {output}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--uat-org", default="ICB-UAT")
    ap.add_argument("--sapsf-org", default="ICB-SAPSF")
    ap.add_argument("--uat-manifest", default="manifest/package-full-uat.xml")
    ap.add_argument("--sapsf-manifest", default="manifest/package-full-sapsf.xml")
    ap.add_argument("--output", default="snapshots/reports/UAT_vs_SAPSF_metadata_diff.xlsx")
    ap.add_argument("--cache-dir", default="snapshots/reports/cache")
    ap.add_argument("--refresh", action="store_true", help="Ignore cache and re-list")
    args = ap.parse_args()

    uat_types = parse_types_from_manifest(Path(args.uat_manifest))
    sapsf_types = parse_types_from_manifest(Path(args.sapsf_manifest))
    all_types = sorted(set(uat_types) | set(sapsf_types))
    print(f"Types to inventory: {len(all_types)}")

    cache_dir = Path(args.cache_dir)
    uat_cache = cache_dir / f"{args.uat_org}_inventory.json"
    sapsf_cache = cache_dir / f"{args.sapsf_org}_inventory.json"
    if args.refresh:
        uat_cache.unlink(missing_ok=True)
        sapsf_cache.unlink(missing_ok=True)

    uat_inv = inventory_org(args.uat_org, all_types, uat_cache)
    sapsf_inv = inventory_org(args.sapsf_org, all_types, sapsf_cache)

    rows = build_rows(uat_inv, sapsf_inv)
    write_excel(rows, Path(args.output))

    # Also dump CSV for quick use
    csv_path = Path(args.output).with_suffix(".csv")
    import csv

    with csv_path.open("w", newline="") as f:
        if rows:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    print(f"Wrote {csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
