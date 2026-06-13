#!/usr/bin/env python3
"""Build the static JSON used by the RCT Bench website.

The project intentionally keeps this dependency-free so the site can be
rebuilt in a plain Python environment from the public Excel workbooks.
"""

from __future__ import annotations

import csv
import json
import re
import statistics
import zipfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "website" / "assets" / "site-data.json"
NS = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def column_index(cell_ref: str) -> int:
    letters = "".join(ch for ch in cell_ref if ch.isalpha())
    index = 0
    for char in letters:
        index = index * 26 + ord(char.upper()) - 64
    return index - 1


def shared_strings(zf: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    values: list[str] = []
    for item in root.findall("a:si", NS):
        values.append("".join(text.text or "" for text in item.findall(".//a:t", NS)))
    return values


def read_xlsx_sheet(path: Path, sheet_path: str = "xl/worksheets/sheet1.xml") -> list[list[str]]:
    with zipfile.ZipFile(path) as zf:
        shared = shared_strings(zf)
        root = ET.fromstring(zf.read(sheet_path))

    rows: list[list[str]] = []
    for row in root.findall(".//a:sheetData/a:row", NS):
        values: list[str] = []
        for cell in row.findall("a:c", NS):
            index = column_index(cell.attrib.get("r", ""))
            while len(values) <= index:
                values.append("")

            cell_type = cell.attrib.get("t")
            value = cell.find("a:v", NS)
            inline = cell.find("a:is", NS)
            if cell_type == "s" and value is not None and value.text is not None:
                text = shared[int(value.text)]
            elif cell_type == "inlineStr" and inline is not None:
                text = "".join(node.text or "" for node in inline.findall(".//a:t", NS))
            elif value is not None:
                text = value.text or ""
            else:
                text = ""
            values[index] = clean_text(text)
        rows.append(values)
    return rows


def clean_text(value: Any) -> str:
    text = "" if value is None else str(value)
    return re.sub(r"\s+", " ", text).strip()


def int_or_none(value: str) -> int | None:
    value = clean_text(value)
    if not value:
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def metadata_rows() -> list[dict[str, str]]:
    rows = read_xlsx_sheet(ROOT / "meta_data.xlsx")
    header = rows[0]
    return [dict(zip(header, row + [""] * (len(header) - len(row)))) for row in rows[1:]]


def dictionary_summary() -> dict[int, dict[str, Any]]:
    rows = read_xlsx_sheet(ROOT / "data-dictionary.xlsx")
    header = rows[0]
    summary: dict[int, dict[str, Any]] = {}

    for row in rows[1:]:
        item = dict(zip(header, row + [""] * (len(header) - len(row))))
        trial_id = int_or_none(item.get("Trial_ID", ""))
        if trial_id is None:
            continue
        bucket = summary.setdefault(
            trial_id,
            {
                "variables": 0,
                "primaryOutcomes": 0,
                "secondaryOutcomes": 0,
                "covariates": 0,
                "treatmentLevels": "",
                "roles": Counter(),
                "sampleSize": int_or_none(item.get("n_rows", "")),
            },
        )
        name = item.get("variable_name", "")
        role = item.get("variable_role", "")
        bucket["variables"] += 1
        bucket["roles"][role] += 1
        if name.startswith("YP_"):
            bucket["primaryOutcomes"] += 1
        elif name.startswith("YS_"):
            bucket["secondaryOutcomes"] += 1
        elif name.startswith("X_"):
            bucket["covariates"] += 1
        if name == "Treatment":
            bucket["treatmentLevels"] = item.get("levels_or_range", "")
            bucket["sampleSize"] = int_or_none(item.get("n_rows", "")) or bucket["sampleSize"]

    for bucket in summary.values():
        bucket["roles"] = dict(bucket["roles"])
    return summary


def csv_shape(trial_id: int) -> dict[str, int | None]:
    path = ROOT / "cleaned_data" / f"trial{trial_id}.csv"
    if not path.exists():
        return {"rows": None, "columns": None}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            return {"rows": 0, "columns": 0}
        return {"rows": sum(1 for _ in reader), "columns": len(header)}


def build() -> dict[str, Any]:
    dictionary = dictionary_summary()
    trials: list[dict[str, Any]] = []
    research_areas: Counter[str] = Counter()
    publication_years: list[int] = []
    sample_sizes: list[int] = []

    for row in metadata_rows():
        trial_id = int_or_none(row.get("Trial_ID", ""))
        if trial_id is None:
            continue
        shape = csv_shape(trial_id)
        summary = dictionary.get(trial_id, {})
        sample_size = int_or_none(row.get("Sample Size", "")) or shape["rows"]
        publication_year = int_or_none(row.get("Publication Year", ""))
        research_area = row.get("Research Area", "")
        if research_area:
            research_areas[research_area] += 1
        if publication_year is not None:
            publication_years.append(publication_year)
        if isinstance(sample_size, int):
            sample_sizes.append(sample_size)

        trials.append(
            {
                "id": trial_id,
                "trialId": f"trial{trial_id}",
                "registry": row.get("Trial Number/Name", ""),
                "paperName": row.get("Paper Name", ""),
                "journal": row.get("Journal", ""),
                "paperLink": row.get("Paper Link", ""),
                "publicationYear": publication_year,
                "arms": int_or_none(row.get("# of Arm", "")),
                "controlGroup": row.get("Control Group", ""),
                "studyPhase": row.get("Study Phase", ""),
                "sampleSize": sample_size,
                "primaryOutcome": row.get("Priamry Outcome", ""),
                "primaryOutcomeType": row.get("Primary Outcome Type", ""),
                "trialSuccess": row.get("Trial Success(Primary Outcome Significant)", ""),
                "statisticalModel": row.get("Statistical Model", ""),
                "randomizationScheme": row.get("Randomization Scheme", ""),
                "randomizationHighLevel": row.get("Randomization Scheme(High Level)", ""),
                "researchArea": research_area,
                "textData": row.get("Text Data", ""),
                "citation": int_or_none(row.get("Citation", "")),
                "rows": shape["rows"],
                "columns": shape["columns"],
                "variables": summary.get("variables", shape["columns"]),
                "primaryOutcomes": summary.get("primaryOutcomes", 0),
                "secondaryOutcomes": summary.get("secondaryOutcomes", 0),
                "covariates": summary.get("covariates", 0),
                "treatmentLevels": summary.get("treatmentLevels", ""),
                "csvPath": f"../cleaned_data/trial{trial_id}.csv",
                "rdsPath": f"../cleaned_data/trial{trial_id}.rds",
            }
        )

    year_min = min(publication_years) if publication_years else None
    year_max = max(publication_years) if publication_years else None
    median_sample_size = int(statistics.median(sample_sizes)) if sample_sizes else None

    return {
        "generatedFrom": ["meta_data.xlsx", "data-dictionary.xlsx", "cleaned_data/*.csv"],
        "workbooks": {
            "metadata": "../meta_data.xlsx",
            "dictionary": "../data-dictionary.xlsx",
        },
        "summary": {
            "trialCount": len(trials),
            "participantRows": sum(t["rows"] or 0 for t in trials),
            "variableCount": sum(t["columns"] or 0 for t in trials),
            "researchAreaCount": len(research_areas),
            "yearMin": year_min,
            "yearMax": year_max,
            "medianSampleSize": median_sample_size,
            "topResearchAreas": research_areas.most_common(8),
        },
        "trials": trials,
    }


def main() -> None:
    data = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)} with {len(data['trials'])} trials")


if __name__ == "__main__":
    main()
