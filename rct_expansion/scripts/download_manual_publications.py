import csv
import re
import shutil
import ssl
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "rct_expansion" / "publications"
LOG = ROOT / "rct_expansion" / "provenance" / "manual_trials87_95_publication_downloads.csv"
USER_AGENT = "Bingkai Wang, University of Michigan, bingkai@umich.edu"


TRIALS = [
    {
        "trial_id": "87",
        "candidate_id": "RCTC-03207",
        "doi": "10.1186/s12871-016-0279-x",
        "title": "Comparison of hemodynamic response to tracheal intubation and postoperative pain in patients undergoing closed reduction of nasal bone fracture under general anesthesia: a randomized controlled trial comparing fentanyl and oxycodone",
    },
    {
        "trial_id": "88",
        "candidate_id": "RCTC-05855",
        "doi": "10.1186/s40795-016-0111-5",
        "title": "Effects of nutrition education on recurrent coronary events after percutaneous coronary intervention: A randomized clinical trial",
    },
    {
        "trial_id": "89",
        "candidate_id": "RCTC-03212",
        "doi": "10.1186/s12906-016-1337-0",
        "title": "Efficacy and safety assessment of acupuncture and nimodipine to treat mild cognitive impairment after cerebral infarction: a randomized controlled trial",
    },
    {
        "trial_id": "90",
        "candidate_id": "RCTC-00458/RCTC-00459",
        "doi": "10.1186/s12913-016-1384-8",
        "title": "Impact of a community pharmacist-led medication review on medicines use in patients on polypharmacy - a prospective randomised controlled trial",
    },
    {
        "trial_id": "91",
        "candidate_id": "RCTC-03185",
        "doi": "10.1186/s12884-017-1545-8",
        "title": "The MOVE-trial: Monocryl vs. Vicryl Rapide for skin repair in mediolateral episiotomies: a randomized controlled trial",
    },
    {
        "trial_id": "92",
        "candidate_id": "RCTC-04202",
        "doi": "10.1186/s12936-021-03586-5",
        "title": "Improving malaria preventive practices and pregnancy outcomes through a health education intervention: A randomized controlled trial",
    },
    {
        "trial_id": "93",
        "candidate_id": "RCTC-07219",
        "doi": "10.1371/journal.pone.0109032",
        "title": "The Impact of Text Message Reminders on Adherence to Antimalarial Treatment",
    },
    {
        "trial_id": "94",
        "candidate_id": "RCTC-06852",
        "doi": "10.1371/journal.pone.0162944",
        "title": "Impact of a Daily SMS Medication Reminder System on Tuberculosis Treatment Outcomes",
    },
    {
        "trial_id": "95",
        "candidate_id": "RCTC-03313",
        "doi": "10.1097/MEJ.0000000000001178",
        "title": "Laryngeal mask vs. laryngeal tube trial in paediatric patients (LaMaTuPe): A randomized-controlled trial",
    },
]


def safe_name(value):
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_")
    return value[:140] or "download"


def fetch(url, timeout=90):
    req = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    context = ssl.create_default_context()
    with urlopen(req, timeout=timeout, context=context) as resp:
        return resp.geturl(), resp.headers, resp.read()


def meta_content(html, name):
    pattern = re.compile(
        rf'<meta[^>]+(?:name|property)=["\']{re.escape(name)}["\'][^>]+content=["\']([^"\']+)["\']',
        re.I,
    )
    match = pattern.search(html)
    if match:
        return match.group(1).replace("&amp;", "&")
    pattern = re.compile(
        rf'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:name|property)=["\']{re.escape(name)}["\']',
        re.I,
    )
    match = pattern.search(html)
    return match.group(1).replace("&amp;", "&") if match else ""


def write_binary(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def main():
    rows = []
    LOG.parent.mkdir(parents=True, exist_ok=True)
    for trial in TRIALS:
        trial_dir = OUT / f"trial{trial['trial_id']}"
        trial_dir.mkdir(parents=True, exist_ok=True)
        doi_url = f"https://doi.org/{quote(trial['doi'], safe='/')}"
        row = {
            "Trial_ID": trial["trial_id"],
            "Candidate_ID": trial["candidate_id"],
            "Paper_DOI": trial["doi"],
            "Paper_Title": trial["title"],
            "Landing_URL": doi_url,
            "Resolved_URL": "",
            "HTML_Path": "",
            "PDF_URL": "",
            "PDF_Path": "",
            "Status": "",
            "Error": "",
        }
        try:
            resolved_url, headers, body = fetch(doi_url)
            row["Resolved_URL"] = resolved_url
            ctype = headers.get("Content-Type", "")
            if "pdf" in ctype.lower() or body[:4] == b"%PDF":
                pdf_path = trial_dir / f"trial{trial['trial_id']}_{safe_name(trial['doi'])}.pdf"
                write_binary(pdf_path, body)
                row["PDF_URL"] = resolved_url
                row["PDF_Path"] = str(pdf_path.relative_to(ROOT))
                row["Status"] = "pdf_downloaded_from_doi"
            else:
                html_path = trial_dir / f"trial{trial['trial_id']}_{safe_name(trial['doi'])}.html"
                write_binary(html_path, body)
                row["HTML_Path"] = str(html_path.relative_to(ROOT))
                html = body.decode("utf-8", errors="ignore")
                pdf_url = meta_content(html, "citation_pdf_url") or meta_content(html, "dc.identifier")
                if pdf_url and not pdf_url.lower().endswith(".pdf") and "type=printable" not in pdf_url:
                    pdf_url = ""
                row["PDF_URL"] = pdf_url
                if pdf_url:
                    pdf_resolved, pdf_headers, pdf_body = fetch(pdf_url)
                    if "pdf" in pdf_headers.get("Content-Type", "").lower() or pdf_body[:4] == b"%PDF":
                        pdf_path = trial_dir / f"trial{trial['trial_id']}_{safe_name(trial['doi'])}.pdf"
                        write_binary(pdf_path, pdf_body)
                        row["PDF_URL"] = pdf_resolved
                        row["PDF_Path"] = str(pdf_path.relative_to(ROOT))
                        row["Status"] = "pdf_downloaded_from_landing_meta"
                    else:
                        row["Status"] = "html_downloaded_no_public_pdf"
                        row["Error"] = "PDF URL did not return a PDF"
                else:
                    row["Status"] = "html_downloaded_no_public_pdf"
        except (HTTPError, URLError, TimeoutError, ssl.SSLError) as exc:
            row["Status"] = "download_failed"
            row["Error"] = str(exc)
        rows.append(row)

    with LOG.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(LOG.relative_to(ROOT))
    print("\n".join(f"{r['Trial_ID']} {r['Status']} {r['PDF_Path'] or r['HTML_Path']} {r['Error']}" for r in rows))


if __name__ == "__main__":
    sys.exit(main())
