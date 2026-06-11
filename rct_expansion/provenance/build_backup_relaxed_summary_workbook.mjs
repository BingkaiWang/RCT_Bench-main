import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const provenanceDir = new URL("./", import.meta.url);
const decisionsPath = new URL("backup_relaxed_summary_recoverability_B06_B14.csv", provenanceDir);
const statsPath = new URL("backup_relaxed_summary_statistics_B06_B13.csv", provenanceDir);
const outputPath = new URL("backup_relaxed_summary_recoverability_B06_B14.xlsx", provenanceDir);
const previewPath = new URL("backup_relaxed_summary_recoverability_B06_B14_preview.png", provenanceDir);
const statsPreviewPath = new URL("backup_relaxed_summary_statistics_B06_B13_preview.png", provenanceDir);

const decisionsCsv = await fs.readFile(decisionsPath, "utf8");
const statsCsv = await fs.readFile(statsPath, "utf8");

const workbook = await Workbook.fromCSV(decisionsCsv, { sheetName: "Decisions" });
await workbook.fromCSV(statsCsv, { sheetName: "SummaryStats" });

const decisionSheet = workbook.worksheets.getItem("Decisions");
const statsSheet = workbook.worksheets.getItem("SummaryStats");

for (const sheet of [decisionSheet, statsSheet]) {
  sheet.freezePanes.freezeRows(1);
  sheet.showGridLines = true;
  const used = sheet.getUsedRange(true);
  used.format = {
    font: { name: "Aptos", size: 10 },
    wrapText: true,
    verticalAlignment: "top",
  };
  const header = used.getRow(0);
  header.format = {
    fill: "#1F4E79",
    font: { bold: true, color: "#FFFFFF", name: "Aptos", size: 10 },
    wrapText: true,
    verticalAlignment: "middle",
  };
  used.format.autofitRows();
}

decisionSheet.getRange("A:I").format.columnWidthPx = 130;
decisionSheet.getRange("J:K").format.columnWidthPx = 340;
statsSheet.getRange("A:F").format.columnWidthPx = 125;
statsSheet.getRange("G:N").format.columnWidthPx = 95;
statsSheet.getRange("O:O").format.columnWidthPx = 300;

decisionSheet.tables.add(decisionSheet.getUsedRange(true), true, "RelaxedRecoverabilityDecisions");
statsSheet.tables.add(statsSheet.getUsedRange(true), true, "RelaxedSummaryStatistics");

const preview = await workbook.render({
  sheetName: "Decisions",
  range: "A1:K10",
  scale: 1,
  format: "png",
});
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));

const statsPreview = await workbook.render({
  sheetName: "SummaryStats",
  range: "A1:O20",
  scale: 1,
  format: "png",
});
await fs.writeFile(statsPreviewPath, new Uint8Array(await statsPreview.arrayBuffer()));

const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(outputPath);

const inspect = await workbook.inspect({
  kind: "workbook,sheet,table",
  tableMaxRows: 4,
  tableMaxCols: 6,
  tableMaxCellChars: 120,
});
console.log(inspect.ndjson);
console.log(`saved ${outputPath.pathname}`);
