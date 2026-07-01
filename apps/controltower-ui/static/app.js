const els = {
  projectPath: document.getElementById("projectPath"),
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
  dependencyList: document.getElementById("dependencyList"),
  workflowPanel: document.getElementById("workflowPanel"),
  commandCatalog: document.getElementById("commandCatalog"),
  jobPanel: document.getElementById("jobPanel"),
  logPanel: document.getElementById("logPanel"),
  chatForm: document.getElementById("chatForm"),
  chatInput: document.getElementById("chatInput")
};

let state = null;

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
    return `
      <div class="command-card">
        <strong>${command.label}</strong>
        <span>${command.group}</span>
        <button class="${className}" data-command="${key}">${command.template ? "Afficher" : "Lancer"}</button>
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
}

function renderJobs(jobs) {
  if (!els.jobPanel) return;
  const visibleJobs = (jobs || []).slice(-4).reverse();
  if (visibleJobs.length === 0) {
    setHtml(els.jobPanel, "");
    return;
  }
  setHtml(els.jobPanel, visibleJobs.map((job) => {
    return `<div class="job-entry"><strong>${job.label}</strong><span>${job.status}</span></div>`;
  }).join(""));
}

function renderLogs(logs) {
  if (!els.logPanel) return;
  if (!logs || logs.length === 0) {
    setHtml(els.logPanel, `<div class="log-entry"><strong>En attente</strong><pre>Choisissez un projet ou lancez une commande.</pre></div>`);
    return;
  }
  setHtml(els.logPanel, logs.slice().reverse().map((entry) => {
    return `
      <div class="log-entry">
        <strong>${entry.time} - ${entry.message}</strong>
        <pre>${entry.output || entry.level}</pre>
      </div>
    `;
  }).join(""));
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
      if (window.confirm("Cette action lance une commande reelle. Continuer ?")) {
        return runCommand(commandKey, true);
      }
    } else {
      showError("Commande non lancee", friendlyError(error), error.message);
    }
  } finally {
    await refresh();
  }
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

if (els.refreshButton) els.refreshButton.addEventListener("click", refresh);
if (els.dismissErrorButton) els.dismissErrorButton.addEventListener("click", clearError);

if (els.commandCatalog) els.commandCatalog.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  await runCommand(button.dataset.command);
});

if (els.workflowPanel) els.workflowPanel.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  await runCommand(button.dataset.command);
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
