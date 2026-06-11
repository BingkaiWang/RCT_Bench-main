import csv
import glob
import hashlib
import html
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "raw_api"
OUT_DIR = ROOT / "processed"
OUT_DIR.mkdir(parents=True, exist_ok=True)


PHRASE_LABELS = {
    "randomized_controlled_trial": "randomized controlled trial",
    "randomised_controlled_trial": "randomised controlled trial",
    "randomized_trial": "randomized trial",
    "randomised_trial": "randomised trial",
    "randomized_control_trial": "randomized control trial",
}

PUBLICATION_RELATIONS = {
    "iscitedby",
    "issupplementto",
    "isdocumentedby",
    "isreferencedby",
    "isderivedfrom",
    "ispartof",
    "isreviewedby",
}

DOI_RE = re.compile(r"\b10\.\d{4,9}/[^\s\"'<>;,)]*", re.I)
TAG_RE = re.compile(r"<[^>]+>")
SPACE_RE = re.compile(r"\s+")


def clean_text(value):
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        value = " ".join(clean_text(v) for v in value if v is not None)
    elif isinstance(value, dict):
        value = " ".join(clean_text(v) for v in value.values() if v is not None)
    else:
        value = str(value)
    value = html.unescape(TAG_RE.sub(" ", value))
    value = value.replace("\u00a0", " ")
    return SPACE_RE.sub(" ", value).strip()


def first_text(items, key="title"):
    if not items:
        return ""
    first = items[0]
    if isinstance(first, dict):
        return clean_text(first.get(key) or first.get("value") or first)
    return clean_text(first)


def norm_doi(value):
    value = clean_text(value).lower()
    value = value.replace("https://doi.org/", "").replace("http://doi.org/", "")
    value = value.replace("doi:", "")
    value = value.strip().strip(".")
    return value


def extract_dois(text):
    return sorted({norm_doi(m.group(0)) for m in DOI_RE.finditer(text or "")})


def canonical_doi(record):
    doi = norm_doi(record.get("doi"))
    related = [norm_doi(x) for x in record.get("concept_or_identical_dois", []) if x]
    if related:
        return related[0]
    if doi.startswith("10.6084/m9.figshare.") and re.search(r"\.v\d+$", doi):
        return re.sub(r"\.v\d+$", "", doi)
    return doi


def title_key(title, publisher):
    normalized = re.sub(r"[^a-z0-9]+", " ", f"{title} {publisher}".lower()).strip()
    return "title:" + hashlib.sha1(normalized.encode("utf-8")).hexdigest()


def search_phrase_from_name(path, prefix):
    stem = Path(path).stem
    middle = stem[len(prefix):]
    middle = re.sub(r"_\d+$", "", middle)
    return PHRASE_LABELS.get(middle, middle.replace("_", " "))


def datacite_records():
    files = sorted(RAW_DIR.glob("datacite_*_[0-9].json"))
    for path in files:
        phrase = search_phrase_from_name(path, "datacite_")
        with open(path, "r", encoding="utf-8") as f:
            payload = json.load(f)
        for item in payload.get("data", []):
            attr = item.get("attributes", {})
            relationships = item.get("relationships", {})
            rels = attr.get("relatedIdentifiers", []) or []
            related_ids = []
            related_pubs = []
            concept_or_identical = []
            for rel in rels:
                rid = clean_text(rel.get("relatedIdentifier"))
                if not rid:
                    continue
                rtype = clean_text(rel.get("relatedIdentifierType"))
                rrel = clean_text(rel.get("relationType"))
                resource_type = clean_text(rel.get("resourceTypeGeneral"))
                label = f"{rrel}:{rtype}:{rid}"
                related_ids.append(label)
                if rrel.lower() in {"isversionof", "isidenticalto"} and rtype.lower() == "doi":
                    concept_or_identical.append(norm_doi(rid))
                if rrel.lower() in PUBLICATION_RELATIONS:
                    related_pubs.append(label)
                elif rtype.lower() == "doi" and resource_type.lower() in {"text", "journalarticle"}:
                    related_pubs.append(label)

            descriptions = " | ".join(
                clean_text(d.get("description")) for d in attr.get("descriptions", []) or []
            )
            rights = " | ".join(
                clean_text(
                    " ".join(
                        str(x)
                        for x in [
                            r.get("rights"),
                            r.get("rightsIdentifier"),
                            r.get("rightsUri"),
                        ]
                        if x
                    )
                )
                for r in attr.get("rightsList", []) or []
            )
            creators = "; ".join(clean_text(c.get("name")) for c in attr.get("creators", []) or [])
            subjects = "; ".join(clean_text(s.get("subject")) for s in attr.get("subjects", []) or [])
            formats = "; ".join(clean_text(x) for x in attr.get("formats", []) or [])
            sizes = "; ".join(clean_text(x) for x in attr.get("sizes", []) or [])
            client = (relationships.get("client", {}).get("data") or {}).get("id", "")
            provider = (relationships.get("provider", {}).get("data") or {}).get("id", "")
            yield {
                "source_api": "DataCite",
                "source_phrase": phrase,
                "raw_record_id": clean_text(item.get("id")),
                "doi": norm_doi(attr.get("doi") or item.get("id")),
                "title": first_text(attr.get("titles")),
                "publisher": clean_text(attr.get("publisher")),
                "repository_client": clean_text(client),
                "provider": clean_text(provider),
                "url": clean_text(attr.get("url")),
                "publication_year": clean_text(attr.get("publicationYear")),
                "creators": creators,
                "subjects_keywords": subjects,
                "description": descriptions,
                "rights_license": rights,
                "formats": formats,
                "sizes": sizes,
                "file_count": "",
                "related_identifiers": " | ".join(related_ids),
                "related_publications": " | ".join(related_pubs),
                "concept_or_identical_dois": concept_or_identical,
                "dataverse_publications": "",
                "dataverse_related_material": "",
            }


def harvard_records():
    files = sorted(RAW_DIR.glob("harvard_*_[0-9].json"))
    for path in files:
        phrase = search_phrase_from_name(path, "harvard_")
        with open(path, "r", encoding="utf-8") as f:
            payload = json.load(f)
        for item in payload.get("data", {}).get("items", []) or []:
            pubs_raw = item.get("publications", []) or []
            pubs = []
            for pub in pubs_raw:
                if isinstance(pub, dict):
                    pub_text = clean_text(" ".join(str(v) for v in pub.values() if v))
                else:
                    pub_text = clean_text(pub)
                if pub_text:
                    pubs.append(pub_text)
            related_materials = item.get("relatedMaterial", []) or []
            if isinstance(related_materials, str):
                related_materials = [related_materials]
            related_material = " | ".join(clean_text(x) for x in related_materials if clean_text(x))
            description = clean_text(item.get("description"))
            related_pubs = []
            for doi in extract_dois(" | ".join(pubs + [related_material, description])):
                related_pubs.append(f"mentioned DOI:{doi}")
            if pubs:
                related_pubs.extend(f"Dataverse publication:{p}" for p in pubs[:5])
            if related_material:
                related_pubs.append(f"related material:{related_material[:500]}")
            subjects = "; ".join(clean_text(s) for s in item.get("subjects", []) or [])
            keywords = "; ".join(clean_text(k) for k in item.get("keywords", []) or [])
            authors = "; ".join(clean_text(a) for a in item.get("authors", []) or [])
            yield {
                "source_api": "Harvard Dataverse API",
                "source_phrase": phrase,
                "raw_record_id": clean_text(item.get("global_id") or item.get("url")),
                "doi": norm_doi(item.get("global_id") or ""),
                "title": clean_text(item.get("name")),
                "publisher": clean_text(item.get("publisher") or "Harvard Dataverse"),
                "repository_client": clean_text(item.get("identifier_of_dataverse")),
                "provider": "harvardu",
                "url": clean_text(item.get("url")),
                "publication_year": clean_text((item.get("published_at") or "")[:4]),
                "creators": authors,
                "subjects_keywords": "; ".join(x for x in [subjects, keywords] if x),
                "description": description,
                "rights_license": "",
                "formats": "",
                "sizes": "",
                "file_count": clean_text(item.get("fileCount")),
                "related_identifiers": related_material,
                "related_publications": " | ".join(related_pubs),
                "concept_or_identical_dois": [],
                "dataverse_publications": " | ".join(pubs),
                "dataverse_related_material": related_material,
            }


def merge_records(records):
    grouped = {}
    for record in records:
        key_doi = canonical_doi(record)
        key = f"doi:{key_doi}" if key_doi else title_key(record.get("title", ""), record.get("publisher", ""))
        if key not in grouped:
            record = dict(record)
            record["canonical_key"] = key
            record["source_apis"] = {record.pop("source_api")}
            record["search_phrases"] = {record.pop("source_phrase")}
            record["raw_record_ids"] = {record.pop("raw_record_id")}
            grouped[key] = record
            continue
        merged = grouped[key]
        merged["source_apis"].add(record.pop("source_api"))
        merged["search_phrases"].add(record.pop("source_phrase"))
        merged["raw_record_ids"].add(record.pop("raw_record_id"))
        for field, value in record.items():
            if field in {"concept_or_identical_dois"}:
                merged.setdefault(field, [])
                merged[field] = sorted(set(merged[field]) | set(value or []))
            elif field in {
                "related_identifiers",
                "related_publications",
                "subjects_keywords",
                "rights_license",
                "formats",
                "sizes",
                "dataverse_publications",
                "dataverse_related_material",
            }:
                parts = [p.strip() for p in str(merged.get(field, "")).split(" | ") if p.strip()]
                parts.extend(p.strip() for p in str(value or "").split(" | ") if p.strip())
                merged[field] = " | ".join(sorted(set(parts)))
            elif field == "description":
                if len(str(value or "")) > len(str(merged.get(field, "") or "")):
                    merged[field] = value
            elif not merged.get(field) and value:
                merged[field] = value
    rows = []
    for idx, record in enumerate(grouped.values(), start=1):
        record["candidate_id"] = f"RCTC-{idx:05d}"
        record["source_apis"] = "; ".join(sorted(record["source_apis"]))
        record["search_phrases"] = "; ".join(sorted(record["search_phrases"]))
        record["raw_record_ids"] = " | ".join(sorted(x for x in record["raw_record_ids"] if x))
        if isinstance(record.get("concept_or_identical_dois"), list):
            record["concept_or_identical_dois"] = " | ".join(record["concept_or_identical_dois"])
        rows.append(record)
    return rows


def contains_any(text, terms):
    return any(term in text for term in terms)


def screen_record(row):
    text = " ".join(
        clean_text(row.get(k))
        for k in [
            "title",
            "publisher",
            "repository_client",
            "subjects_keywords",
            "description",
            "rights_license",
            "formats",
            "related_publications",
            "dataverse_publications",
            "dataverse_related_material",
        ]
    ).lower()

    rct_signal = bool(re.search(r"\brandomi[sz]ed\b|\brct\b|\brandom allocation\b", text))
    associated_publication = bool(clean_text(row.get("related_publications"))) or contains_any(
        text,
        [
            "data for:",
            "data from:",
            "dataset of manuscript",
            "replication data",
            "associated article",
            "journal article",
            "published here",
            "manuscript",
            "article:",
        ],
    )

    restrictive_terms = [
        "restricted access",
        "access restricted",
        "restricted-use",
        "restricted use",
        "data use agreement",
        "dua",
        "controlled access",
        "access controlled",
        "apply for",
        "application system",
        "request access",
        "available upon request",
        "by request",
        "permission required",
        "login required",
        "embargo",
    ]
    open_terms = [
        "creative commons",
        "cc-by",
        "cc0",
        "openaccess",
        "open access",
        "public domain",
        "unrestricted",
        "dataverse",
        "figshare",
        "zenodo",
        "dryad",
        "mendeley",
        "osf",
    ]
    restricted_signal = contains_any(text, restrictive_terms)
    no_dua_open_signal = contains_any(text, open_terms) and not restricted_signal

    individual_terms = [
        "participant-level",
        "participant level",
        "individual-participant",
        "individual participant",
        "individual-level",
        "individual level",
        "patient-level",
        "patient level",
        "student-level",
        "student level",
        "subject-level",
        "subject level",
        "respondent-level",
        "raw data",
        "trial data",
        "clinical data",
        "survey data",
        "participants were",
        "patients were",
        "students were",
        "subjects were",
        "respondents",
        "participants",
        "patients",
        "students",
        "subjects",
        "randomly allocated",
        "randomly assigned",
        "allocated to",
        "assigned to",
        "treatment group",
        "control group",
        "intervention group",
        "experimental group",
    ]
    individual_signal = contains_any(text, individual_terms)

    data_file_signal = bool(row.get("file_count")) or contains_any(
        text,
        [
            ".csv",
            ".xlsx",
            ".xls",
            ".sav",
            ".dta",
            ".tab",
            "application/vnd.openxmlformats",
            "text/csv",
            "spss",
            "stata",
            "excel",
        ],
    )

    negative_terms = [
        "cluster-randomized",
        "cluster randomized",
        "cluster-randomised",
        "cluster randomised",
        "community-randomized",
        "community randomized",
        "school-randomized",
        "stepped wedge",
        "meta-analysis",
        "systematic review",
        "review protocol",
        "study protocol",
        "trial protocol",
        "protocol for",
        "statistical analysis plan",
        "sap ",
        "questionnaire",
        "survey instrument",
        "supplementary materials",
        "training materials",
        "codebook only",
        "aggregate data",
        "aggregated data",
        "summary data",
        "pooled data",
        "simulated",
        "simulation",
        "animal study",
        "mouse",
        "mice",
        "rat ",
    ]
    negative_signal = contains_any(text, negative_terms)
    cluster_signal = contains_any(
        text,
        [
            "cluster-randomized",
            "cluster randomized",
            "cluster-randomised",
            "cluster randomised",
            "community-randomized",
            "community randomized",
            "school-randomized",
            "stepped wedge",
        ],
    )
    protocol_material_signal = contains_any(
        text,
        [
            "study protocol",
            "trial protocol",
            "protocol for",
            "statistical analysis plan",
            "questionnaire",
            "supplementary materials",
            "training materials",
        ],
    )

    score = 0
    score += 2 if rct_signal else -2
    score += 2 if associated_publication else -1
    score += 2 if no_dua_open_signal else 0
    score += 2 if individual_signal else 0
    score += 1 if data_file_signal else 0
    score -= 3 if restricted_signal else 0
    score -= 3 if cluster_signal else 0
    score -= 2 if protocol_material_signal else 0
    score -= 2 if negative_signal else 0

    reasons = []
    if associated_publication:
        reasons.append("publication/link signal")
    else:
        reasons.append("no associated publication signal")
    if no_dua_open_signal:
        reasons.append("open/no-DUA signal")
    if restricted_signal:
        reasons.append("restriction/DUA signal")
    if individual_signal:
        reasons.append("individual-level signal")
    else:
        reasons.append("no individual-level signal")
    if data_file_signal:
        reasons.append("data-file signal")
    if cluster_signal:
        reasons.append("cluster-randomization signal")
    if protocol_material_signal:
        reasons.append("protocol/materials-only signal")
    elif negative_signal:
        reasons.append("other exclusion signal")

    if restricted_signal or cluster_signal or protocol_material_signal:
        status = "Likely not qualified"
    elif rct_signal and associated_publication and no_dua_open_signal and individual_signal and score >= 6:
        status = "Likely qualified"
    elif rct_signal and associated_publication and not restricted_signal:
        status = "Needs manual review"
    elif score <= 0:
        status = "Likely not qualified"
    else:
        status = "Needs manual review"

    return {
        "screen_status": status,
        "screen_score": score,
        "associated_publication_flag": "yes" if associated_publication else "no",
        "no_dua_open_flag": "yes" if no_dua_open_signal else "no",
        "restriction_or_dua_flag": "yes" if restricted_signal else "no",
        "individual_level_signal": "yes" if individual_signal else "no",
        "data_file_signal": "yes" if data_file_signal else "no",
        "cluster_randomized_signal": "yes" if cluster_signal else "no",
        "protocol_or_materials_signal": "yes" if protocol_material_signal else "no",
        "screen_reasons": "; ".join(reasons),
    }


def truncate(value, limit):
    text = clean_text(value)
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def write_csv(path, rows, fieldnames):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fieldnames})


def main():
    raw_records = list(datacite_records()) + list(harvard_records())
    rows = merge_records(raw_records)
    for row in rows:
        row.update(screen_record(row))
        row["description_short"] = truncate(row.get("description"), 900)
        row["related_publications_short"] = truncate(row.get("related_publications"), 500)
        row["rights_license_short"] = truncate(row.get("rights_license"), 300)
        row["subjects_keywords_short"] = truncate(row.get("subjects_keywords"), 300)
        row["related_identifiers_short"] = truncate(row.get("related_identifiers"), 500)

    rows.sort(
        key=lambda r: (
            {"Likely qualified": 0, "Needs manual review": 1, "Likely not qualified": 2}.get(
                r["screen_status"], 9
            ),
            -int(r["screen_score"]),
            r.get("publisher", ""),
            r.get("title", ""),
        )
    )

    candidate_fields = [
        "candidate_id",
        "screen_status",
        "screen_score",
        "associated_publication_flag",
        "no_dua_open_flag",
        "restriction_or_dua_flag",
        "individual_level_signal",
        "data_file_signal",
        "cluster_randomized_signal",
        "protocol_or_materials_signal",
        "screen_reasons",
        "title",
        "publisher",
        "repository_client",
        "provider",
        "doi",
        "url",
        "publication_year",
        "creators",
        "source_apis",
        "search_phrases",
        "file_count",
        "formats",
        "sizes",
        "rights_license_short",
        "subjects_keywords_short",
        "related_publications_short",
        "related_identifiers_short",
        "description_short",
        "canonical_key",
        "raw_record_ids",
    ]
    write_csv(OUT_DIR / "candidate_records.csv", rows, candidate_fields)

    status_counts = Counter(row["screen_status"] for row in rows)
    summary_rows = []
    for status, count in status_counts.most_common():
        summary_rows.append({"summary_type": "screen_status", "group": status, "count": count})
    by_publisher = Counter((row.get("publisher") or "Unknown") for row in rows)
    for publisher, count in by_publisher.most_common(30):
        summary_rows.append({"summary_type": "top_publishers", "group": publisher, "count": count})
    by_source_status = Counter(
        (row.get("source_apis") or "Unknown", row["screen_status"]) for row in rows
    )
    for (source, status), count in sorted(by_source_status.items()):
        summary_rows.append(
            {"summary_type": "source_by_status", "group": f"{source} | {status}", "count": count}
        )
    write_csv(OUT_DIR / "summary.csv", summary_rows, ["summary_type", "group", "count"])

    source_pages = []
    for path in sorted(RAW_DIR.glob("datacite_*_[0-9].json")) + sorted(
        RAW_DIR.glob("harvard_*_[0-9].json")
    ):
        with open(path, "r", encoding="utf-8") as f:
            payload = json.load(f)
        if path.name.startswith("datacite_"):
            records = len(payload.get("data", []) or [])
            total = payload.get("meta", {}).get("total", "")
            page = payload.get("meta", {}).get("page", "")
            phrase = search_phrase_from_name(path, "datacite_")
            api = "DataCite"
        else:
            data = payload.get("data", {})
            records = len(data.get("items", []) or [])
            total = data.get("total_count", "")
            page = ""
            phrase = search_phrase_from_name(path, "harvard_")
            api = "Harvard Dataverse API"
        source_pages.append(
            {
                "api": api,
                "search_phrase": phrase,
                "file": path.name,
                "records_in_page": records,
                "reported_total": total,
                "page": page,
            }
        )
    write_csv(
        OUT_DIR / "source_pages.csv",
        source_pages,
        ["api", "search_phrase", "file", "records_in_page", "reported_total", "page"],
    )

    rules = [
        {
            "rule": "Associated publication",
            "crude_logic": "Yes when DataCite relatedIdentifiers indicate article/document/citation links, or Harvard records mention publications, related materials, manuscript/article data, or DOI-like publication references.",
        },
        {
            "rule": "No DUA / open signal",
            "crude_logic": "Yes when license/source text includes open terms such as Creative Commons, CC0, CC-BY, open access, or common open repositories, and no restriction terms are detected.",
        },
        {
            "rule": "Restriction / DUA signal",
            "crude_logic": "Yes when text includes restricted access, access restricted, data use agreement/DUA, controlled access, request access, available upon request, login required, embargo, or similar terms.",
        },
        {
            "rule": "Individual-level signal",
            "crude_logic": "Yes when title/abstract/source text includes participant-level, individual participant, patient/student/subject/respondent-level, raw data, clinical data, survey data, treatment/control/intervention group, or randomized/allocated participants.",
        },
        {
            "rule": "Data-file signal",
            "crude_logic": "Yes when Harvard reports files or metadata mentions common analyzable formats such as CSV, Excel, SPSS, Stata, tabular files, or application/vnd.openxmlformats.",
        },
        {
            "rule": "Likely qualified",
            "crude_logic": "RCT signal + associated publication + open/no-DUA signal + individual-level signal, without detected restriction, cluster randomization, or protocol/materials-only signal.",
        },
        {
            "rule": "Needs manual review",
            "crude_logic": "RCT-looking and publication-backed but one or more required signals are weak/missing. These are not rejected; they need repository-file inspection and paper review.",
        },
        {
            "rule": "Likely not qualified",
            "crude_logic": "Detected restriction/DUA, cluster randomization, protocol/materials-only record, or weak overall RCT/data/publication evidence.",
        },
    ]
    write_csv(OUT_DIR / "screening_rules.csv", rules, ["rule", "crude_logic"])

    stats = {
        "raw_records": len(raw_records),
        "deduplicated_candidates": len(rows),
        "status_counts": dict(status_counts),
        "output_files": [
            "candidate_records.csv",
            "summary.csv",
            "source_pages.csv",
            "screening_rules.csv",
        ],
    }
    with open(OUT_DIR / "stats.json", "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
