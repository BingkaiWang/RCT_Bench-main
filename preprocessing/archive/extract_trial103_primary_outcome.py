#!/usr/bin/env python3
"""Build trial103's publication-aligned participant table from its source XLSX."""

from __future__ import annotations

import csv
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "local/rct_expansion/raw_data/trial103/TEAM economic evaluation dataset.xlsx"
OUTPUT = ROOT / "local/rct_expansion/provenance/cleaned_data_quality_audit/trial103_primary_repair.csv"
MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
MISSING = {"", ".", "na", "n/a", "nan", "null", "none"}


def column_index(cell_ref: str) -> int:
    letters = re.match(r"[A-Z]+", cell_ref.upper()).group(0)
    value = 0
    for letter in letters:
        value = value * 26 + ord(letter) - 64
    return value - 1


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    return ["".join(node.text or "" for node in item.iter(f"{{{MAIN_NS}}}t")) for item in root]


def worksheet_path(archive: zipfile.ZipFile, sheet_name: str) -> str:
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    relation_id = None
    for sheet in workbook.findall(f".//{{{MAIN_NS}}}sheet"):
        if sheet.attrib.get("name") == sheet_name:
            relation_id = sheet.attrib[f"{{{REL_NS}}}id"]
            break
    if relation_id is None:
        raise ValueError(f"Sheet not found: {sheet_name}")
    relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    for relationship in relationships.findall(f"{{{PKG_REL_NS}}}Relationship"):
        if relationship.attrib.get("Id") == relation_id:
            target = relationship.attrib["Target"].lstrip("/")
            return target if target.startswith("xl/") else f"xl/{target}"
    raise ValueError(f"Worksheet relationship not found: {sheet_name}")


def cell_text(cell: ET.Element, shared: list[str]) -> str:
    cell_type = cell.attrib.get("t")
    if cell_type == "inlineStr":
        return "".join(node.text or "" for node in cell.iter(f"{{{MAIN_NS}}}t"))
    value = cell.find(f"{{{MAIN_NS}}}v")
    if value is None or value.text is None:
        return ""
    return shared[int(value.text)] if cell_type == "s" else value.text


def read_columns(path: Path, sheet_name: str, requested: list[str]) -> list[dict[str, str]]:
    with zipfile.ZipFile(path) as archive:
        shared = shared_strings(archive)
        root = ET.fromstring(archive.read(worksheet_path(archive, sheet_name)))
    rows = root.findall(f".//{{{MAIN_NS}}}sheetData/{{{MAIN_NS}}}row")
    header: dict[int, str] = {}
    for cell in rows[0].findall(f"{{{MAIN_NS}}}c"):
        header[column_index(cell.attrib["r"])] = cell_text(cell, shared)
    wanted = {index: name for index, name in header.items() if name in requested}
    missing = sorted(set(requested) - set(wanted.values()))
    if missing:
        raise ValueError(f"Missing source columns: {', '.join(missing)}")

    output: list[dict[str, str]] = []
    for row in rows[1:]:
        item = {name: "" for name in requested}
        for cell in row.findall(f"{{{MAIN_NS}}}c"):
            index = column_index(cell.attrib["r"])
            if index in wanted:
                item[wanted[index]] = cell_text(cell, shared).strip()
        output.append(item)
    return output


def number(value: str) -> float | None:
    if value.strip().lower() in MISSING:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def eq5d3l_uk(values: list[str]) -> float | None:
    levels = [number(value) for value in values]
    if any(value not in {1.0, 2.0, 3.0} for value in levels):
        return None
    coefficients = (
        (0.0, 0.069, 0.314),
        (0.0, 0.104, 0.214),
        (0.0, 0.036, 0.094),
        (0.0, 0.123, 0.386),
        (0.0, 0.071, 0.236),
    )
    decrement = sum(coefficients[position][int(level) - 1] for position, level in enumerate(levels))
    decrement += 0.081 if any(level > 1 for level in levels) else 0.0
    decrement += 0.269 if any(level == 3 for level in levels) else 0.0
    return 1.0 - decrement


def main() -> None:
    source_columns = [
        "wardtype", "age", "gender", "pi_residencecode", "pi_med_con_tot",
        "pi_npi_depress_s", "pi_eq5d_mob", "pi_eq5d_sc", "pi_eq5d_act",
        "pi_eq5d_pain", "pi_eq5d_anx", "po_status", "Days_in_study",
        "po_eq5d_mob", "po_eq5d_sc", "po_eq5d_act", "po_eq5d_pain", "po_eq5d_anx",
    ]
    source_rows = read_columns(SOURCE, "clinical data", source_columns)
    cleaned: list[dict[str, object]] = []
    for row in source_rows:
        baseline = eq5d3l_uk([row[name] for name in (
            "pi_eq5d_mob", "pi_eq5d_sc", "pi_eq5d_act", "pi_eq5d_pain", "pi_eq5d_anx"
        )])
        followup = eq5d3l_uk([row[name] for name in (
            "po_eq5d_mob", "po_eq5d_sc", "po_eq5d_act", "po_eq5d_pain", "po_eq5d_anx"
        )])
        status = row["po_status"].strip().upper()
        days = number(row["Days_in_study"])
        qaly = None
        if status == "D" and baseline is not None and days is not None:
            qaly = baseline * days / 365.0
        elif status == "A" and baseline is not None and followup is not None:
            qaly = (baseline + followup) / 2.0 * 90.0 / 365.0
        cleaned.append({
            "Treatment": "MMHU" if number(row["wardtype"]) == 0 else "Standard care",
            "YP_qaly_90d_observed": qaly,
            "YS_eq5d_utility_90d": followup,
            "YS_status_90d": "Alive" if status == "A" else "Dead" if status == "D" else "",
            "YS_days_survived_90d": 90 if status == "A" else days,
            "X_eq5d_utility_0d": baseline,
            "X_age_0d": number(row["age"]),
            "X_gender_0d": row["gender"],
            "X_residence_care_home_0d": number(row["pi_residencecode"]),
            "X_medical_condition_count_0d": number(row["pi_med_con_tot"]),
            "X_npi_depression_severity_0d": number(row["pi_npi_depress_s"]),
            "X_eq5d_pain_0d": number(row["pi_eq5d_pain"]),
        })
    if len(cleaned) != 599 or sum(row["YP_qaly_90d_observed"] is not None for row in cleaned) != 272:
        raise ValueError("Unexpected trial103 row count or observed-QALY count")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(cleaned[0]))
        writer.writeheader()
        writer.writerows(cleaned)
    print(f"Wrote {OUTPUT} ({len(cleaned)} rows; 272 observed QALYs)")


if __name__ == "__main__":
    main()
