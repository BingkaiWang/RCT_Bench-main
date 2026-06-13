import { initAnalytics, trackEvent } from "./analytics.js";

const state = {
  trials: [],
  filtered: [],
  filterTimer: null,
};

const els = {
  search: document.querySelector("#search-input"),
  area: document.querySelector("#area-filter"),
  outcome: document.querySelector("#outcome-filter"),
  randomization: document.querySelector("#randomization-filter"),
  sort: document.querySelector("#sort-select"),
  table: document.querySelector("#trial-table"),
  count: document.querySelector("#result-count"),
  empty: document.querySelector("#empty-state"),
  dialog: document.querySelector("#trial-dialog"),
  dialogContent: document.querySelector("#dialog-content"),
  statTrials: document.querySelector("#stat-trials"),
  statRows: document.querySelector("#stat-rows"),
  statVars: document.querySelector("#stat-vars"),
  statYears: document.querySelector("#stat-years"),
};

const fieldsForSearch = [
  "trialId",
  "registry",
  "paperName",
  "journal",
  "primaryOutcome",
  "primaryOutcomeType",
  "randomizationScheme",
  "randomizationHighLevel",
  "researchArea",
  "statisticalModel",
];

function formatNumber(value) {
  if (value === null || value === undefined || value === "") return "Not reported";
  return new Intl.NumberFormat("en-US").format(Number(value));
}

function compactNumber(value) {
  if (value === null || value === undefined || value === "") return "--";
  return new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 }).format(Number(value));
}

function clean(value) {
  return value === null || value === undefined || value === "" ? "Not reported" : String(value);
}

function escapeHtml(value) {
  return clean(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function setOptions(select, values, label) {
  const unique = [...new Set(values.filter(Boolean).map(String))].sort((a, b) => a.localeCompare(b));
  select.replaceChildren(new Option(label, ""));
  for (const value of unique) {
    select.append(new Option(value, value));
  }
}

function initStats(summary) {
  els.statTrials.textContent = formatNumber(summary.trialCount);
  els.statRows.textContent = compactNumber(summary.participantRows);
  els.statVars.textContent = compactNumber(summary.variableCount);
  els.statYears.textContent = `${summary.yearMin}-${summary.yearMax}`;
}

function initFilters() {
  setOptions(els.area, state.trials.map((trial) => trial.researchArea), "All areas");
  setOptions(els.outcome, state.trials.map((trial) => trial.primaryOutcomeType), "All outcomes");
  setOptions(
    els.randomization,
    state.trials.map((trial) => trial.randomizationHighLevel),
    "All schemes",
  );

  for (const control of [els.search, els.area, els.outcome, els.randomization, els.sort]) {
    control.addEventListener("input", render);
  }

  for (const control of [els.area, els.outcome, els.randomization, els.sort]) {
    control.addEventListener("change", () => trackFilterUse(control.id));
  }

  els.search.addEventListener("input", () => {
    window.clearTimeout(state.filterTimer);
    state.filterTimer = window.setTimeout(() => trackFilterUse("search-input"), 900);
  });
}

function matchesSearch(trial, term) {
  if (!term) return true;
  const haystack = fieldsForSearch.map((field) => trial[field] || "").join(" ").toLowerCase();
  return haystack.includes(term);
}

function sortTrials(trials) {
  const sorted = [...trials];
  const sort = els.sort.value;
  if (sort === "year-desc") {
    sorted.sort((a, b) => (b.publicationYear || 0) - (a.publicationYear || 0) || a.id - b.id);
  } else if (sort === "sample-desc") {
    sorted.sort((a, b) => (b.sampleSize || 0) - (a.sampleSize || 0) || a.id - b.id);
  } else if (sort === "citation-desc") {
    sorted.sort((a, b) => (b.citation || 0) - (a.citation || 0) || a.id - b.id);
  } else {
    sorted.sort((a, b) => a.id - b.id);
  }
  return sorted;
}

function filteredTrials() {
  const term = els.search.value.trim().toLowerCase();
  return sortTrials(
    state.trials.filter((trial) => {
      return (
        matchesSearch(trial, term) &&
        (!els.area.value || trial.researchArea === els.area.value) &&
        (!els.outcome.value || trial.primaryOutcomeType === els.outcome.value) &&
        (!els.randomization.value || trial.randomizationHighLevel === els.randomization.value)
      );
    }),
  );
}

function trialRow(trial) {
  const tr = document.createElement("tr");
  tr.innerHTML = `
    <td>
      <button class="row-action" type="button" data-trial="${trial.id}">${escapeHtml(trial.trialId)}</button>
      <div class="cell-muted">${escapeHtml(trial.registry || "No registry ID")}</div>
    </td>
    <td>
      <div class="paper-title">${escapeHtml(trial.paperName)}</div>
      <div class="paper-meta">${escapeHtml(trial.journal)}${trial.publicationYear ? `, ${trial.publicationYear}` : ""}</div>
    </td>
    <td><span class="tag">${escapeHtml(trial.researchArea)}</span></td>
    <td>
      ${formatNumber(trial.sampleSize)}
      <div class="cell-muted">${formatNumber(trial.columns)} variables</div>
    </td>
    <td>
      ${escapeHtml(trial.primaryOutcome)}
      <div class="cell-muted">${escapeHtml(trial.primaryOutcomeType)}</div>
    </td>
    <td>
      <div class="file-actions">
        <a class="small-button primary" href="${trial.csvPath}" data-download="csv" data-trial-id="${trial.id}" download>CSV</a>
        <a class="small-button ghost" href="${trial.rdsPath}" data-download="rds" data-trial-id="${trial.id}" download>RDS</a>
      </div>
    </td>
  `;
  return tr;
}

function render() {
  state.filtered = filteredTrials();
  els.table.replaceChildren(...state.filtered.map(trialRow));
  els.count.textContent = `${formatNumber(state.filtered.length)} of ${formatNumber(state.trials.length)} trials`;
  els.empty.hidden = state.filtered.length > 0;

  for (const button of els.table.querySelectorAll("[data-trial]")) {
    button.addEventListener("click", () => openTrial(Number(button.dataset.trial)));
  }

  for (const link of els.table.querySelectorAll("[data-download]")) {
    link.addEventListener("click", () => {
      trackEvent("trial_file_download", {
        trial_id: link.dataset.trialId,
        file_type: link.dataset.download,
      });
    });
  }
}

function detail(label, value) {
  return `
    <div>
      <span class="detail-label">${escapeHtml(label)}</span>
      <span class="detail-value">${escapeHtml(value)}</span>
    </div>
  `;
}

function openTrial(id) {
  const trial = state.trials.find((item) => item.id === id);
  if (!trial) return;
  const paperLink = trial.paperLink
    ? `<a class="small-button ghost" href="${escapeHtml(trial.paperLink)}" data-paper-link target="_blank" rel="noreferrer">Paper</a>`
    : "";

  els.dialogContent.innerHTML = `
    <div class="dialog-body">
      <div class="section-kicker">${escapeHtml(trial.trialId)}</div>
      <h2 class="dialog-title" id="dialog-title">${escapeHtml(trial.paperName)}</h2>
      <p class="paper-meta">${escapeHtml(trial.journal)}${trial.publicationYear ? `, ${trial.publicationYear}` : ""}</p>
      <div class="detail-grid">
        ${detail("Registry", trial.registry || "Not reported")}
        ${detail("Research area", trial.researchArea)}
        ${detail("Sample size", formatNumber(trial.sampleSize))}
        ${detail("Arms", trial.arms || "Not reported")}
        ${detail("Control group", trial.controlGroup)}
        ${detail("Study phase", trial.studyPhase)}
        ${detail("Primary outcome", trial.primaryOutcome)}
        ${detail("Outcome type", trial.primaryOutcomeType)}
        ${detail("Trial success", trial.trialSuccess)}
        ${detail("Statistical model", trial.statisticalModel)}
        ${detail("Randomization", trial.randomizationScheme)}
        ${detail("High-level scheme", trial.randomizationHighLevel)}
        ${detail("Rows", formatNumber(trial.rows))}
        ${detail("Variables", formatNumber(trial.variables))}
        ${detail("Citation count", formatNumber(trial.citation))}
        ${detail("Primary outcome columns", formatNumber(trial.primaryOutcomes))}
        ${detail("Secondary outcome columns", formatNumber(trial.secondaryOutcomes))}
        ${detail("Covariates", formatNumber(trial.covariates))}
      </div>
      <p><strong>Treatment levels:</strong> ${escapeHtml(trial.treatmentLevels)}</p>
      <div class="dialog-actions">
        <a class="button primary" href="${trial.csvPath}" data-download="csv" data-trial-id="${trial.id}" download>Download CSV</a>
        <a class="button ghost" href="${trial.rdsPath}" data-download="rds" data-trial-id="${trial.id}" download>Download RDS</a>
        ${paperLink}
      </div>
    </div>
  `;
  els.dialog.showModal();
  trackEvent("trial_detail_open", {
    trial_id: trial.id,
    research_area: trial.researchArea || "Not reported",
  });

  for (const link of els.dialogContent.querySelectorAll("[data-download]")) {
    link.addEventListener("click", () => {
      trackEvent("trial_file_download", {
        trial_id: link.dataset.trialId,
        file_type: link.dataset.download,
        source: "dialog",
      });
    });
  }

  const paper = els.dialogContent.querySelector("[data-paper-link]");
  if (paper) {
    paper.addEventListener("click", () => {
      trackEvent("paper_link_click", {
        trial_id: trial.id,
        link_url: trial.paperLink,
      });
    });
  }
}

function trackFilterUse(controlId) {
  trackEvent("metadata_filter_use", {
    control_id: controlId,
    result_count: state.filtered.length,
    has_search: els.search.value.trim().length > 0,
    area_selected: Boolean(els.area.value),
    outcome_selected: Boolean(els.outcome.value),
    randomization_selected: Boolean(els.randomization.value),
    sort_order: els.sort.value,
  });
}

async function load() {
  try {
    initAnalytics();
    const response = await fetch("assets/site-data.json");
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    state.trials = data.trials;
    initStats(data.summary);
    initFilters();
    render();
  } catch (error) {
    els.count.textContent = "Could not load site data";
    els.empty.hidden = false;
    els.empty.textContent = "The metadata index did not load. Serve the website from a local web server and try again.";
    console.error(error);
  }
}

document.querySelectorAll("[data-site-download]").forEach((link) => {
  link.addEventListener("click", () => {
    trackEvent("site_file_download", {
      file_type: link.dataset.siteDownload,
    });
  });
});

load();
