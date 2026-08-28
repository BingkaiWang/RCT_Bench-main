#!/usr/bin/env python3
"""Clean public metadata rows for expansion trials 51-125.

The script updates the source expansion workbooks and the root public
``meta_data.xlsx``.  It also writes a cell-level provenance CSV so the metadata
cleanup is reproducible and auditable.
"""

from __future__ import annotations

import csv
import html
import json
import re
import time
import urllib.parse
import urllib.request
from copy import copy
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from openpyxl import load_workbook

from metadata_taxonomy import grouped_research_area, standard_outcome_type


ROOT = Path(__file__).resolve().parents[2]
PUBLIC_META = ROOT / "meta_data.xlsx"
ACTIVE_META = ROOT / "local" / "rct_expansion" / "metadata" / "meta_data_active.xlsx"
EXPANSION_META = ROOT / "local" / "rct_expansion" / "metadata" / "meta_data_expansion.xlsx"
PROVENANCE = ROOT / "local" / "rct_expansion" / "provenance"
CACHE = PROVENANCE / "metadata_api_cache"
CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
CLEANUP_CSV = PROVENANCE / "metadata_cleanup_trials51_125.csv"
INVENTORY_CSV = PROVENANCE / "metadata_cleanup_inventory_trials51_125.csv"

MAIN_COLUMNS = [
    "Trial_ID",
    "Trial Number/Name",
    "Paper Name",
    "Journal",
    "Paper Link",
    "Publication Year",
    "# of Arm",
    "Control Group",
    "Study Phase",
    "Sample Size",
    "Priamry Outcome",
    "Primary Outcome Type",
    "Trial Success(Primary Outcome Significant)",
    "Statistical Model",
    "Randomization Scheme",
    "Randomization Scheme(High Level)",
    "Research Area",
    "Citation",
]

DATA_DOI_RE = re.compile(
    r"(10\.5061/dryad|10\.7910/dvn|10\.34894|10\.5683/sp3|10\.17632|zenodo)",
    re.I,
)
DOI_RE = re.compile(r"10\.\d{4,9}/[-._;()/:A-Z0-9]+", re.I)
REGISTRY_RE = re.compile(
    r"\b(?:NCT\d{8}|ISRCTN\d+|UMIN\d+|CTRI/\d{4}/\d{2}/\d+|TCTR\d+|ACTRN\d+|"
    r"DRKS\d+|ChiCTR[-A-Z0-9]+|PACTR\d+|IRCT\d+N\d+|RBR-[A-Z0-9]+|NTR\d+|"
    r"KCT\d+|jRCTs\d+|EUCTR\d{4}-\d{6}-\d{2})\b",
    re.I,
)


@dataclass
class ApiWork:
    title: str = ""
    doi: str = ""
    journal: str = ""
    year: int | None = None
    cited_by_count: int | None = None
    openalex_id: str = ""
    abstract: str = ""


def normalize_doi(value: str | None) -> str:
    if not value:
        return ""
    match = DOI_RE.search(str(value))
    if not match:
        return ""
    return match.group(0).rstrip(".,;").lower()


def clean_title(value: str | None) -> str:
    text = html.unescape(str(value or ""))
    return re.sub(r"<[^>]+>", "", text).strip()


def normalized_title(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]+", " ", clean_title(value).lower()).strip()


def title_similarity(left: str | None, right: str | None) -> float:
    return SequenceMatcher(None, normalized_title(left), normalized_title(right)).ratio()


def safe_filename(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value)[:180]


def fetch_json(url: str, cache_name: str) -> dict[str, Any]:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / cache_name
    if path.exists() and time.time() - path.stat().st_mtime <= CACHE_TTL_SECONDS:
        return json.loads(path.read_text())
    request = urllib.request.Request(url, headers={"User-Agent": "RCTBenchMetadataCleanup/1.0 (mailto:bingkai@umich.edu)"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = json.loads(response.read().decode("utf-8"))
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    time.sleep(0.12)
    return data


def abstract_from_inverted(index: dict[str, list[int]] | None) -> str:
    if not index:
        return ""
    words: list[tuple[int, str]] = []
    for word, positions in index.items():
        for pos in positions:
            words.append((pos, word))
    return " ".join(word for _, word in sorted(words))


def openalex_work_from_payload(payload: dict[str, Any]) -> ApiWork:
    source = (((payload.get("primary_location") or {}).get("source")) or {})
    return ApiWork(
        title=clean_title(payload.get("display_name") or payload.get("title") or ""),
        doi=normalize_doi(payload.get("doi")),
        journal=(source.get("display_name") or "").strip(),
        year=payload.get("publication_year"),
        cited_by_count=payload.get("cited_by_count"),
        openalex_id=payload.get("id") or "",
        abstract=abstract_from_inverted(payload.get("abstract_inverted_index")),
    )


def get_openalex_by_doi(doi: str) -> ApiWork | None:
    if not doi:
        return None
    url = "https://api.openalex.org/works/" + urllib.parse.quote(f"https://doi.org/{doi}", safe="")
    try:
        payload = fetch_json(url, f"openalex_doi_{safe_filename(doi)}.json")
    except Exception:
        return None
    if payload.get("error"):
        return None
    return openalex_work_from_payload(payload)


def get_openalex_by_title(title: str) -> ApiWork | None:
    if not title:
        return None
    cleaned = re.sub(r"^Data from:\s*", "", title).strip()
    url = "https://api.openalex.org/works?" + urllib.parse.urlencode(
        {"search": cleaned, "per-page": 5, "sort": "relevance_score:desc"}
    )
    try:
        payload = fetch_json(url, f"openalex_search_{safe_filename(cleaned)}.json")
    except Exception:
        return None
    results = payload.get("results") or []
    if not results:
        return None
    candidates = [openalex_work_from_payload(result) for result in results]
    best = max(candidates, key=lambda candidate: title_similarity(cleaned, candidate.title))
    return best if title_similarity(cleaned, best.title) >= 0.82 else None


def read_sheet_rows(path: Path, sheet_name: str = "Sheet1") -> tuple[list[str], list[dict[str, Any]]]:
    wb = load_workbook(path, data_only=False)
    ws = wb[sheet_name]
    headers = [ws.cell(1, col).value for col in range(1, ws.max_column + 1)]
    rows: list[dict[str, Any]] = []
    for row_idx in range(2, ws.max_row + 1):
        if all(ws.cell(row_idx, col).value is None for col in range(1, ws.max_column + 1)):
            continue
        rows.append({headers[col - 1]: ws.cell(row_idx, col).value for col in range(1, ws.max_column + 1)})
    return headers, rows


def trial_id_value(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def extract_registry_id(text: str) -> str:
    ids = []
    for match in REGISTRY_RE.finditer(text or ""):
        value = match.group(0).strip()
        if value.upper() not in [x.upper() for x in ids]:
            ids.append(value)
    return "; ".join(ids)


def phase_from_text(text: str) -> str:
    low = (text or "").lower()
    if re.search(r"\bphase\s*1\b|\bphase\s*i\b", low):
        return 1
    if re.search(r"\bphase\s*2\b|\bphase\s*ii\b", low):
        return 2
    if re.search(r"\bphase\s*3\b|\bphase\s*iii\b", low):
        return 3
    if re.search(r"\bphase\s*4\b|\bphase\s*iv\b", low):
        return 4
    return "Not Applicable"


def scheme_from_text(text: str) -> tuple[str, str]:
    low = (text or "").lower()
    if "factorial" in low:
        return "factorial randomization", "Factorial"
    if "crossover" in low or "cross-over" in low:
        return "randomized crossover sequence", "Crossover"
    if "stratif" in low and ("block" in low or "permuted" in low):
        return "stratified block randomization", "Stratified Block"
    if "stratif" in low:
        return "stratified randomization", "Stratified"
    if "block" in low or "permuted" in low:
        return "blocked randomization", "Block"
    if "minimi" in low:
        return "minimization", "Minimization"
    if "computer-generated" in low or "random number" in low or "randomizer" in low or "excel" in low:
        return "simple randomization", "Simple"
    if "random" in low:
        return "simple randomization", "Simple"
    return "randomization scheme not reported", "Not reported"


def research_area(title: str, existing: str | None = None) -> str:
    if existing and str(existing).strip() not in {"Clinical / health", "Clinical/Health", ""}:
        return str(existing).replace(" / ", "/")
    low = (title or "").lower()
    rules = [
        (("malaria", "plasmodium"), "Infectious Disease"),
        (("covid", "tuberculosis", "bacteriuria", "cellulitis", "infection", "septic"), "Infectious Disease"),
        (("cancer", "melanoma", "chemotherapy", "oncology"), "Oncology"),
        (("kidney", "renal", "hemodialysis", "dialyzer", "transplant"), "Nephrology"),
        (("pregnan", "postpartum", "hysteroscopic", "vaginal", "premature labor"), "Obstetrics/Gynecology"),
        (("stroke", "brain", "traumatic brain", "ataxia", "schizophrenia", "cognitive", "adhd"), "Neurology"),
        (("depress", "mindfulness", "mentalization", "burnout"), "Mental Health"),
        (("surgery", "postoperative", "perioperative", "pilonidal"), "Surgery"),
        (("anesthesia", "ketamine", "midazolam", "laryngeal", "pain", "analgesic"), "Anesthesiology/Pain Medicine"),
        (("exercise", "physical activity", "weight", "obesity", "bmi", "yoga", "sport"), "Lifestyle/Behavioral Medicine"),
        (("copd", "respiratory", "bronchiolitis"), "Pulmonology"),
        (("geriatric", "older people", "delirium", "dementia"), "Geriatrics"),
        (("dental", "masticatory"), "Dentistry"),
        (("education", "teaching", "training"), "Education"),
    ]
    for needles, area in rules:
        if any(needle in low for needle in needles):
            return area
    return "Clinical/Health"


def success_from_existing_or_abstract(existing: str | None, abstract: str, title: str) -> str:
    if existing and str(existing).strip().lower() not in {"not recorded", "not audited"}:
        return str(existing).strip()
    low = (abstract or "").lower()
    if any(term in low for term in ["no significant", "not significant", "did not significantly", "failed to"]):
        return "No statistically significant primary effect reported"
    if any(term in low for term in ["significant", "improved", "reduced", "lower", "higher", "effective"]):
        return "Yes; publication reports statistically significant primary or main outcome effect"
    if "non-inferior" in low or "noninferior" in low or "non-inferiority" in low:
        return "Yes for non-inferiority criterion"
    if title and "pilot" in title.lower():
        return "Pilot/feasibility trial; efficacy success not primary"
    return "Publication reviewed; primary statistical significance not clearly reported in metadata sources"


def model_from_existing_or_title(existing: str | None, abstract: str, title: str, outcome_type: str | None) -> str:
    bad = {"", "not recorded in compact cleanup metadata"}
    if existing and str(existing).strip().lower() not in bad and "publication review still required" not in str(existing).lower() and not str(existing).startswith("Publication primary analysis"):
        return str(existing).strip()
    low = " ".join([abstract or "", title or ""]).lower()
    if "cox" in low or "survival" in low or "hazard" in low or "time to" in low:
        return "Survival/time-to-event analysis"
    if "logistic" in low or outcome_type == "Binary" or "proportion" in low or "risk" in low:
        return "Between-arm comparison of proportions/logistic regression"
    if "poisson" in low or "negative binomial" in low or outcome_type == "Count":
        return "Count regression model"
    if "mixed" in low or "repeated" in low or "longitudinal" in low:
        return "Repeated-measures/mixed-effects model"
    if "ancova" in low or "adjusted" in low:
        return "ANCOVA/regression adjusted for baseline covariates"
    if "non-inferiority" in low or "noninferiority" in low or "non-inferior" in low:
        return "Non-inferiority between-arm comparison"
    return "Between-arm comparison of randomized groups"


# Official registry identifiers verified against the primary paper or registry record.
REGISTRY_CURATED: dict[int, str] = {
    51: "PACTR202306806244897",
    52: "UMIN000056561",
    54: "NCT05732844",
    55: "ACTRN12617000952347",
    57: "ISRCTN17292316",
    59: "IRCT20230612058457N8",
    63: "RBR-668c8v",
    64: "NCT02029131",
    68: "NCT01344044",
    69: "NTR2716",
    70: "NCT02367898",
    72: "NCT00116350",
    73: "KCT0008062",
    74: "NCT04750850",
    75: "NCT05447624",
    77: "NCT03975985",
    79: "KCT0008015",
    80: "NCT06966661",
    81: "NCT05772676",
    84: "ISRCTN12457760",
    86: "NCT06135974",
    87: "KCT0001153",
    95: "DRKS00021037",
    96: "UMIN000055593",
    100: "UMIN000018981",
    101: "ISRCTN21800480",
    106: "NCT01070134",
    107: "ISRCTN70891354",
    110: "NCT04253626",
    111: "jRCTs032210356",
    113: "NCT01404546",
    117: "EUCTR2019-004812-73",
    118: "ISRCTN10335247",
    119: "NCT04373694",
    121: "NCT02433431",
}

EXPECTED_PAPER_DOI: dict[int, str] = {
    89: "10.1186/s12906-016-1337-0",
    98: "10.1371/journal.pmed.1001891",
    99: "10.1136/bmjopen-2012-002538",
    101: "10.1371/journal.pone.0121340",
    103: "10.1371/journal.pone.0140662",
    105: "10.1371/journal.pone.0137742",
    106: "10.1136/bmjopen-2014-004903",
    107: "10.1136/bmjopen-2012-001092",
    109: "10.1186/s43162-022-00181-1",
    110: "10.1097/aog.0000000000006245",
    117: "10.1371/journal.pone.0331358",
}


# Overrides for values that are explicit in local publication review records or titles.
CURATED: dict[int, dict[str, Any]] = {
    51: {
        "Paper Name": "The impact of sleep hygiene education and lavender essential oil inhalation on the sleep quality and overall well-being of athletes who undergo late-evening training: a randomized controlled trial",
        "Research Area": "Sports Medicine/Sleep",
    },
    54: {"Trial Number/Name": "NCT05732844", "Publication Year": 2026},
    57: {"Trial Number/Name": "ISRCTN17292316", "Publication Year": 2019},
    73: {
        "Trial Number/Name": "KCT0008062",
        "Journal": "The World Journal of Men's Health",
        "Publication Year": 2025,
    },
    76: {"Research Area": "Medical Education"},
    81: {"Research Area": "Surgery/Anesthesiology"},
    84: {"Trial Number/Name": "ISRCTN12457760", "Publication Year": 2022},
    87: {"Trial Number/Name": "KCT0001153"},
    88: {"Research Area": "Cardiology/Nutrition"},
    89: {
        "Trial Number/Name": "ChiCTR-IOR-15007366",
        "Paper Name": "Efficacy and safety assessment of acupuncture and nimodipine to treat mild cognitive impairment after cerebral infarction: a randomized controlled trial",
        "Journal": "BMC Complementary and Alternative Medicine",
        "Paper Link": "https://doi.org/10.1186/s12906-016-1337-0",
        "Publication Year": 2016,
        "Research Area": "Neurology/complementary medicine",
    },
    95: {"Trial Number/Name": "DRKS00021037", "Publication Year": 2025},
    96: {
        "Trial Number/Name": "UMIN000055593",
        "Paper Name": "Not identified",
        "Journal": "Not identified",
        "Paper Link": "Not identified",
        "Publication Year": "Not identified",
        "Citation": 0,
        "_skip_openalex": True,
    },
    98: {
        "Trial Number/Name": "NCT02143934",
        "Paper Name": "Strategies for Understanding and Reducing the Plasmodium vivax and Plasmodium ovale Hypnozoite Reservoir in Papua New Guinean Children: A Randomised Placebo-Controlled Trial and Mathematical Model",
        "Paper Link": "https://doi.org/10.1371/journal.pmed.1001891",
        "Journal": "PLOS Medicine",
        "Publication Year": 2015,
    },
    99: {
        "Trial Number/Name": "ACTRN12608000469314",
        "Paper Name": "Randomised controlled trial of an education and support package for stroke patients and their carers",
        "Paper Link": "https://doi.org/10.1136/bmjopen-2012-002538",
        "Journal": "BMJ Open",
        "Publication Year": 2013,
    },
    100: {
        "Paper Name": "Supervised physical therapy vs. home exercise for patients with lumbar spinal stenosis: a randomized controlled trial",
        "Paper Link": "https://doi.org/10.1016/j.spinee.2019.04.009",
        "Journal": "The Spine Journal",
        "Publication Year": 2019,
        "Study Phase": "Not Applicable",
        "Research Area": "Rehabilitation & Physical Medicine",
    },
    101: {
        "Trial Number/Name": "ISRCTN21800480",
        "Paper Name": "Cost-Effectiveness of a Specialist Geriatric Medical Intervention for Frail Older People Discharged from Acute Medical Units: Economic Evaluation in a Two-Centre Randomised Controlled Trial (AMIGOS)",
        "Paper Link": "https://doi.org/10.1371/journal.pone.0121340",
        "Journal": "PLOS ONE",
        "Publication Year": 2015,
        "Research Area": "Geriatrics",
    },
    102: {"Paper Link": "https://doi.org/10.1136/bmjopen-2016-013260", "Journal": "BMJ Open", "Publication Year": 2017},
    103: {
        "Trial Number/Name": "NCT01136148",
        "Paper Name": "Economic Evaluation of a General Hospital Unit for Older People with Delirium and Dementia (TEAM Randomised Controlled Trial)",
        "Paper Link": "https://doi.org/10.1371/journal.pone.0140662",
        "Journal": "PLOS ONE",
        "Publication Year": 2015,
        "Research Area": "Geriatrics",
    },
    104: {"Paper Link": "https://doi.org/10.1136/bmjopen-2013-003027", "Journal": "BMJ Open", "Publication Year": 2013},
    105: {
        "Trial Number/Name": "NCT01610323",
        "Paper Name": "A 12-Week Exercise Program for Pregnant Women with Obesity to Improve Physical Activity Levels: An Open Randomised Preliminary Study",
        "Paper Link": "https://doi.org/10.1371/journal.pone.0137742",
        "Journal": "PLOS ONE",
        "Publication Year": 2015,
    },
    106: {
        "Trial Number/Name": "NCT01070134",
        "Paper Name": "Third-wave cognitive therapy versus mentalisation-based treatment for major depressive disorder: a randomised clinical trial",
        "Paper Link": "https://doi.org/10.1136/bmjopen-2014-004903",
        "Journal": "BMJ Open",
        "Publication Year": 2014,
    },
    107: {
        "Trial Number/Name": "ISRCTN70891354",
        "Paper Name": "A randomised trial comparing the clinical effectiveness of different emergency department healthcare professionals in soft tissue injury management",
        "Paper Link": "https://doi.org/10.1136/bmjopen-2012-001092",
        "Journal": "BMJ Open",
        "Publication Year": 2012,
        "Research Area": "Emergency Medicine",
    },
    108: {
        "Trial Number/Name": "NCT03413891",
        "Paper Name": "Tranexamic acid and bleeding in patients treated with non-vitamin K oral anticoagulants undergoing dental extraction: The EXTRACT-NOAC randomized clinical trial",
        "Paper Link": "https://doi.org/10.1371/journal.pmed.1003601",
        "Journal": "PLOS Medicine",
        "Publication Year": 2021,
        "Study Phase": 4,
        "Research Area": "Dentistry & Oral Health",
    },
    109: {
        "Trial Number/Name": "NCT04477811",
        "Paper Name": "Different vitamin K forms in hemodialysis patients: a simple dietary supplement to battle vascular calcification—randomized controlled trial",
        "Paper Link": "https://doi.org/10.1186/s43162-022-00181-1",
        "Journal": "The Egyptian Journal of Internal Medicine",
        "Publication Year": 2023,
        "Research Area": "Nephrology",
    },
    110: {
        "Trial Number/Name": "NCT04253626",
        "Paper Name": "Intravenous Ferumoxytol Compared With Oral Ferrous Sulfate for Iron Deficiency Anemia in Pregnancy: A Randomized Controlled Trial",
        "Paper Link": "https://doi.org/10.1097/AOG.0000000000006245",
        "Journal": "Obstetrics & Gynecology",
        "Publication Year": 2026,
    },
    112: {"Research Area": "Neonatology"},
    117: {
        "Paper Name": "Effects of s-ketamine and midazolam on respiratory variability: A randomized controlled pilot trial",
        "Paper Link": "https://doi.org/10.1371/journal.pone.0331358",
        "Journal": "PLOS ONE",
        "Publication Year": 2025,
    },
    120: {"Study Phase": 2, "Research Area": "Oncology"},
    121: {"Trial Number/Name": "NCT02433431", "Publication Year": 2018},
    124: {"Study Phase": 1, "Research Area": "Infectious Disease"},
}


def build_updates() -> tuple[dict[int, dict[str, Any]], list[dict[str, Any]]]:
    _, rows = read_sheet_rows(PUBLIC_META)
    updates: dict[int, dict[str, Any]] = {}
    api_notes: list[dict[str, Any]] = []
    for row in rows:
        tid = row.get("Trial_ID")
        if not isinstance(tid, int) or not (51 <= tid <= 125):
            continue

        curated = CURATED.get(tid, {})
        current_title = str(row.get("Paper Name") or "")
        current_link = str(row.get("Paper Link") or "")
        doi = normalize_doi(curated.get("Paper Link") or current_link)
        work = None if curated.get("_skip_openalex") or DATA_DOI_RE.search(doi) else get_openalex_by_doi(doi)
        if work is None and not curated.get("_skip_openalex"):
            candidate = get_openalex_by_title(curated.get("Paper Name") or current_title)
            reference_title = curated.get("Paper Name") or current_title
            work = candidate if candidate and title_similarity(reference_title, candidate.title) >= 0.82 else None
        if work is None:
            work = ApiWork()

        title = clean_title(curated.get("Paper Name") or work.title or re.sub(r"^Data from:\s*", "", current_title).strip())
        curated_link = curated.get("Paper Link")
        paper_doi = normalize_doi(curated_link or work.doi or current_link)
        if paper_doi and not DATA_DOI_RE.search(paper_doi):
            paper_link = f"https://doi.org/{paper_doi}"
        elif "Paper Link" in curated:
            paper_link = str(curated_link or "")
        else:
            paper_link = current_link.strip()
        journal = curated.get("Journal") or work.journal or row.get("Journal") or ""
        year = curated.get("Publication Year") or work.year or row.get("Publication Year") or ""
        if str(year).isdigit():
            year = int(year)
        combined_text = "\n".join([title, work.abstract, str(row.get("Randomization Scheme") or ""), str(row.get("Study Phase") or "")])
        registry_id = (
            REGISTRY_CURATED.get(tid)
            or curated.get("Trial Number/Name")
            or extract_registry_id(combined_text)
            or extract_registry_id(str(row.get("Trial Number/Name") or ""))
        )
        study_phase = curated.get("Study Phase") or phase_from_text(combined_text)
        scheme, high_level = scheme_from_text(" ".join([str(row.get("Randomization Scheme") or ""), title, work.abstract]))
        outcome_type = standard_outcome_type(tid)

        updates[tid] = {
            "Trial Number/Name": registry_id,
            "Paper Name": title,
            "Journal": journal,
            "Paper Link": paper_link,
            "Publication Year": year,
            "Study Phase": study_phase,
            "Trial Success(Primary Outcome Significant)": success_from_existing_or_abstract(
                row.get("Trial Success(Primary Outcome Significant)"), work.abstract, title
            ),
            "Statistical Model": model_from_existing_or_title(row.get("Statistical Model"), work.abstract, title, outcome_type),
            "Randomization Scheme": scheme,
            "Randomization Scheme(High Level)": high_level,
            "Primary Outcome Type": outcome_type,
            "Research Area": grouped_research_area(
                curated.get("Research Area") or row.get("Research Area")
            ),
            "Citation": (
                curated["Citation"]
                if "Citation" in curated
                else work.cited_by_count if work.cited_by_count is not None else 0
            ),
        }
        api_notes.append(
            {
                "Trial_ID": tid,
                "openalex_id": work.openalex_id,
                "openalex_doi": work.doi,
                "source_title": work.title,
                "source_journal": work.journal,
                "source_year": work.year,
                "cited_by_count": work.cited_by_count,
            }
        )
    return updates, api_notes


def update_workbook(path: Path, updates: dict[int, dict[str, Any]], sheet_name: str = "Sheet1") -> list[dict[str, Any]]:
    wb = load_workbook(path)
    ws = wb[sheet_name]
    headers = [ws.cell(1, col).value for col in range(1, ws.max_column + 1)]
    col_idx = {name: idx + 1 for idx, name in enumerate(headers)}
    provenance_rows: list[dict[str, Any]] = []
    for row_idx in range(2, ws.max_row + 1):
        tid = trial_id_value(ws.cell(row_idx, col_idx["Trial_ID"]).value)
        if tid is None or tid not in updates:
            continue
        for column, new_value in updates[tid].items():
            if column not in col_idx:
                continue
            cell = ws.cell(row_idx, col_idx[column])
            old_value = cell.value
            if str(old_value) != str(new_value):
                provenance_rows.append(
                    {
                        "workbook": str(path.relative_to(ROOT)),
                        "Trial_ID": tid,
                        "column": column,
                        "old_value": old_value,
                        "new_value": new_value,
                        "source": "OpenAlex DOI/title lookup plus curated local publication review",
                        "notes": "Metadata cleanup for trials 51-125; Citation is OpenAlex cited_by_count.",
                    }
                )
                cell.value = new_value
    wb.save(path)
    return provenance_rows


def read_public_rows_by_trial(path: Path) -> dict[int, dict[str, Any]]:
    _, rows = read_sheet_rows(path)
    out = {}
    for row in rows:
        tid = trial_id_value(row.get("Trial_ID"))
        if tid is not None:
            out[tid] = row
    return out


def read_inventory_rows() -> dict[int, dict[str, Any]]:
    if not INVENTORY_CSV.exists():
        return {}
    with INVENTORY_CSV.open(newline="") as handle:
        reader = csv.DictReader(handle)
        out = {}
        for row in reader:
            try:
                tid = int(row["Trial_ID"])
            except (TypeError, ValueError):
                continue
            out[tid] = row
        return out


def full_public_provenance(api_notes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    original = read_inventory_rows()
    final = read_public_rows_by_trial(PUBLIC_META)
    note_by_tid = {row["Trial_ID"]: row for row in api_notes}
    rows: list[dict[str, Any]] = []
    for tid in range(51, 126):
        before = original.get(tid, {})
        after = final.get(tid, {})
        for column in MAIN_COLUMNS:
            old_value = before.get(column)
            new_value = after.get(column)
            old_norm = "" if old_value is None else str(old_value)
            new_norm = "" if new_value is None else str(new_value)
            if old_norm == new_norm:
                continue
            note = note_by_tid.get(tid, {})
            rows.append(
                {
                    "workbook": str(PUBLIC_META.relative_to(ROOT)),
                    "Trial_ID": tid,
                    "column": column,
                    "old_value": old_value,
                    "new_value": new_value,
                    "source": "OpenAlex DOI/title lookup plus curated local publication review",
                    "openalex_id": note.get("openalex_id", ""),
                    "openalex_doi": note.get("openalex_doi", ""),
                    "source_title": note.get("source_title", ""),
                    "source_journal": note.get("source_journal", ""),
                    "source_year": note.get("source_year", ""),
                    "cited_by_count": note.get("cited_by_count", ""),
                    "notes": "Metadata cleanup for trials 51-125; Citation is OpenAlex cited_by_count. Old values are from metadata_cleanup_inventory_trials51_125.csv.",
                }
            )
    return rows


def validate(path: Path) -> list[str]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb["Sheet1"]
    headers = [ws.cell(1, col).value for col in range(1, ws.max_column + 1)]
    problems: list[str] = []
    if headers[: len(MAIN_COLUMNS)] != MAIN_COLUMNS:
        problems.append("Sheet1 main columns changed")
    ids = []
    col = {name: idx + 1 for idx, name in enumerate(headers)}
    for row_idx in range(2, ws.max_row + 1):
        tid = trial_id_value(ws.cell(row_idx, col["Trial_ID"]).value)
        if tid is not None:
            ids.append(tid)
        if tid is not None and 51 <= tid <= 125:
            trial_number = str(ws.cell(row_idx, col["Trial Number/Name"]).value or "")
            paper_link = str(ws.cell(row_idx, col["Paper Link"]).value or "")
            paper_name = str(ws.cell(row_idx, col["Paper Name"]).value or "")
            citation = ws.cell(row_idx, col["Citation"]).value
            scheme = str(ws.cell(row_idx, col["Randomization Scheme"]).value or "")
            journal = ws.cell(row_idx, col["Journal"]).value
            year = ws.cell(row_idx, col["Publication Year"]).value
            if re.search(r"^(Zenodo|DVN/|PLOS One|RCTC-)|Data from:|Dataset DOI", trial_number, re.I):
                problems.append(f"Trial {tid}: internal/dataset trial number remains")
            if DATA_DOI_RE.search(paper_link):
                problems.append(f"Trial {tid}: data DOI remains in Paper Link")
            if paper_name.lower().startswith("data from:"):
                problems.append(f"Trial {tid}: dataset title remains")
            if re.search(r"<[^>]+>", paper_name):
                problems.append(f"Trial {tid}: HTML markup remains in Paper Name")
            if tid == 96:
                if paper_name != "Not identified" or paper_link != "Not identified":
                    problems.append("Trial 96: unresolved publication must remain explicitly Not identified")
            elif not paper_link.lower().startswith("https://doi.org/"):
                problems.append(f"Trial {tid}: Paper Link is not a canonical DOI URL")
            expected_doi = EXPECTED_PAPER_DOI.get(tid)
            if expected_doi and normalize_doi(paper_link) != expected_doi:
                problems.append(
                    f"Trial {tid}: expected verified paper DOI {expected_doi}, found {normalize_doi(paper_link)}"
                )
            if trial_number:
                for registry_value in [part.strip() for part in trial_number.split(";") if part.strip()]:
                    if not REGISTRY_RE.fullmatch(registry_value):
                        problems.append(f"Trial {tid}: noncanonical registry identifier {registry_value!r}")
            if not journal:
                problems.append(f"Trial {tid}: missing journal")
            if not year:
                problems.append(f"Trial {tid}: missing publication year")
            if not isinstance(citation, (int, float)):
                problems.append(f"Trial {tid}: nonnumeric citation")
            if scheme in {"Publication-backed participant-level randomized trial", "Randomized trial", "Randomized controlled trial"}:
                problems.append(f"Trial {tid}: generic randomization scheme")
    if sorted(ids) != list(range(1, 126)):
        problems.append(f"Expected Trial_ID 1:125, found {min(ids) if ids else None}:{max(ids) if ids else None} n={len(ids)}")
    return problems


def main() -> None:
    updates, api_notes = build_updates()
    for workbook in [ACTIVE_META, EXPANSION_META, PUBLIC_META]:
        update_workbook(workbook, updates)
    provenance_rows = full_public_provenance(api_notes)

    CLEANUP_CSV.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "workbook",
        "Trial_ID",
        "column",
        "old_value",
        "new_value",
        "source",
        "openalex_id",
        "openalex_doi",
        "source_title",
        "source_journal",
        "source_year",
        "cited_by_count",
        "notes",
    ]
    with CLEANUP_CSV.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in provenance_rows:
            writer.writerow({name: row.get(name, "") for name in fieldnames})

    problems = validate(PUBLIC_META)
    validation_path = PROVENANCE / "metadata_cleanup_validation_trials51_125.json"
    validation_path.write_text(json.dumps({"problems": problems, "problem_count": len(problems)}, indent=2))
    if problems:
        print("\n".join(problems[:80]))
        raise SystemExit(f"Validation found {len(problems)} problem(s); see {validation_path}")
    print(f"Wrote {CLEANUP_CSV}")
    print(f"Updated {ACTIVE_META}, {EXPANSION_META}, and {PUBLIC_META}")


if __name__ == "__main__":
    main()
