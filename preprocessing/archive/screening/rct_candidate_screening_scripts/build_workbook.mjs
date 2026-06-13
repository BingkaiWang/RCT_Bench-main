import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const processedDir = path.join(root, "processed");
const outputXlsx = path.join(root, "rct_dataset_candidates_screened.xlsx");
const previewDir = path.join(root, "previews");

function colLetter(n) {
  let s = "";
  while (n > 0) {
    const m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

async function csvShape(file) {
  const text = await fs.readFile(file, "utf8");
  const matrix = parseCsv(text);
  return { matrix, rows: matrix.length, cols: matrix[0].length };
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let inQuotes = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"' && text[i + 1] === '"') {
        field += '"';
        i += 1;
      } else if (ch === '"') {
        inQuotes = false;
      } else {
        field += ch;
      }
      continue;
    }
    if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (ch !== "\r") {
      field += ch;
    }
  }
  if (field || row.length) {
    row.push(field);
    rows.push(row);
  }
  const numericHeaders = new Set([
    "screen_score",
    "file_count",
    "count",
    "records_in_page",
    "reported_total",
    "page",
  ]);
  const headers = rows[0] || [];
  return rows.map((r, rowIndex) =>
    r.map((value, colIndex) => {
      value = sanitizeCell(value);
      if (rowIndex === 0 || !numericHeaders.has(headers[colIndex])) return value;
      if (value === "") return "";
      return /^-?\d+(\.\d+)?$/.test(value) ? Number(value) : value;
    }),
  );
}

function sanitizeCell(value) {
  if (typeof value !== "string") return value;
  return value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");
}

function styleHeader(range, fill = "#1F4E79") {
  range.format.fill = { color: fill };
  range.format.font = { bold: true, color: "#FFFFFF" };
  range.format.wrapText = true;
}

function styleTitle(range) {
  range.format.fill = { color: "#EAF2F8" };
  range.format.font = { bold: true, color: "#1F2937", size: 14 };
}

async function addCsvSheet(workbook, csvName, sheetName, tableName, widths = {}) {
  const file = path.join(processedDir, csvName);
  const { matrix, rows, cols } = await csvShape(file);
  const sheet = workbook.worksheets.add(sheetName);
  const lastCol = colLetter(cols);
  const fullRange = `A1:${lastCol}${rows}`;
  sheet.getRange(fullRange).values = matrix;
  styleHeader(sheet.getRange(`A1:${lastCol}1`));
  sheet.freezePanes.freezeRows(1);
  sheet.showGridLines = false;
  const table = sheet.tables.add(fullRange, true, tableName);
  table.style = "TableStyleMedium2";
  table.showFilterButton = true;
  table.showBandedColumns = false;
  sheet.getRange(fullRange).format.wrapText = true;
  sheet.getRange(fullRange).format.borders = { preset: "all", style: "thin", color: "#D9E2EC" };
  for (const [col, width] of Object.entries(widths)) {
    sheet.getRange(`${col}:${col}`).format.columnWidthPx = width;
  }
  return { sheet, rows, cols, fullRange };
}

async function main() {
  const stats = JSON.parse(await fs.readFile(path.join(processedDir, "stats.json"), "utf8"));
  const workbook = Workbook.create();
  const readme = workbook.worksheets.add("README");
  readme.showGridLines = false;

  const statusCounts = stats.status_counts || {};
  const readmeRows = [
    ["RCT Dataset Candidate Screening Workbook", ""],
    ["Created", "2026-06-08"],
    ["Raw API records reviewed", stats.raw_records],
    ["Deduplicated candidate entries", stats.deduplicated_candidates],
    ["Likely qualified", statusCounts["Likely qualified"] || 0],
    ["Needs manual review", statusCounts["Needs manual review"] || 0],
    ["Likely not qualified", statusCounts["Likely not qualified"] || 0],
    ["Scope", "DataCite-indexed dataset records for randomized/randomised RCT phrases plus Harvard Dataverse native dataset search results."],
    ["Important limitation", "This is a crude metadata screen. It does not download or inspect every underlying data file and does not replace publication-level eligibility review."],
    ["Screening intent", "Keep broad candidates, deduplicate obvious overlaps, and flag likely publication-backed, open/no-DUA, individual-level RCT datasets for manual follow-up."],
  ];
  readme.getRange(`A1:B${readmeRows.length}`).values = readmeRows;
  readme.getRange("A1:B1").merge();
  styleTitle(readme.getRange("A1:B1"));
  readme.getRange("A2:A10").format.font = { bold: true, color: "#1F2937" };
  readme.getRange("A1:B10").format.borders = { preset: "all", style: "thin", color: "#D9E2EC" };
  readme.getRange("A:A").format.columnWidthPx = 230;
  readme.getRange("B:B").format.columnWidthPx = 760;
  readme.getRange("B8:B10").format.wrapText = true;

  const candidate = await addCsvSheet(
    workbook,
    "candidate_records.csv",
    "Candidates",
    "CandidateTable",
    {
      A: 95,
      B: 145,
      C: 85,
      D: 95,
      E: 90,
      F: 100,
      G: 95,
      H: 90,
      I: 95,
      J: 105,
      K: 250,
      L: 360,
      M: 180,
      N: 150,
      O: 110,
      P: 150,
      Q: 260,
      R: 95,
      S: 230,
      T: 150,
      U: 190,
      V: 80,
      W: 160,
      X: 120,
      Y: 240,
      Z: 220,
      AA: 360,
      AB: 360,
      AC: 520,
      AD: 170,
      AE: 320,
    },
  );
  candidate.sheet.freezePanes.freezeColumns(2);
  candidate.sheet.getRange(`C2:C${candidate.rows}`).setNumberFormat("0");

  await addCsvSheet(
    workbook,
    "summary.csv",
    "Summary",
    "SummaryTable",
    { A: 170, B: 430, C: 100 },
  );
  await addCsvSheet(
    workbook,
    "source_pages.csv",
    "Source Pages",
    "SourcePagesTable",
    { A: 190, B: 220, C: 310, D: 120, E: 120, F: 80 },
  );
  await addCsvSheet(
    workbook,
    "screening_rules.csv",
    "Screening Rules",
    "ScreeningRulesTable",
    { A: 190, B: 850 },
  );

  const inspect = await workbook.inspect({
    kind: "sheet,table",
    maxChars: 5000,
    tableMaxRows: 5,
    tableMaxCols: 8,
  });
  console.log(inspect.ndjson);

  const errors = await workbook.inspect({
    kind: "match",
    searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
    options: { useRegex: true, maxResults: 50 },
    summary: "final formula error scan",
  });
  console.log(errors.ndjson);

  await fs.mkdir(previewDir, { recursive: true });
  for (const [sheetName, range] of [
    ["README", "A1:B10"],
    ["Candidates", "A1:K35"],
    ["Summary", "A1:C45"],
    ["Source Pages", "A1:F30"],
    ["Screening Rules", "A1:B9"],
  ]) {
    const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
    const bytes = new Uint8Array(await preview.arrayBuffer());
    await fs.writeFile(path.join(previewDir, `${sheetName.replaceAll(" ", "_")}.png`), bytes);
  }

  const output = await SpreadsheetFile.exportXlsx(workbook);
  await output.save(outputXlsx);
  console.log(JSON.stringify({ outputXlsx, candidateRows: candidate.rows - 1 }));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
