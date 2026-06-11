import re
from pathlib import Path

from pypdf import PdfReader


def clean_text(text: str) -> str:
    text = text.replace("\x00", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def main() -> None:
    pub_dir = Path("rct_expansion/publications")
    out_dir = Path("rct_expansion/provenance/publication_text")
    out_dir.mkdir(parents=True, exist_ok=True)

    for pdf_path in sorted(pub_dir.glob("trial*/**/*.pdf")):
        match = re.search(r"trial(\d+)", str(pdf_path))
        if not match:
            continue
        trial_id = int(match.group(1))
        pieces = []
        reader = PdfReader(pdf_path)
        for page_number, page in enumerate(reader.pages, start=1):
            text = page.extract_text() or ""
            pieces.append(f"\n\n--- page {page_number} ---\n{text}")
        output = out_dir / f"trial{trial_id}.txt"
        output.write_text(clean_text("\n".join(pieces)) + "\n", encoding="utf-8")
        print(f"trial{trial_id}: wrote {output} ({len(pieces)} pages)")


if __name__ == "__main__":
    main()
