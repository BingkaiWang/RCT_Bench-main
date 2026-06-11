import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDir, "../../..");
function argValue(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const verifyDir = path.resolve(root, argValue("--verify-dir", "rct_expansion/provenance/predownload_verification_2026_06_09"));
const outputXlsx = path.resolve(verifyDir, argValue("--output-name", "download_first_verification.xlsx"));
const workbookTitle = argValue("--title", "Download First Verification Workbook");
const workbookScope = argValue(
  "--scope",
  "Official repository metadata and data downloads for the 20 candidates in the Download first shortlist. This is a pre-cleaning eligibility screen, not publication-based variable cleaning.",
);
const previewDir = path.join(verifyDir, "workbook_previews");

function colLetter(n) {
  let s = "";
  while (n > 0) {
    const m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

function sanitizeCell(value) {
  if (typeof value !== "string") return value;
  return value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");
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
      } else field += ch;
      continue;
    }
    if (ch === '"') inQuotes = true;
    else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (ch !== "\r") field += ch;
  }
  if (field || row.length) {
    row.push(field);
    rows.push(row);
  }
  const numericHeaders = new Set([
    "count",
    "candidate_count",
    "registered_file_count",
    "downloaded_file_count",
    "download_failed_count",
    "oversize_skipped_count",
    "archive_extracted_file_count",
    "readable_table_count",
    "declared_size",
    "bytes_downloaded",
    "n_rows_sampled",
    "n_cols",
    "numeric_col_count",
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

async function csvMatrix(fileName) {
  return parseCsv(await fs.readFile(path.join(verifyDir, fileName), "utf8"));
}

async function fileExists(fileName) {
  try {
    await fs.access(path.join(verifyDir, fileName));
    return true;
  } catch {
    return false;
  }
}

function styleHeader(range) {
  range.format.fill = { color: "#1F4E79" };
  range.format.font = { bold: true, color: "#FFFFFF" };
  range.format.wrapText = true;
}

function styleTitle(range) {
  range.format.fill = { color: "#EAF2F8" };
  range.format.font = { bold: true, color: "#1F2937", size: 14 };
}

async function addCsvSheet(workbook, fileName, sheetName, tableName, widths = {}) {
  const matrix = await csvMatrix(fileName);
  const sheet = workbook.worksheets.add(sheetName);
  sheet.showGridLines = false;
  if (matrix.length === 0) return { sheet, rows: 0, cols: 0 };
  const rows = matrix.length;
  const cols = matrix[0].length;
  const lastCol = colLetter(cols);
  const range = `A1:${lastCol}${rows}`;
  sheet.getRange(range).values = matrix;
  styleHeader(sheet.getRange(`A1:${lastCol}1`));
  sheet.getRange(range).format.wrapText = true;
  sheet.getRange(range).format.borders = { preset: "all", style: "thin", color: "#D9E2EC" };
  sheet.freezePanes.freezeRows(1);
  sheet.freezePanes.freezeColumns(Math.min(2, cols));
  const table = sheet.tables.add(range, true, tableName);
  table.style = "TableStyleMedium2";
  table.showFilterButton = true;
  for (const [col, width] of Object.entries(widths)) {
    sheet.getRange(`${col}:${col}`).format.columnWidthPx = width;
  }
  return { sheet, rows, cols, range };
}

async function main() {
  const summary = JSON.parse(await fs.readFile(path.join(verifyDir, "verification_summary.json"), "utf8"));
  const generatedText = String(summary.generated_at_utc || "").replace("T", " ").replace(".000Z", " UTC").replace("+00:00", " UTC");
  const workbook = Workbook.create();
  const readme = workbook.worksheets.add("README");
  readme.showGridLines = false;

  const counts = summary.decision_counts || {};
  const readmeRows = [
    [workbookTitle, ""],
    ["Generated UTC", generatedText],
    ["Input candidates", summary.candidate_count],
    ["Official files registered", summary.registered_file_count],
    ["Files downloaded/reused", summary.downloaded_file_count],
    ["Failed file downloads", summary.failed_file_count],
    ["Oversize files skipped", summary.oversize_skipped_file_count],
    ["Archive members extracted", summary.extracted_archive_file_count],
    ["Readable tables/sheets", summary.readable_table_count],
    ["Qualified for cleaning", counts.qualified_for_cleaning || 0],
    ["Method review before cleaning", counts.method_review_before_cleaning || 0],
    ["Not qualified before cleaning", counts.not_qualified_before_cleaning || 0],
    ["Scope", workbookScope],
  ];
  readme.getRange(`A1:B${readmeRows.length}`).values = readmeRows;
  readme.getRange("A1:B1").merge();
  styleTitle(readme.getRange("A1:B1"));
  readme.getRange("A2:A13").format.font = { bold: true, color: "#1F2937" };
  readme.getRange("A1:B13").format.borders = { preset: "all", style: "thin", color: "#D9E2EC" };
  readme.getRange("A:A").format.columnWidthPx = 250;
  readme.getRange("B:B").format.columnWidthPx = 780;
  readme.getRange("B13").format.wrapText = true;

  await addCsvSheet(workbook, "verification_results.csv", "Verification Results", "VerificationResults", {
    A: 100,
    B: 430,
    C: 150,
    D: 170,
    E: 95,
    F: 95,
    G: 95,
    H: 115,
    I: 115,
    J: 115,
    K: 115,
    L: 130,
    M: 130,
    N: 130,
    O: 130,
    P: 155,
    Q: 360,
    R: 420,
    S: 360,
    T: 360,
    U: 420,
  });
  await addCsvSheet(workbook, "file_manifest.csv", "File Manifest", "FileManifest", {
    A: 100,
    B: 160,
    C: 180,
    D: 180,
    E: 300,
    F: 520,
    G: 150,
    H: 110,
    I: 90,
    J: 90,
    K: 360,
    L: 130,
    M: 360,
    N: 115,
  });
  await addCsvSheet(workbook, "inspection_summary.csv", "Inspection Summary", "InspectionSummary", {
    A: 100,
    B: 115,
    C: 300,
    D: 260,
    E: 160,
    F: 130,
    G: 360,
    H: 80,
    I: 80,
    J: 520,
    K: 260,
    L: 360,
    M: 420,
    N: 420,
    O: 100,
  });
  await addCsvSheet(workbook, "archive_manifest.csv", "Archive Manifest", "ArchiveManifest", {
    A: 100,
    B: 360,
    C: 420,
    D: 280,
    E: 115,
    F: 360,
    G: 140,
    H: 320,
  });
  await addCsvSheet(workbook, "metadata_manifest.csv", "Metadata Manifest", "MetadataManifest", {
    A: 100,
    B: 560,
    C: 430,
    D: 100,
    E: 500,
  });
  if (await fileExists("curated_queue_summary.csv")) {
    await addCsvSheet(workbook, "curated_queue_summary.csv", "Curated Queues", "CuratedQueues", {
      A: 260,
      B: 110,
    });
  }
  if (await fileExists("verification_results_curated.csv")) {
    await addCsvSheet(workbook, "verification_results_curated.csv", "Curated Results", "CuratedResults", {
      A: 100,
      B: 430,
      C: 150,
      D: 170,
      E: 180,
      F: 230,
      G: 210,
      H: 95,
      I: 95,
      J: 95,
      K: 115,
      L: 115,
      M: 115,
      N: 115,
      O: 130,
      P: 130,
      Q: 130,
      R: 155,
      S: 360,
      T: 420,
      U: 360,
      V: 360,
      W: 420,
      X: 420,
      Y: 420,
      Z: 420,
    });
  }

  const inspect = await workbook.inspect({
    kind: "sheet,table",
    maxChars: 6000,
    tableMaxRows: 5,
    tableMaxCols: 8,
  });
  console.log(inspect.ndjson);
  const errors = await workbook.inspect({
    kind: "match",
    searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
    options: { useRegex: true, maxResults: 100 },
  });
  console.log(errors.ndjson);

  await fs.mkdir(previewDir, { recursive: true });
  for (const [sheetName, range] of [
    ["README", "A1:B13"],
    ["Verification Results", "A1:K21"],
    ["File Manifest", "A1:H35"],
    ["Inspection Summary", "A1:H35"],
    ["Archive Manifest", "A1:H35"],
    ["Metadata Manifest", "A1:E25"],
  ]) {
    const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
    await fs.writeFile(
      path.join(previewDir, `${sheetName.replaceAll(" ", "_")}.png`),
      new Uint8Array(await preview.arrayBuffer()),
    );
  }

  const output = await SpreadsheetFile.exportXlsx(workbook);
  await output.save(outputXlsx);
  console.log(JSON.stringify({ outputXlsx }));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
