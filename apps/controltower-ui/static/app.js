const els = {
  projectPath: document.getElementById("projectPath"),
  browseProjectButton: document.getElementById("browseProjectButton"),
  setProjectButton: document.getElementById("setProjectButton"),
  refreshButton: document.getElementById("refreshButton"),
  branchState: document.getElementById("branchState"),
  githubLink: document.getElementById("githubLink"),
  gitState: document.getElementById("gitState"),
  errorPanel: document.getElementById("errorPanel"),
  errorTitle: document.getElementById("errorTitle"),
  errorMessage: document.getElementById("errorMessage"),
  dismissErrorButton: document.getElementById("dismissErrorButton"),
  lastRunStatus: document.getElementById("lastRunStatus"),
  artifactLinks: document.getElementById("artifactLinks"),
  reportActions: document.getElementById("reportActions"),
  readReportButton: document.getElementById("readReportButton"),
  downloadReportButton: document.getElementById("downloadReportButton"),
  coveragePanel: document.getElementById("coveragePanel"),
  coverageStatus: document.getElementById("coverageStatus"),
  coverageDetails: document.getElementById("coverageDetails"),
  dependencyList: document.getElementById("dependencyList"),
  workflowPanel: document.getElementById("workflowPanel"),
  commandCatalog: document.getElementById("commandCatalog"),
  jobPanel: document.getElementById("jobPanel"),
  logPanel: document.getElementById("logPanel"),
  chatForm: document.getElementById("chatForm"),
  chatInput: document.getElementById("chatInput"),
  modalPanel: document.getElementById("modalPanel"),
  modalTitle: document.getElementById("modalTitle"),
  modalMessage: document.getElementById("modalMessage"),
  modalCancelButton: document.getElementById("modalCancelButton"),
  modalConfirmButton: document.getElementById("modalConfirmButton"),
  helpModal: document.getElementById("helpModal"),
  helpTitle: document.getElementById("helpTitle"),
  helpMessage: document.getElementById("helpMessage"),
  helpCommand: document.getElementById("helpCommand"),
  helpCloseButton: document.getElementById("helpCloseButton"),
  reportModal: document.getElementById("reportModal"),
  reportPath: document.getElementById("reportPath"),
  reportWarnings: document.getElementById("reportWarnings"),
  reportContent: document.getElementById("reportContent"),
  reportCloseButton: document.getElementById("reportCloseButton")
};

let state = null;
let confirmResolver = null;
const REPORT_READER_LABEL = "Lire le rapport";
const NEW_PROJECT_LABEL = "Nouveau projet";

function escapeHtml(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function setText(element, value) {
  if (element) element.textContent = value;
}

function setHtml(element, value) {
  if (element) element.innerHTML = value;
}

function showError(title, message, detail = "") {
  setText(els.errorTitle, title || "Action impossible");
  setText(els.errorMessage, message || "ControlTower n'a pas pu terminer cette action.");
  if (els.errorPanel) els.errorPanel.hidden = false;
  if (detail) {
    renderLogs([...(state && state.logs ? state.logs : []), {
      time: new Date().toLocaleTimeString("fr-FR", { hour12: false }),
      level: "error",
      message: title || "Erreur",
      output: detail
    }]);
  }
}

function clearError() {
  if (els.errorPanel) els.errorPanel.hidden = true;
}

function showConfirm(title, message) {
  setText(els.modalTitle, title || "Confirmation");
  setText(els.modalMessage, message || "Confirmer cette action ?");
  if (els.modalPanel) els.modalPanel.hidden = false;
  return new Promise((resolve) => {
    confirmResolver = resolve;
  });
}

function resolveConfirm(value) {
  if (els.modalPanel) els.modalPanel.hidden = true;
  if (confirmResolver) {
    confirmResolver(Boolean(value));
    confirmResolver = null;
  }
}

function friendlyError(error) {
  const raw = (error && error.message) || "Erreur inconnue";
  if (raw.includes("Confirmation requise")) {
    return "Cette action peut lancer Aider ou modifier un snapshot. Confirmez explicitement pour continuer.";
  }
  if (raw.includes("Commande non autorisee")) {
    return "Cette commande n'est pas dans le catalogue ControlTower autorise.";
  }
  if (raw.includes("chemin") || raw.includes("Projet")) {
    return "Le chemin projet indique n'est pas accessible. Verifiez le dossier puis relancez.";
  }
  return raw;
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options
  });
  const payload = await response.json();
  if (!response.ok) {
    const error = new Error(payload.error || "Erreur inconnue");
    error.payload = payload;
    throw error;
  }
  return payload;
}

function statusBadge(ok) {
  return `<span class="badge ${ok ? "ok" : "bad"}">${ok ? "OK" : "Absent"}</span>`;
}

function renderDependencies(deps) {
  if (!els.dependencyList) return;
  const items = [
    ["Projet", deps.project && deps.project.available],
    ["Git", deps.git && deps.git.available],
    ["Aider", deps.aider && deps.aider.available],
    ["Ollama", deps.ollama && deps.ollama.available],
    ["Ornith 9B", deps.ornith && deps.ornith.available],
    ["Hermes", deps.hermes && deps.hermes.available]
  ];
  setHtml(els.dependencyList, items.map(([name, ok]) => {
    return `<div class="status-item"><span>${name}</span>${statusBadge(Boolean(ok))}</div>`;
  }).join(""));
}

function renderCommands(commands) {
  if (!els.commandCatalog) return;
  setHtml(els.commandCatalog, Object.entries(commands).map(([key, command]) => {
    const className = command.template ? "template" : (command.dangerous ? "danger" : "secondary");
    const description = command.description || "Commande ControlTower.";
    return `
      <div class="command-card" title="${escapeHtml(description)}">
        <div class="command-title">
          <strong>${escapeHtml(command.label)}</strong>
          <button class="help-button" data-command-help="${escapeHtml(key)}" type="button" title="Aide">?</button>
        </div>
        <span>${escapeHtml(command.group)}</span>
        <button class="${className}" data-command="${escapeHtml(key)}">${command.template ? "Afficher" : "Lancer"}</button>
      </div>
    `;
  }).join(""));
}

function renderWorkflow(steps) {
  if (!els.workflowPanel) return;
  setHtml(els.workflowPanel, (steps || []).map((step, index) => {
    const button = step.command
      ? `<button class="secondary" data-command="${step.command}">Faire</button>`
      : `<span class="badge ok">OK</span>`;
    return `
      <div class="workflow-step">
        <span class="workflow-index">${index + 1}</span>
        <strong>${step.label}</strong>
        ${button}
      </div>
    `;
  }).join(""));
}

function renderLastRun(lastRun) {
  if (!els.lastRunStatus && !els.artifactLinks) return;
  const info = lastRun || {};
  setText(els.lastRunStatus, info.label || "En attente");
  const artifacts = info.artifacts || {};
  const links = [
    ["Workspace", artifacts.workspace],
    ["Rapport", artifacts.report],
    ["Validation", artifacts.validation],
    ["Run log", artifacts.run_log],
    ["Summary", artifacts.summary]
  ].filter(([, value]) => value);
  setHtml(
    els.artifactLinks,
    links.length
      ? links.map(([label, value]) => `<span title="${value}">${label}</span>`).join("")
      : `<span>Aucun artefact recent</span>`
  );
  if (els.reportActions) {
    els.reportActions.hidden = !artifacts.report;
  }
}

function renderAuditCoverage(coverage) {
  if (!els.coveragePanel) return;
  const info = coverage || {};
  if (!info.total_files) {
    setText(els.coverageStatus, "Aucun audit lance");
    setHtml(els.coverageDetails, `<span>Aucun pack de contexte recent</span>`);
    return;
  }
  const complete = info.status === "complete" || info.is_project_complete;
  const title = complete ? "Audit projet complet" : "Audit projet incomplet";
  setText(els.coverageStatus, title);
  const omitted = info.omitted_files || 0;
  const included = info.included_files || 0;
  const total = info.total_files || 0;
  const percent = info.percent || 0;
  const omittedItems = (info.omitted || []).slice(0, 5).map((item) => {
    const path = item.path || item;
    const reason = item.reason ? ` - ${item.reason}` : "";
    return `<li>${path}${reason}</li>`;
  }).join("");
  setHtml(els.coverageDetails, `
    <span>${included}/${total} fichiers couverts (${percent}%).</span>
    <span>${omitted} fichier(s) hors contexte.</span>
    ${omittedItems ? `<ul>${omittedItems}</ul>` : ""}
    ${!complete && omitted > 0 ? `<button class="secondary coverage-action" data-command="continue_audit" type="button">Continuer audit</button>` : ""}
  `);
}

function renderJobs(jobs) {
  if (!els.jobPanel) return;
  const visibleJobs = (jobs || []).slice(-4).reverse();
  if (visibleJobs.length === 0) {
    setHtml(els.jobPanel, "");
    return;
  }
  setHtml(els.jobPanel, visibleJobs.map((job) => {
    const stalled = job.stalled || job.health === "stalled";
    const statusText = stalled
      ? `Aucune activite recente (${job.silence_seconds || 0}s)`
      : (job.status_label || job.status);
    const output = (job.output || "").slice(-700);
    const cancelButton = (job.status === "queued" || job.status === "running")
      ? `<button class="secondary job-cancel" data-job-cancel="${job.id}" type="button">Arreter</button>`
      : "";
    return `
      <div class="job-entry ${stalled ? "stalled" : ""}">
        <div class="job-main">
          <strong>${job.label}</strong>
          <span>${statusText}</span>
          ${job.last_activity_at ? `<small>Derniere activite: ${job.last_activity_at}</small>` : ""}
          ${output ? `<pre>${output}</pre>` : ""}
        </div>
        ${cancelButton}
      </div>
    `;
  }).join(""));
}

function renderLogs(logs) {
  if (!els.logPanel) return;
  if (!logs || logs.length === 0) {
    renderLogPanel(els.logPanel, `<div class="log-entry"><strong>En attente</strong><pre>Choisissez un projet ou lancez une commande.</pre></div>`);
    return;
  }
  renderLogPanel(els.logPanel, logs.map((entry) => {
    return `
      <div class="log-entry">
        <strong>${entry.time} - ${entry.message}</strong>
        <pre>${entry.output || entry.level}</pre>
      </div>
    `;
  }).join(""));
}

function shouldStickToBottom(panel) {
  if (!panel) return false;
  const distance = panel.scrollHeight - panel.scrollTop - panel.clientHeight;
  return distance < 80;
}

function renderLogPanel(panel, html) {
  const stickToBottom = shouldStickToBottom(panel);
  panel.innerHTML = html;
  if (stickToBottom) {
    panel.scrollTop = panel.scrollHeight;
  }
}

function render(nextState) {
  state = nextState;
  if (els.projectPath) els.projectPath.value = state.project_path || "";
  setText(els.branchState, `Branche: ${(state.git && state.git.branch) || "-"}`);
  setText(els.gitState, `Git: ${(state.git && state.git.status) || "-"}`);
  if (els.githubLink && state.git && state.git.github_url) {
    els.githubLink.href = state.git.github_url;
    setText(els.githubLink, state.git.github_url);
  } else if (els.githubLink) {
    els.githubLink.href = "#";
    setText(els.githubLink, "GitHub non detecte");
  }
  renderDependencies(state.dependencies || {});
  renderLastRun(state.last_run || {});
  renderAuditCoverage(state.audit_coverage || {});
  renderWorkflow(state.workflow_steps || []);
  renderCommands(state.commands || {});
  renderJobs(state.jobs || []);
  renderLogs(state.logs || []);
}

async function refresh() {
  try {
    render(await requestJson("/api/state"));
  } catch (error) {
    showError("Etat indisponible", "Impossible de charger l'etat ControlTower. Verifiez que le serveur local tourne.", error.message);
  }
}

async function runCommand(commandKey, confirmed = false) {
  try {
    if (commandKey === "ticket_from_report") {
      await requestJson("/api/tickets/from-report", {
        method: "POST",
        body: JSON.stringify({})
      });
      await refresh();
      return;
    }
    await requestJson("/api/jobs", {
      method: "POST",
      body: JSON.stringify({ command: commandKey, confirmed })
    });
    startJobPolling();
  } catch (error) {
    if (error.payload && error.payload.requires_confirmation) {
      const accepted = await showConfirm(
        "Confirmer le lancement",
        "Cette action lance une commande reelle avec Aider ou le systeme local. ControlTower gardera les sorties et validera le resultat."
      );
      if (accepted) {
        return runCommand(commandKey, true);
      }
    } else {
      showError("Commande non lancee", friendlyError(error), error.message);
    }
  } finally {
    await refresh();
  }
}

async function browseProject() {
  try {
    const payload = await requestJson("/api/project/browse", {
      method: "POST",
      body: JSON.stringify({})
    });
    if (payload.canceled) return;
    if (els.projectPath && payload.project_path) els.projectPath.value = payload.project_path;
    await refresh();
  } catch (error) {
    showError("Selection dossier impossible", friendlyError(error), error.message);
  }
}

function openCommandHelp(commandKey) {
  const command = state && state.commands ? state.commands[commandKey] : null;
  if (!command) return;
  setText(els.helpTitle, command.label || "Commande");
  setText(els.helpMessage, command.description || "Commande ControlTower.");
  setText(els.helpCommand, command.command || "");
  if (els.helpModal) els.helpModal.hidden = false;
}

function closeCommandHelp() {
  if (els.helpModal) els.helpModal.hidden = true;
}

async function readReport() {
  try {
    const payload = await requestJson("/api/report");
    setText(els.reportPath, payload.path || "");
    setHtml(els.reportWarnings, (payload.warnings || []).map((item) => `<div>${escapeHtml(item)}</div>`).join(""));
    setHtml(els.reportContent, payload.html || "<p>Rapport vide.</p>");
    if (els.reportModal) els.reportModal.hidden = false;
  } catch (error) {
    showError("Rapport indisponible", friendlyError(error), error.message);
  }
}

function closeReport() {
  if (els.reportModal) els.reportModal.hidden = true;
}

function downloadReport() {
  window.location.href = "/api/report/download";
}

let pollTimer = null;

function startJobPolling() {
  if (pollTimer) return;
  pollTimer = window.setInterval(async () => {
    await refresh();
    const running = (state.jobs || []).some((job) => job.status === "queued" || job.status === "running");
    if (!running) {
      window.clearInterval(pollTimer);
      pollTimer = null;
    }
  }, 1500);
}

async function cancelJob(jobId) {
  try {
    await requestJson(`/api/jobs/${jobId}/cancel`, {
      method: "POST",
      body: JSON.stringify({})
    });
    await refresh();
  } catch (error) {
    showError("Arret impossible", friendlyError(error), error.message);
  }
}

if (els.setProjectButton) els.setProjectButton.addEventListener("click", async () => {
  try {
    await requestJson("/api/project", {
      method: "POST",
      body: JSON.stringify({ project_path: els.projectPath ? els.projectPath.value : "" })
    });
    await refresh();
  } catch (error) {
    showError("Projet non charge", friendlyError(error), error.message);
  }
});

if (els.browseProjectButton) els.browseProjectButton.addEventListener("click", browseProject);
if (els.refreshButton) els.refreshButton.addEventListener("click", refresh);
if (els.dismissErrorButton) els.dismissErrorButton.addEventListener("click", clearError);
if (els.modalCancelButton) els.modalCancelButton.addEventListener("click", () => resolveConfirm(false));
if (els.modalConfirmButton) els.modalConfirmButton.addEventListener("click", () => resolveConfirm(true));
if (els.helpCloseButton) els.helpCloseButton.addEventListener("click", closeCommandHelp);
if (els.reportCloseButton) els.reportCloseButton.addEventListener("click", closeReport);
if (els.readReportButton) els.readReportButton.addEventListener("click", readReport);
if (els.downloadReportButton) els.downloadReportButton.addEventListener("click", downloadReport);

if (els.commandCatalog) els.commandCatalog.addEventListener("click", async (event) => {
  const helpButton = event.target.closest("button[data-command-help]");
  if (helpButton) {
    openCommandHelp(helpButton.dataset.commandHelp);
    return;
  }
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  await runCommand(button.dataset.command);
});

if (els.workflowPanel) els.workflowPanel.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  await runCommand(button.dataset.command);
});

if (els.coveragePanel) els.coveragePanel.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  await runCommand(button.dataset.command);
});

if (els.jobPanel) els.jobPanel.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-job-cancel]");
  if (!button) return;
  await cancelJob(button.dataset.jobCancel);
});

if (els.chatForm) els.chatForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = els.chatInput ? els.chatInput.value.trim() : "";
  if (!message) return;
  if (els.chatInput) els.chatInput.value = "";
  try {
    await requestJson("/api/chat", {
      method: "POST",
      body: JSON.stringify({ message })
    });
  } catch (error) {
    showError("Message non traite", friendlyError(error), error.message);
  } finally {
    await refresh();
  }
});

refresh();
