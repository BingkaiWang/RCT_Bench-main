import csv
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from html import unescape
from pathlib import Path
from urllib.parse import quote, unquote, urljoin, urlparse

import pandas as pd


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SHORTLIST = ROOT / "outputs/rct_candidate_screening/predownload_screen/download_first_shortlist.csv"
DEFAULT_OUT = ROOT / "rct_expansion/provenance/predownload_verification_2026_06_09"
SHORTLIST = DEFAULT_SHORTLIST
OUT = DEFAULT_OUT
DOWNLOADS = OUT / "downloads"
METADATA = OUT / "metadata"
EXTRACTED = OUT / "extracted"
REQUEST_DELAY_SECONDS = 0.0

MAX_DOWNLOAD_BYTES = 350 * 1024 * 1024
MAX_EXTRACT_BYTES = 75 * 1024 * 1024

DATA_EXTENSIONS = {
    ".csv",
    ".tsv",
    ".tab",
    ".txt",
    ".xlsx",
    ".xls",
    ".sav",
    ".dta",
    ".rds",
    ".rdata",
    ".zip",
}
SUPPORT_EXTENSIONS = {".json", ".xml", ".doc", ".docx", ".do", ".r", ".sas", ".sps"}
SKIP_EXTENSIONS = {".pdf", ".png", ".jpg", ".jpeg", ".gif", ".tif", ".tiff", ".nii", ".gz"}

OPEN_LICENSE_RE = re.compile(r"\bcc0\b|cc-by|creative commons|openaccess|open access|public domain", re.I)
RESTRICTED_RE = re.compile(
    r"restricted access|restrictedaccess|controlled access|request access|available upon request|data use agreement|\bdua\b|login required|embargo|custom terms|permission required",
    re.I,
)
PUB_RE = re.compile(r"\b10\.\d{4,9}/[^\s|;,)]*|PMID:\s*\d+|pubmed|journal|article|publication|manuscript|doi:", re.I)
RANDOM_RE = re.compile(r"randomi[sz]ed|randomly assigned|random allocation|randomized controlled trial|\brct\b", re.I)
CLUSTER_RE = re.compile(r"cluster[- ]randomi[sz]ed|stepped wedge|school[- ]randomi[sz]ed|community[- ]randomi[sz]ed", re.I)
CROSSOVER_RE = re.compile(r"cross[- ]over|crossover", re.I)
OBS_RE = re.compile(r"\bcohort\b|observational|cross-sectional|secondary analysis|case-control", re.I)

ID_RE = re.compile(r"\b(id|subject|participant|patient|record|studyid|pid|sid)\b", re.I)
TREAT_RE = re.compile(
    r"treat|trt|arm|group|grupo|condition|intervention|intervenc|control|placebo|allocation|random|study[_ ]?group|product|sequence|assigned|trialarm|rx|alert|tratamiento|rama|tx[_-]?wl|1tx|\\btx\\b|\\bwl\\b",
    re.I,
)
OUTCOME_RE = re.compile(
    r"outcome|primary|secondary|score|scale|follow|post|change|delta|pain|vas|qol|quality|anxiety|depress|stress|"
    r"nausea|vomit|rhodes|rankin|mrs|nihss|adherence|step|activity|weight|bmi|waist|satiety|satiation|"
    r"glucose|glyc|insulin|ghrelin|thirst|salt|atrial|fibrillation|poaf|hospital|event|rate|symptom|"
    r"pcs|tsk|promis|odi|mobility|feasibility|usability|accept|heart|blood|cd4|viral|infection|recurrence|clinical|"
    r"nausea|náusea|vomit|vómit|vomit|arcad|malestar|rescate",
    re.I,
)
ARM_WORD_RE = re.compile(
    r"\b(control|placebo|intervention|vr|virtual|aprepitant|tocovid|myplate|calorie|bpt|cbt|dtm|ripc|usual|sms|reward|deposit|hypo|rehydrat|plain|sweet|iud|ius)\b",
    re.I,
)


@dataclass
class DownloadCandidate:
    row: dict
    candidate_dir: Path


def safe_name(value, fallback="file"):
    value = unquote(str(value or "")).strip()
    value = value.split("?")[0].split("#")[0]
    value = value.replace(os.sep, "_")
    value = re.sub(r"[^A-Za-z0-9._() +\\-]+", "_", value)
    value = re.sub(r"\s+", " ", value).strip(" ._")
    return value[:180] or fallback


def ensure_dirs():
    for path in [OUT, DOWNLOADS, METADATA, EXTRACTED]:
        path.mkdir(parents=True, exist_ok=True)


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def curl_to(url, out_path, timeout=240):
    if REQUEST_DELAY_SECONDS > 0:
        time.sleep(REQUEST_DELAY_SECONDS)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "curl",
        "-L",
        "--fail",
        "-A",
        "Bingkai Wang, University of Michigan, bingkai@umich.edu",
        "--retry",
        "2",
        "--retry-delay",
        "1",
        "--connect-timeout",
        "25",
        "--max-time",
        str(timeout),
        "--silent",
        "--show-error",
        "-o",
        str(out_path),
        url,
    ]
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    return proc.returncode, proc.stderr.strip()


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def read_text(path):
    for enc in ["utf-8", "latin1"]:
        try:
            return path.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    return path.read_text(errors="ignore")


def ext_for(filename, content_type=""):
    ext = Path(filename).suffix.lower()
    if ext:
        return ext
    ctype = (content_type or "").lower()
    if "spreadsheetml" in ctype:
        return ".xlsx"
    if "csv" in ctype:
        return ".csv"
    if "tab-separated" in ctype:
        return ".tab"
    if "zip" in ctype:
        return ".zip"
    if "spss" in ctype or "sav" in ctype:
        return ".sav"
    if "stata" in ctype:
        return ".dta"
    if "plain" in ctype:
        return ".txt"
    return ""


def is_probably_data_file(filename, content_type=""):
    ext = ext_for(filename, content_type)
    if ext in SKIP_EXTENSIONS:
        return False
    if ext in DATA_EXTENSIONS or ext in SUPPORT_EXTENSIONS:
        return True
    ctype = (content_type or "").lower()
    return any(token in ctype for token in ["csv", "tab-separated", "spreadsheet", "zip", "octet-stream", "stata", "spss"])


def dataverse_base(row):
    client = row.get("repository_client", "")
    publisher = row.get("publisher", "")
    doi = (row.get("doi") or "").lower()
    url = (row.get("url") or "").lower()
    if client == "gdcc.harvard-dv" or "Harvard" in publisher:
        return "https://dataverse.harvard.edu"
    if client in {"IFPRI", "impact_eval", "DL_CWT2"} or doi.startswith("10.7910/dvn/"):
        return "https://dataverse.harvard.edu"
    if client == "ocul.spdv" or "Borealis" in publisher:
        return "https://borealisdata.ca"
    if client == "dans.dataversenl" or "DataverseNL" in publisher:
        return "https://dataverse.nl"
    if "dataverse.no" in url or "dataverseno" in client.lower() or "DataverseNO" in publisher:
        return "https://dataverse.no"
    if "data.cipotato.org" in url or client == "sml.cip" or doi.startswith("10.21223/"):
        return "https://data.cipotato.org"
    if "heidata.uni-heidelberg.de" in url or client == "gesis.ubhd" or doi.startswith("10.11588/data/"):
        return "https://heidata.uni-heidelberg.de"
    if "dataverse.tdl.org" in url or client == "tdl.tdl" or doi.startswith("10.18738/t8/"):
        return "https://dataverse.tdl.org"
    return None


def zenodo_record_id(row):
    doi = (row.get("doi") or "").lower()
    match = re.search(r"zenodo\.(\d+)", doi)
    if match:
        return match.group(1)
    url = row.get("url") or ""
    match = re.search(r"/(?:record|records|doi/10\.5281/zenodo\.)(\d+)", url)
    return match.group(1) if match else None


def mendeley_dataset_id_version(row):
    doi = row.get("doi") or ""
    match = re.search(r"10\.17632/([A-Za-z0-9]+)\.(\d+)", doi)
    if match:
        return match.group(1), match.group(2)
    match = re.search(r"10\.17632/([A-Za-z0-9]+)(?:\b|$)", doi)
    if match:
        return match.group(1), None
    url = row.get("url") or ""
    match = re.search(r"/datasets/([A-Za-z0-9]+)/(\d+)", url)
    if match:
        return match.group(1), match.group(2)
    match = re.search(r"/datasets/([A-Za-z0-9]+)(?:\b|[?#])", url)
    if match:
        return match.group(1), None
    return None, None


def bath_eprint_id(row):
    doi = (row.get("doi") or "").lower()
    match = re.search(r"bath-0*(\d+)", doi)
    if match:
        return str(int(match.group(1)))
    url = row.get("url") or ""
    match = re.search(r"/(?:id/eprint/)?(\d+)", url)
    return match.group(1) if match else None


def figshare_article_id_version(row):
    url = row.get("url") or ""
    match = re.search(r"/articles/(?:[^/]+/)?[^/]+/(\d+)(?:/(\d+))?", url)
    if match:
        return match.group(1), match.group(2)
    doi = (row.get("doi") or "").lower()
    match = re.search(r"rd\.lboro\.(\d+)(?:\.v(\d+))?", doi)
    if match:
        return match.group(1), match.group(2)
    match = re.search(r"(?:m9\.figshare|sage)\.(\d+)(?:\.v(\d+))?", doi)
    if match:
        return match.group(1), match.group(2)
    return None, None


def openneuro_id_version(row):
    text = truthy_text(row.get("url"), row.get("doi"), row.get("related_publications_short"), row.get("description_short"))
    match = re.search(r"openneuro\.ds(\d+)\.v([0-9.]+)", text, re.I)
    if match:
        return f"ds{match.group(1)}", match.group(2).rstrip(".")
    match = re.search(r"dataset_id=on(\d+)", text, re.I)
    if match:
        return f"ds{match.group(1)}", "1.0.3"
    match = re.search(r"\bds(\d{6})\b", text, re.I)
    if match:
        return f"ds{match.group(1)}", "1.0.3"
    return None, None


def icpsr_record_id_version(row):
    text = truthy_text(row.get("doi"), row.get("url"))
    match = re.search(r"10\.3886/(?:e|E)(\d+)(?:v(\d+))?", text)
    if match:
        return match.group(1), f"V{match.group(2) or '1'}", "openicpsr"
    match = re.search(r"10\.3886/(?:icpsr|ICPSR)(\d+)(?:\.v(\d+))?", text)
    if match:
        return match.group(1), f"V{match.group(2) or '1'}", "icpsr"
    return None, None, None


def register_file(
    file_manifest,
    candidate_id,
    repository,
    source_record,
    filename,
    url,
    content_type="",
    size=None,
    restricted=False,
    role="data",
    guestbook_id="",
):
    filename = safe_name(filename, "download")
    ext = ext_for(filename, content_type)
    if ext and not Path(filename).suffix:
        filename = f"{filename}{ext}"
    file_manifest.append(
        {
            "candidate_id": candidate_id,
            "repository": repository,
            "source_record": source_record,
            "file_name": filename,
            "download_url": url,
            "content_type": content_type or "",
            "declared_size": size if size is not None else "",
            "restricted": "yes" if restricted else "no",
            "role": role,
            "guestbook_id": guestbook_id or "",
            "local_path": "",
            "download_status": "pending",
            "download_error": "",
            "bytes_downloaded": "",
        }
    )


def collect_dataverse_files(row, cand_dir, metadata_manifest, file_manifest):
    base = dataverse_base(row)
    if not base:
        raise ValueError("No Dataverse base URL")
    doi = row["doi"]
    url = f"{base}/api/datasets/:persistentId/?persistentId=doi:{quote(doi, safe=':/')}"
    meta_path = METADATA / f"{row['candidate_id']}_dataverse.json"
    code, err = curl_to(url, meta_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    data = read_json(meta_path)["data"]
    latest = data.get("latestVersion", {})
    guestbook_id = latest.get("guestbookId") or data.get("guestbookId") or ""
    files = latest.get("files", [])
    for item in files:
        df = item.get("dataFile", {})
        label = item.get("label") or df.get("filename") or f"dataverse_file_{df.get('id')}"
        content_type = df.get("contentType", "")
        if not is_probably_data_file(label, content_type):
            continue
        file_id = df.get("id")
        if not file_id:
            continue
        register_file(
            file_manifest,
            row["candidate_id"],
            row.get("publisher", ""),
            doi,
            label,
            f"{base}/api/access/datafile/{file_id}",
            content_type,
            df.get("filesize") or df.get("originalFileSize"),
            bool(item.get("restricted") or df.get("restricted")),
            guestbook_id=guestbook_id,
        )


def collect_zenodo_files(row, cand_dir, metadata_manifest, file_manifest):
    record_id = zenodo_record_id(row)
    if not record_id:
        raise ValueError("No Zenodo record id")
    url = f"https://zenodo.org/api/records/{record_id}"
    meta_path = METADATA / f"{row['candidate_id']}_zenodo.json"
    code, err = curl_to(url, meta_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    data = read_json(meta_path)
    for item in data.get("files", []):
        name = item.get("key") or item.get("filename") or item.get("id")
        if not is_probably_data_file(name, ""):
            continue
        url = item.get("links", {}).get("self")
        if not url:
            continue
        register_file(
            file_manifest,
            row["candidate_id"],
            "Zenodo",
            data.get("doi") or row.get("doi", ""),
            name,
            url,
            "",
            item.get("size"),
            False,
        )


def collect_dryad_files(row, cand_dir, metadata_manifest, file_manifest):
    encoded = quote(f"doi:{row['doi']}", safe="")
    url = f"https://datadryad.org/api/v2/datasets/{encoded}"
    meta_path = METADATA / f"{row['candidate_id']}_dryad.json"
    code, err = curl_to(url, meta_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    data = read_json(meta_path)
    version_href = data.get("_links", {}).get("stash:version", {}).get("href")
    if not version_href:
        return
    version_url = urljoin("https://datadryad.org", version_href)
    version_path = METADATA / f"{row['candidate_id']}_dryad_version.json"
    code, err = curl_to(version_url, version_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": version_url, "local_path": str(version_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    version = read_json(version_path)
    files_href = version.get("_links", {}).get("stash:files", {}).get("href")
    if not files_href:
        return
    files_url = urljoin("https://datadryad.org", files_href)
    files_path = METADATA / f"{row['candidate_id']}_dryad_files.json"
    code, err = curl_to(files_url, files_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": files_url, "local_path": str(files_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    files_data = read_json(files_path)
    for item in files_data.get("_embedded", {}).get("stash:files", []):
        name = item.get("path") or f"dryad_file_{item.get('id')}"
        content_type = item.get("mimeType", "")
        if not is_probably_data_file(name, content_type):
            continue
        download_href = item.get("_links", {}).get("stash:download", {}).get("href")
        if not download_href:
            continue
        register_file(
            file_manifest,
            row["candidate_id"],
            "Dryad",
            row["doi"],
            name,
            urljoin("https://datadryad.org", download_href),
            content_type,
            item.get("size"),
            False,
        )


def collect_mendeley_files(row, cand_dir, metadata_manifest, file_manifest):
    dataset_id, version = mendeley_dataset_id_version(row)
    if not dataset_id:
        raise ValueError("No Mendeley dataset id")
    url = f"https://data.mendeley.com/api/datasets/{dataset_id}/files"
    meta_path = METADATA / f"{row['candidate_id']}_mendeley_files.json"
    code, err = curl_to(url, meta_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    data = read_json(meta_path)
    for item in data if isinstance(data, list) else []:
        details = item.get("content_details", {})
        name = item.get("filename") or item.get("id")
        content_type = details.get("content_type", "")
        if not is_probably_data_file(name, content_type):
            continue
        download_url = details.get("download_url")
        if not download_url:
            continue
        register_file(
            file_manifest,
            row["candidate_id"],
            "Mendeley Data",
            row.get("doi", ""),
            name,
            download_url,
            content_type,
            item.get("size") or details.get("size"),
            False,
        )


def collect_bath_files(row, cand_dir, metadata_manifest, file_manifest):
    eprint_id = bath_eprint_id(row)
    if not eprint_id:
        raise ValueError("No Bath eprint id")
    url = f"https://researchdata.bath.ac.uk/id/eprint/{eprint_id}"
    meta_path = METADATA / f"{row['candidate_id']}_bath.html"
    code, err = curl_to(url, meta_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    html = read_text(meta_path)
    urls = sorted(set(unescape(x) for x in re.findall(r'https://researchdata\.bath\.ac\.uk/\d+/\d+/[^"<> ]+', html)))
    for file_url in urls:
        name = Path(urlparse(file_url).path).name
        if not is_probably_data_file(name, ""):
            continue
        register_file(
            file_manifest,
            row["candidate_id"],
            "University of Bath",
            row.get("doi", ""),
            name,
            file_url,
            "",
            "",
            False,
        )


def collect_figshare_files(row, cand_dir, metadata_manifest, file_manifest):
    article_id, version = figshare_article_id_version(row)
    if not article_id:
        raise ValueError("No Figshare article id")
    if version:
        url = f"https://api.figshare.com/v2/articles/{article_id}/versions/{version}"
    else:
        url = f"https://api.figshare.com/v2/articles/{article_id}"
    meta_path = METADATA / f"{row['candidate_id']}_figshare.json"
    code, err = curl_to(url, meta_path)
    metadata_manifest.append(
        {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)), "status": code, "error": err}
    )
    if code != 0:
        return
    data = read_json(meta_path)
    for item in data.get("files", []):
        name = item.get("name") or item.get("filename") or item.get("id")
        if not is_probably_data_file(name, ""):
            continue
        download_url = item.get("download_url")
        if not download_url:
            continue
        register_file(
            file_manifest,
            row["candidate_id"],
            row.get("publisher", "") or "Figshare",
            data.get("doi") or row.get("doi", ""),
            name,
            download_url,
            "",
            item.get("size"),
            bool(data.get("is_embargoed") or item.get("is_link_only")),
        )


def collect_loughborough_files(row, cand_dir, metadata_manifest, file_manifest):
    collect_figshare_files(row, cand_dir, metadata_manifest, file_manifest)


def collect_sage_files(row, cand_dir, metadata_manifest, file_manifest):
    try:
        collect_figshare_files(row, cand_dir, metadata_manifest, file_manifest)
        if any(rec["candidate_id"] == row["candidate_id"] for rec in file_manifest):
            return
    except Exception as exc:
        metadata_manifest.append(
            {"candidate_id": row["candidate_id"], "metadata_url": row.get("url", ""), "local_path": "", "status": "figshare_exception", "error": str(exc)}
        )
    pub_match = re.search(r"10\.1177/[A-Za-z0-9._/-]+", truthy_text(row.get("url"), row.get("related_publications_short")))
    if not pub_match:
        return
    raw_name = str(row.get("title") or "").split(" - for ")[0].split(" – for ")[0].strip()
    if not raw_name:
        raw_name = "sage_supplementary_file"
    filename = raw_name if Path(raw_name).suffix else f"{raw_name}.xlsx"
    file_url = f"https://journals.sagepub.com/doi/suppl/{pub_match.group(0)}/suppl_file/{quote(filename)}"
    register_file(
        file_manifest,
        row["candidate_id"],
        row.get("publisher", "") or "SAGE Journals",
        row.get("doi", ""),
        filename,
        file_url,
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "",
        False,
    )


def collect_openneuro_files(row, cand_dir, metadata_manifest, file_manifest):
    dataset_id, version = openneuro_id_version(row)
    if not dataset_id:
        raise ValueError("No OpenNeuro dataset id")
    base = f"https://openneuro.org/crn/datasets/{dataset_id}/snapshots/{version}/files"
    metadata_manifest.append(
        {
            "candidate_id": row["candidate_id"],
            "metadata_url": row.get("url", ""),
            "local_path": "",
            "status": "openneuro_direct_files",
            "error": f"Using OpenNeuro snapshot {dataset_id} {version}",
        }
    )
    for name in ["participants.tsv", "participants.json", "dataset_description.json"]:
        register_file(
            file_manifest,
            row["candidate_id"],
            row.get("publisher", "") or "OpenNeuro/NEMAR",
            row.get("doi", ""),
            name,
            f"{base}/{name}",
            "text/tab-separated-values" if name.endswith(".tsv") else "application/json",
            "",
            False,
            "metadata" if name.endswith(".json") else "data",
        )


def collect_icpsr_access_attempt(row, cand_dir, metadata_manifest, file_manifest):
    record_id, version, source = icpsr_record_id_version(row)
    urls = [row.get("url", "")]
    if record_id and source == "openicpsr":
        urls.append(f"https://www.openicpsr.org/openicpsr/project/{record_id}/version/{version}/view")
    elif record_id:
        urls.append(f"https://www.icpsr.umich.edu/web/ICPSR/studies/{record_id}/datadocumentation")
    for i, url in enumerate([u for u in urls if u]):
        meta_path = METADATA / f"{row['candidate_id']}_icpsr_{i + 1}.html"
        code, err = curl_to(url, meta_path)
        metadata_manifest.append(
            {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)) if meta_path.exists() else "", "status": code, "error": err}
        )


def collect_ubc_access_attempt(row, cand_dir, metadata_manifest, file_manifest):
    for i, url in enumerate([row.get("url", ""), f"https://doi.org/{row.get('doi', '')}"]):
        if not url or url == "https://doi.org/":
            continue
        meta_path = METADATA / f"{row['candidate_id']}_ubc_{i + 1}.html"
        code, err = curl_to(url, meta_path)
        metadata_manifest.append(
            {"candidate_id": row["candidate_id"], "metadata_url": url, "local_path": str(meta_path.relative_to(ROOT)) if meta_path.exists() else "", "status": code, "error": err}
        )


def looks_like_html_file(path):
    try:
        chunk = path.read_bytes()[:1024].lstrip().lower()
    except Exception:
        return False
    return chunk.startswith(b"<!doctype html") or chunk.startswith(b"<html") or b"<title>just a moment" in chunk[:512]


def download_registered_files(file_manifest):
    for rec in file_manifest:
        cand_dir = DOWNLOADS / rec["candidate_id"]
        cand_dir.mkdir(parents=True, exist_ok=True)
        if rec["restricted"] == "yes":
            rec["download_status"] = "skipped_restricted"
            continue
        size = int(rec["declared_size"] or 0) if str(rec["declared_size"]).isdigit() else 0
        if size and size > MAX_DOWNLOAD_BYTES:
            rec["download_status"] = "skipped_oversize"
            rec["download_error"] = f"Declared size {size} exceeds {MAX_DOWNLOAD_BYTES}"
            continue
        local = cand_dir / safe_name(rec["file_name"], "download")
        if local.exists() and local.stat().st_size > 0:
            if looks_like_html_file(local) and local.suffix.lower() in DATA_EXTENSIONS | SUPPORT_EXTENSIONS:
                rec["download_status"] = "failed"
                rec["download_error"] = "downloaded HTML/challenge page instead of data file"
                rec["bytes_downloaded"] = local.stat().st_size
                continue
            rec["local_path"] = str(local.relative_to(ROOT))
            rec["download_status"] = "already_downloaded"
            rec["bytes_downloaded"] = local.stat().st_size
            continue
        code, err = curl_to(rec["download_url"], local, timeout=600)
        if code != 0 and rec.get("guestbook_id"):
            signed_url, signed_err = dataverse_signed_url_with_guestbook(rec)
            if signed_url:
                code, err = curl_to(signed_url, local, timeout=600)
            else:
                err = f"{err}; guestbook response failed: {signed_err}".strip("; ")
        if code == 0 and local.exists() and local.stat().st_size > 0:
            if looks_like_html_file(local) and local.suffix.lower() in DATA_EXTENSIONS | SUPPORT_EXTENSIONS:
                rec["download_status"] = "failed"
                rec["download_error"] = "downloaded HTML/challenge page instead of data file"
                rec["bytes_downloaded"] = local.stat().st_size
                continue
            rec["local_path"] = str(local.relative_to(ROOT))
            rec["download_status"] = "downloaded"
            rec["bytes_downloaded"] = local.stat().st_size
        else:
            rec["download_status"] = "failed"
            rec["download_error"] = err or f"curl exit {code}"


def curl_post_json(url, payload, timeout=120):
    if REQUEST_DELAY_SECONDS > 0:
        time.sleep(REQUEST_DELAY_SECONDS)
    cmd = [
        "curl",
        "-L",
        "--fail",
        "-A",
        "Bingkai Wang, University of Michigan, bingkai@umich.edu",
        "-X",
        "POST",
        "-H",
        "Content-type: application/json",
        "--connect-timeout",
        "25",
        "--max-time",
        str(timeout),
        "--silent",
        "--show-error",
        "--data",
        json.dumps(payload),
        url,
    ]
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def dataverse_signed_url_with_guestbook(rec):
    try:
        parsed = urlparse(rec["download_url"])
        base = f"{parsed.scheme}://{parsed.netloc}"
        gb_path = METADATA / f"{rec['candidate_id']}_guestbook_{rec['guestbook_id']}.json"
        if not gb_path.exists() or gb_path.stat().st_size == 0:
            code, err = curl_to(f"{base}/api/guestbooks/{rec['guestbook_id']}", gb_path, timeout=60)
            if code != 0:
                return "", err or f"guestbook metadata curl exit {code}"
        guestbook = read_json(gb_path).get("data", {})
        answers = []
        for question in guestbook.get("customQuestions", []):
            if not question.get("required"):
                continue
            value = "Original research"
            options = [opt.get("value", "") for opt in question.get("optionValues", [])]
            if options and value not in options:
                value = options[0]
            answers.append({"id": question.get("id"), "value": value})
        payload = {
            "guestbookResponse": {
                "name": "Bingkai Wang",
                "email": "bingkai@umich.edu",
                "institution": "University of Michigan",
                "position": "Researcher",
                "answers": answers,
            }
        }
        signed_endpoint = rec["download_url"] + ("&" if "?" in rec["download_url"] else "?") + "signed=true"
        code, stdout, stderr = curl_post_json(signed_endpoint, payload)
        if code != 0:
            return "", stderr or f"signed-url curl exit {code}"
        data = json.loads(stdout)
        signed_url = data.get("data", {}).get("signedUrl", "")
        return signed_url, "" if signed_url else f"no signedUrl in response: {stdout[:200]}"
    except Exception as exc:
        return "", str(exc)


def extract_archives(file_manifest):
    archive_rows = []
    for rec in file_manifest:
        if rec["download_status"] not in {"downloaded", "already_downloaded"}:
            continue
        local = ROOT / rec["local_path"]
        if local.suffix.lower() != ".zip":
            continue
        target_dir = EXTRACTED / rec["candidate_id"] / local.stem
        target_dir.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(local) as zf:
                for info in zf.infolist():
                    if info.is_dir():
                        continue
                    name = safe_name(Path(info.filename).name, "archive_file")
                    ext = ext_for(name, "")
                    row = {
                        "candidate_id": rec["candidate_id"],
                        "archive_path": rec["local_path"],
                        "archive_member": info.filename,
                        "file_name": name,
                        "declared_size": info.file_size,
                        "local_path": "",
                        "extract_status": "skipped_non_data",
                        "extract_error": "",
                    }
                    if ext in DATA_EXTENSIONS - {".zip"} and info.file_size <= MAX_EXTRACT_BYTES:
                        out_path = target_dir / safe_name(info.filename.replace("/", "__"), "archive_file")
                        try:
                            out_path.parent.mkdir(parents=True, exist_ok=True)
                            with zf.open(info) as src, open(out_path, "wb") as dst:
                                shutil.copyfileobj(src, dst)
                            row["local_path"] = str(out_path.relative_to(ROOT))
                            row["extract_status"] = "extracted"
                        except Exception as exc:
                            row["extract_status"] = "failed"
                            row["extract_error"] = str(exc)
                    elif ext in DATA_EXTENSIONS - {".zip"}:
                        row["extract_status"] = "skipped_oversize"
                    archive_rows.append(row)
        except Exception as exc:
            archive_rows.append(
                {
                    "candidate_id": rec["candidate_id"],
                    "archive_path": rec["local_path"],
                    "archive_member": "",
                    "file_name": local.name,
                    "declared_size": "",
                    "local_path": "",
                    "extract_status": "failed_open_archive",
                    "extract_error": str(exc),
                }
            )
    return archive_rows


def read_csv_like(path):
    for enc in ["utf-8", "utf-8-sig", "latin1"]:
        try:
            return pd.read_csv(path, sep=None, engine="python", encoding=enc, nrows=1000)
        except Exception:
            continue
    # Fixed-field or malformed text files may still reveal a header line.
    raise ValueError("Unable to parse as delimited text")


def inspect_excel(path):
    xls = pd.ExcelFile(path)
    rows = []
    for sheet in xls.sheet_names[:20]:
        try:
            frame = pd.read_excel(path, sheet_name=sheet, nrows=1000)
            rows.append((sheet, frame))
        except Exception as exc:
            rows.append((sheet, exc))
    return rows


def promote_first_row_header(frame):
    if not isinstance(frame, pd.DataFrame) or frame.empty:
        return frame
    cols = [str(c) for c in frame.columns]
    bad_cols = sum(1 for c in cols if c.startswith("Unnamed") or re.fullmatch(r"\d+(?:\.\d+)?", c))
    if bad_cols / max(1, len(cols)) < 0.25:
        return frame
    first = frame.iloc[0]
    text_values = [str(v).strip() for v in first.tolist() if pd.notna(v) and str(v).strip()]
    if len(text_values) < max(3, min(8, len(cols) // 4)):
        return frame
    new_cols = []
    seen = {}
    for i, old in enumerate(cols):
        val = first.iloc[i]
        name = str(val).strip() if pd.notna(val) and str(val).strip() else old
        name = re.sub(r"\s+", " ", name)
        if name in seen:
            seen[name] += 1
            name = f"{name}.{seen[name]}"
        else:
            seen[name] = 0
        new_cols.append(name)
    promoted = frame.iloc[1:].reset_index(drop=True)
    promoted.columns = new_cols
    return promoted


def inspect_with_r(path):
    helper = Path(__file__).with_name("inspect_r_file.R")
    if not helper.exists():
        return None, "R helper missing"
    proc = subprocess.run(["Rscript", str(helper), str(path)], cwd=ROOT, text=True, capture_output=True, timeout=180)
    if proc.returncode != 0:
        return None, proc.stderr.strip() or proc.stdout.strip()
    try:
        return json.loads(proc.stdout), ""
    except Exception as exc:
        return None, f"Invalid R JSON: {exc}; {proc.stdout[:200]}"


def summarize_frame(frame):
    if not isinstance(frame, pd.DataFrame):
        raise ValueError(str(frame))
    frame = promote_first_row_header(frame)
    cols = [str(c) for c in frame.columns]
    treatment_cols = [c for c in cols if TREAT_RE.search(c)]
    outcome_cols = [c for c in cols if OUTCOME_RE.search(c)]
    id_cols = [c for c in cols if ID_RE.search(c)]
    arm_word_cols = [c for c in cols if ARM_WORD_RE.search(c)]
    treat_levels = []
    for col in treatment_cols[:6]:
        try:
            vals = frame[col].dropna().astype(str).str.slice(0, 80).unique().tolist()
            if 1 < len(vals) <= 12:
                treat_levels.append(f"{col}: {' | '.join(vals[:8])}")
        except Exception:
            continue
    numeric_cols = 0
    for col in frame.columns:
        try:
            if pd.api.types.is_numeric_dtype(frame[col]):
                numeric_cols += 1
        except Exception:
            pass
    return {
        "n_rows_sampled": int(frame.shape[0]),
        "n_cols": int(frame.shape[1]),
        "columns_sample": "; ".join(cols[:80]),
        "id_candidates": "; ".join(id_cols[:20]),
        "treatment_candidates": "; ".join((treatment_cols + [c for c in arm_word_cols if c not in treatment_cols])[:30]),
        "treatment_levels_sample": " || ".join(treat_levels[:5]),
        "outcome_candidates": "; ".join(outcome_cols[:40]),
        "numeric_col_count": numeric_cols,
    }


def inspect_one_file(candidate_id, local_path, source_kind="download"):
    path = ROOT / local_path
    ext = path.suffix.lower()
    base = {
        "candidate_id": candidate_id,
        "source_kind": source_kind,
        "local_path": local_path,
        "file_name": path.name,
        "sheet_or_object": "",
        "read_status": "pending",
        "read_error": "",
        "n_rows_sampled": "",
        "n_cols": "",
        "columns_sample": "",
        "id_candidates": "",
        "treatment_candidates": "",
        "treatment_levels_sample": "",
        "outcome_candidates": "",
        "numeric_col_count": "",
    }
    rows = []
    try:
        if ext in {".csv", ".tsv", ".tab", ".txt"}:
            frame = read_csv_like(path)
            row = dict(base)
            row.update(summarize_frame(frame))
            row["sheet_or_object"] = "delimited"
            row["read_status"] = "readable"
            rows.append(row)
        elif ext in {".xlsx", ".xls"}:
            for sheet, item in inspect_excel(path):
                row = dict(base)
                row["sheet_or_object"] = sheet
                if isinstance(item, Exception):
                    row["read_status"] = "failed"
                    row["read_error"] = str(item)
                else:
                    row.update(summarize_frame(item))
                    row["read_status"] = "readable"
                rows.append(row)
        elif ext in {".sav", ".dta", ".rds", ".rdata"}:
            result, err = inspect_with_r(path)
            row = dict(base)
            if result:
                row.update({k: result.get(k, "") for k in row if k in result})
                row["sheet_or_object"] = result.get("sheet_or_object", ext.lstrip("."))
                row["read_status"] = result.get("read_status", "readable")
                row["read_error"] = result.get("read_error", "")
            else:
                row["read_status"] = "failed"
                row["read_error"] = err
            rows.append(row)
        else:
            row = dict(base)
            row["read_status"] = "skipped_unsupported_extension"
            rows.append(row)
    except Exception as exc:
        row = dict(base)
        row["read_status"] = "failed"
        row["read_error"] = str(exc)
        rows.append(row)
    return rows


def inspect_files(file_manifest, archive_rows):
    inspection = []
    seen = set()
    for rec in file_manifest:
        if rec["download_status"] not in {"downloaded", "already_downloaded"} or not rec["local_path"]:
            continue
        local = rec["local_path"]
        if local in seen or Path(local).suffix.lower() == ".zip":
            continue
        seen.add(local)
        inspection.extend(inspect_one_file(rec["candidate_id"], local, "download"))
    for rec in archive_rows:
        if rec["extract_status"] == "extracted" and rec["local_path"]:
            local = rec["local_path"]
            if local in seen:
                continue
            seen.add(local)
            inspection.extend(inspect_one_file(rec["candidate_id"], local, "archive_member"))
    return inspection


def truthy_text(*parts):
    return " ".join(str(p or "") for p in parts)


def status_from_candidate(row, file_manifest, archive_rows, inspection):
    cid = row["candidate_id"]
    cand_files = [r for r in file_manifest if r["candidate_id"] == cid]
    cand_arch = [r for r in archive_rows if r["candidate_id"] == cid]
    cand_ins = [r for r in inspection if r["candidate_id"] == cid]
    downloaded = [r for r in cand_files if r["download_status"] in {"downloaded", "already_downloaded"}]
    failed = [r for r in cand_files if r["download_status"] == "failed"]
    restricted = [r for r in cand_files if r["restricted"] == "yes" or r["download_status"] == "skipped_restricted"]
    oversize = [r for r in cand_files if r["download_status"] == "skipped_oversize"]
    readable = [r for r in cand_ins if r["read_status"] == "readable"]

    meta_text = truthy_text(
        row.get("title"),
        row.get("description_short"),
        row.get("related_publications_short"),
        row.get("rights_license_short"),
    )
    license_ok = bool(OPEN_LICENSE_RE.search(row.get("rights_license_short", ""))) and not bool(RESTRICTED_RE.search(meta_text)) and not restricted
    publication_ok = bool(PUB_RE.search(truthy_text(row.get("title"), row.get("related_publications_short"), row.get("description_short"))))
    random_ok = bool(RANDOM_RE.search(meta_text)) and not bool(CLUSTER_RE.search(meta_text))
    crossover = bool(CROSSOVER_RE.search(meta_text))
    obs_flag = bool(OBS_RE.search(meta_text)) and not random_ok

    best_rows = []
    treatment_hits = []
    outcome_hits = []
    id_hits = []
    numeric_counts = []
    for rec in readable:
        try:
            n_rows = int(rec.get("n_rows_sampled") or 0)
            n_cols = int(rec.get("n_cols") or 0)
            numeric_counts.append(int(rec.get("numeric_col_count") or 0))
        except Exception:
            n_rows = 0
            n_cols = 0
        if n_rows >= 10 and n_cols >= 3:
            best_rows.append((n_rows, n_cols, rec["file_name"], rec.get("sheet_or_object", "")))
        if rec.get("treatment_candidates"):
            treatment_hits.append(rec.get("treatment_candidates"))
        if rec.get("outcome_candidates"):
            outcome_hits.append(rec.get("outcome_candidates"))
        if rec.get("id_candidates"):
            id_hits.append(rec.get("id_candidates"))

    group_file_names = " ".join(r["file_name"] for r in downloaded + cand_arch).replace("_", " ").replace("-", " ")
    treatment_from_files = bool(re.search(r"\b(control|placebo|intervention|vr|bpt|cbt|treatment|group)\b", group_file_names, re.I))
    treatment_ok = bool(treatment_hits) or treatment_from_files
    outcome_ok = bool(outcome_hits) or any(n >= 5 for n in numeric_counts)
    individual_ok = bool(best_rows) and (bool(id_hits) or max(r[0] for r in best_rows) >= 20)
    download_ok = bool(downloaded)

    reasons = []
    if not download_ok:
        reasons.append("no data file downloaded")
    if failed:
        reasons.append(f"{len(failed)} download failure(s)")
    if oversize:
        reasons.append(f"{len(oversize)} file(s) skipped as oversize")
    if not license_ok:
        reasons.append("license/restriction check not clean")
    if not publication_ok:
        reasons.append("associated publication not linked/clear in metadata")
    if not random_ok:
        reasons.append("individual randomization not confirmed by metadata")
    if crossover:
        reasons.append("crossover design requires method decision before benchmark cleaning")
    if obs_flag:
        reasons.append("observational/cohort wording without clear randomization")
    if not individual_ok:
        reasons.append("participant-level rows not confirmed")
    if not treatment_ok:
        reasons.append("treatment/group assignment not confirmed")
    if not outcome_ok:
        reasons.append("outcomes not confirmed")

    if (
        download_ok
        and license_ok
        and publication_ok
        and random_ok
        and individual_ok
        and treatment_ok
        and outcome_ok
        and not crossover
        and not obs_flag
    ):
        decision = "qualified_for_cleaning"
        next_action = "Read publication and map primary outcome/covariates before cleaning."
    elif not download_ok or not license_ok or obs_flag:
        decision = "not_qualified_before_cleaning"
        next_action = "Do not clean unless metadata/access issue is resolved."
    elif crossover:
        decision = "method_review_before_cleaning"
        next_action = "Decide whether crossover trials are admissible for the benchmark before cleaning."
    elif individual_ok and outcome_ok and not treatment_ok:
        decision = "not_qualified_before_cleaning"
        next_action = "Do not clean unless participant-level treatment assignment is found."
    else:
        decision = "needs_manual_review_before_cleaning"
        next_action = "Manual file/publication review before any cleaning."

    return {
        "candidate_id": cid,
        "title": row.get("title", ""),
        "doi": row.get("doi", ""),
        "repository": row.get("publisher", ""),
        "downloaded_file_count": len(downloaded),
        "download_failed_count": len(failed),
        "oversize_skipped_count": len(oversize),
        "archive_extracted_file_count": sum(1 for r in cand_arch if r["extract_status"] == "extracted"),
        "readable_table_count": len(readable),
        "license_status": "pass" if license_ok else "fail_or_unclear",
        "publication_status": "pass" if publication_ok else "unclear",
        "randomization_status": "pass" if random_ok else "unclear_or_fail",
        "crossover_status": "yes" if crossover else "no",
        "participant_level_status": "pass" if individual_ok else "unclear_or_fail",
        "treatment_assignment_status": "pass" if treatment_ok else "unclear_or_fail",
        "outcome_status": "pass" if outcome_ok else "unclear_or_fail",
        "qualification_decision": decision,
        "reasons": "; ".join(reasons) if reasons else "all crude pre-cleaning checks passed",
        "best_readable_tables": " | ".join(f"{name}:{sheet} rows>={rows} cols={cols}" for rows, cols, name, sheet in best_rows[:6]),
        "treatment_evidence": " | ".join(treatment_hits[:4]) or ("group inferred from file names" if treatment_from_files else ""),
        "outcome_evidence": " | ".join(outcome_hits[:4]),
        "next_action": next_action,
    }


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = list(rows)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main():
    global SHORTLIST, OUT, DOWNLOADS, METADATA, EXTRACTED, REQUEST_DELAY_SECONDS
    parser = argparse.ArgumentParser(description="Download and verify RCT candidate data files before cleaning.")
    parser.add_argument("--shortlist", type=Path, default=DEFAULT_SHORTLIST)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--status-filter", default="")
    parser.add_argument("--request-delay", type=float, default=0.0, help="Seconds to sleep before each outbound repository request.")
    args = parser.parse_args()
    SHORTLIST = args.shortlist if args.shortlist.is_absolute() else ROOT / args.shortlist
    OUT = args.out if args.out.is_absolute() else ROOT / args.out
    DOWNLOADS = OUT / "downloads"
    METADATA = OUT / "metadata"
    EXTRACTED = OUT / "extracted"
    REQUEST_DELAY_SECONDS = max(0.0, args.request_delay)

    ensure_dirs()
    if not SHORTLIST.exists():
        raise SystemExit(f"Missing shortlist: {SHORTLIST}")
    with open(SHORTLIST, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if args.status_filter:
        rows = [row for row in rows if row.get("predownload_status") == args.status_filter]

    metadata_manifest = []
    file_manifest = []
    for row in rows:
        cid = row["candidate_id"]
        cand_dir = DOWNLOADS / cid
        cand_dir.mkdir(parents=True, exist_ok=True)
        try:
            publisher = row.get("publisher", "")
            client = row.get("repository_client", "")
            if dataverse_base(row):
                collect_dataverse_files(row, cand_dir, metadata_manifest, file_manifest)
            elif client == "icpsr" or "ICPSR" in publisher:
                collect_icpsr_access_attempt(row, cand_dir, metadata_manifest, file_manifest)
            elif "NEMAR" in publisher or client == "cdl.ucsd":
                collect_openneuro_files(row, cand_dir, metadata_manifest, file_manifest)
            elif client == "sage.journals" or "SAGE" in publisher:
                collect_sage_files(row, cand_dir, metadata_manifest, file_manifest)
            elif "figshare" in client.lower() or "figshare" in publisher.lower() or publisher in {"Karger Publishers", "SciELO journals"}:
                collect_figshare_files(row, cand_dir, metadata_manifest, file_manifest)
            elif "University of British Columbia" in publisher or client == "ubc.oc":
                collect_ubc_access_attempt(row, cand_dir, metadata_manifest, file_manifest)
            elif "Dryad" in publisher or client == "dryad.dryad":
                collect_dryad_files(row, cand_dir, metadata_manifest, file_manifest)
            elif "Zenodo" in publisher or client == "cern.zenodo":
                collect_zenodo_files(row, cand_dir, metadata_manifest, file_manifest)
            elif "Mendeley" in publisher or client == "bl.mendeley":
                collect_mendeley_files(row, cand_dir, metadata_manifest, file_manifest)
            elif "Loughborough" in publisher or client == "bl.lboro":
                collect_loughborough_files(row, cand_dir, metadata_manifest, file_manifest)
            elif "Bath" in publisher or client == "bl.bath":
                collect_bath_files(row, cand_dir, metadata_manifest, file_manifest)
            else:
                metadata_manifest.append(
                    {
                        "candidate_id": cid,
                        "metadata_url": row.get("url", ""),
                        "local_path": "",
                        "status": "unsupported_repository",
                        "error": f"Unsupported repository {publisher}/{client}",
                    }
                )
        except Exception as exc:
            metadata_manifest.append(
                {"candidate_id": cid, "metadata_url": row.get("url", ""), "local_path": "", "status": "exception", "error": str(exc)}
            )

    download_registered_files(file_manifest)
    archive_rows = extract_archives(file_manifest)
    inspection = inspect_files(file_manifest, archive_rows)
    verification = [status_from_candidate(row, file_manifest, archive_rows, inspection) for row in rows]

    write_csv(OUT / "metadata_manifest.csv", metadata_manifest)
    write_csv(OUT / "file_manifest.csv", file_manifest)
    write_csv(OUT / "archive_manifest.csv", archive_rows)
    write_csv(OUT / "inspection_summary.csv", inspection)
    write_csv(OUT / "verification_results.csv", verification)

    summary = {
        "generated_at_utc": now_iso(),
        "shortlist_path": str(SHORTLIST.relative_to(ROOT)),
        "candidate_count": len(rows),
        "registered_file_count": len(file_manifest),
        "downloaded_file_count": sum(1 for r in file_manifest if r["download_status"] in {"downloaded", "already_downloaded"}),
        "failed_file_count": sum(1 for r in file_manifest if r["download_status"] == "failed"),
        "oversize_skipped_file_count": sum(1 for r in file_manifest if r["download_status"] == "skipped_oversize"),
        "extracted_archive_file_count": sum(1 for r in archive_rows if r["extract_status"] == "extracted"),
        "readable_table_count": sum(1 for r in inspection if r["read_status"] == "readable"),
        "decision_counts": pd.Series([r["qualification_decision"] for r in verification]).value_counts().to_dict(),
    }
    (OUT / "verification_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
