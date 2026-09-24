#!/usr/bin/env python3
"""Split a package.xml into smaller manifests by metadata type groups."""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://soap.sforce.com/2006/04/metadata"
ET.register_namespace("", NS)

# Prefer retrieving these high-value groups first
GROUPS = {
    "01-code": [
        "ApexClass",
        "ApexTrigger",
        "ApexPage",
        "ApexComponent",
        "LightningComponentBundle",
        "AuraDefinitionBundle",
        "StaticResource",
    ],
    "02-automation": [
        "Flow",
        "FlowDefinition",
        "Workflow",
        "WorkflowRule",
        "AssignmentRules",
        "AutoResponseRules",
        "EscalationRules",
        "MatchingRules",
        "DuplicateRule",
        "ApprovalProcess",
    ],
    "03-objects": [
        "CustomObject",
        "CustomField",
        "CustomTab",
        "CustomMetadata",
        "CustomMetadataType",
        "PlatformEventChannel",
        "PlatformEventChannelMember",
        "EventDelivery",
        "EventSubscription",
        "CustomIndex",
    ],
    "04-ui": [
        "Layout",
        "FlexiPage",
        "CustomApplication",
        "HomePageLayout",
        "HomePageComponent",
        "ListView",
        "CompactLayout",
        "QuickAction",
        "GlobalValueSet",
        "StandardValueSet",
        "PathAssistant",
        "LightningMessageChannel",
    ],
    "05-security": [
        "Profile",
        "PermissionSet",
        "PermissionSetGroup",
        "CustomPermission",
        "Role",
        "Group",
        "SharingRules",
        "SharingSet",
        "MutingPermissionSet",
    ],
    "06-integration": [
        "NamedCredential",
        "ExternalCredential",
        "ExternalDataSource",
        "ConnectedApp",
        "AuthProvider",
        "RemoteSiteSetting",
        "CspTrustedSite",
        "CorsWhitelistOrigin",
        "CallCenter",
        "ExternalServiceRegistration",
    ],
    "07-reports": [
        "Report",
        "ReportType",
        "Dashboard",
        "AnalyticSnapshot",
        "WaveApplication",
        "WaveDashboard",
        "WaveDataflow",
        "WaveDataset",
        "WaveLens",
        "WaveRecipe",
        "WaveTemplateBundle",
        "WaveXmd",
    ],
    "08-other": [],  # filled with remaining types
}


def parse_types(path: Path) -> dict[str, list[str]]:
    tree = ET.parse(path)
    root = tree.getroot()
    out: dict[str, list[str]] = {}
    for t in root.findall(f"{{{NS}}}types"):
        name = t.findtext(f"{{{NS}}}name")
        members = [m.text for m in t.findall(f"{{{NS}}}members") if m.text]
        if name:
            out[name] = members
    if not out:
        for t in root.findall("types"):
            name = t.findtext("name")
            members = [m.text for m in t.findall("members") if m.text]
            if name:
                out[name] = members
    return out


def write_manifest(types_map: dict[str, list[str]], out_path: Path, api_version: str) -> None:
    package = ET.Element(f"{{{NS}}}Package")
    for tname in sorted(types_map.keys()):
        types_el = ET.SubElement(package, f"{{{NS}}}types")
        for member in types_map[tname]:
            m = ET.SubElement(types_el, f"{{{NS}}}members")
            m.text = member
        n = ET.SubElement(types_el, f"{{{NS}}}name")
        n.text = tname
    ver = ET.SubElement(package, f"{{{NS}}}version")
    ver.text = api_version
    tree = ET.ElementTree(package)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(out_path, encoding="UTF-8", xml_declaration=True)
    print(f"Wrote {out_path} ({len(types_map)} types)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--output-dir", default="manifest/batches")
    ap.add_argument("--api-version", default="65.0")
    args = ap.parse_args()

    all_types = parse_types(Path(args.manifest))
    assigned = set()
    out_dir = Path(args.output_dir)

    for group_name, type_names in GROUPS.items():
        if group_name == "08-other":
            continue
        subset = {t: all_types[t] for t in type_names if t in all_types}
        assigned.update(subset.keys())
        if subset:
            write_manifest(subset, out_dir / f"{group_name}.xml", args.api_version)

    remaining = {t: m for t, m in all_types.items() if t not in assigned}
    if remaining:
        write_manifest(remaining, out_dir / "08-other.xml", args.api_version)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
