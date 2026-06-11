import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const screenDir = path.join(root, "predownload_screen");
const outputXlsx = path.join(root, "likely_qualified_predownload_screen.xlsx");
const previewDir = path.join(root, "predownload_previews");

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
      } else {
        field += ch;
      }
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
  const numericHeaders = new Set(["predownload_score", "count", "publication_year"]);
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
  return parseCsv(await fs.readFile(path.join(screenDir, fileName), "utf8"));
}

function styleHeader(range) {
  range.format.fill = { color: "#1F4E79" };
  range.format.font = { bold: true, color: "#FFFFFF" };
  range.format.wrapText = true;
}

async function addCsvSheet(workbook, fileName, sheetName, tableName, widths = {}) {
  const matrix = await csvMatrix(fileName);
  const sheet = workbook.worksheets.add(sheetName);
  const rows = matrix.length;
  const cols = matrix[0].length;
  const range = `A1:${colLetter(cols)}${rows}`;
  sheet.getRange(range).values = matrix;
  styleHeader(sheet.getRange(`A1:${colLetter(cols)}1`));
  sheet.getRange(range).format.wrapText = true;
  sheet.getRange(range).format.borders = { preset: "all", style: "thin", color: "#D9E2EC" };
  sheet.freezePanes.freezeRows(1);
  sheet.freezePanes.freezeColumns(2);
  sheet.showGridLines = false;
  const table = sheet.tables.add(range, true, tableName);
  table.style = "TableStyleMedium2";
  table.showFilterButton = true;
  for (const [col, width] of Object.entries(widths)) {
    sheet.getRange(`${col}:${col}`).format.columnWidthPx = width;
  }
  return { sheet, rows, cols };
}

async function main() {
  const stats = JSON.parse(await fs.readFile(path.join(screenDir, "predownload_stats.json"), "utf8"));
  const workbook = Workbook.create();
  const readme = workbook.worksheets.add("README");
  readme.showGridLines = false;
  const counts = stats.counts || {};
  const rows = [
    ["Likely-Qualified Pre-download Screen", ""],
    ["Recorded", "2026-06-09"],
    ["Input likely-qualified records", stats.input_likely_qualified],
    ["Download first", counts["Download first"] || 0],
    ["Landing page / file manifest first", counts["Landing page / file manifest first"] || 0],
    ["Source-specific manual check", counts["Source-specific manual check"] || 0],
    ["Deferred", (counts["Defer - missing access/file certainty"] || 0) + (counts["Defer - low clinical or data confidence"] || 0)],
    ["Already curated exclusions", (counts["Already active expansion - exclude"] || 0) + (counts["Already original benchmark - exclude"] || 0)],
    ["Other exclude before download", counts["Exclude before download"] || 0],
    ["Purpose", "Reduce data-download workload by applying stricter metadata-only checks before opening dataset files."],
  ];
  readme.getRange(`A1:B${rows.length}`).values = rows;
  readme.getRange("A1:B1").merge();
  readme.getRange("A1:B1").format.fill = { color: "#EAF2F8" };
  readme.getRange("A1:B1").format.font = { bold: true, color: "#1F2937", size: 14 };
  readme.getRange("A2:A10").format.font = { bold: true, color: "#1F2937" };
  readme.getRange("A1:B10").format.borders = { preset: "all", style: "thin", color: "#D9E2EC" };
  readme.getRange("A:A").format.columnWidthPx = 260;
  readme.getRange("B:B").format.columnWidthPx = 720;
  readme.getRange("B10").format.wrapText = true;

  const commonWidths = {
    A: 95,
    B: 185,
    C: 80,
    D: 420,
    E: 95,
    F: 90,
    G: 90,
    H: 105,
    I: 90,
    J: 90,
    K: 90,
    L: 150,
    M: 150,
    N: 360,
    O: 170,
    P: 140,
    Q: 150,
    R: 260,
    S: 90,
    T: 220,
    U: 230,
    V: 360,
    W: 520,
  };
  await addCsvSheet(workbook, "download_first_shortlist.csv", "Download First", "DownloadFirstTable", commonWidths);
  await addCsvSheet(workbook, "landing_page_first_shortlist.csv", "Landing Page First", "LandingPageFirstTable", commonWidths);
  await addCsvSheet(workbook, "likely_qualified_predownload_screen.csv", "Full Pre-download Screen", "FullPredownloadTable", commonWidths);
  await addCsvSheet(workbook, "predownload_summary.csv", "Summary", "PredownloadSummaryTable", { A: 260, B: 480, C: 100 });
  await addCsvSheet(workbook, "predownload_rules.csv", "Rules", "PredownloadRulesTable", { A: 240, B: 880 });

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
  });
  console.log(errors.ndjson);

  await fs.mkdir(previewDir, { recursive: true });
  for (const [sheetName, range] of [
    ["README", "A1:B10"],
    ["Download First", "A1:H25"],
    ["Summary", "A1:C90"],
    ["Rules", "A1:B8"],
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
