const els = {
  projectPath: document.getElementById("projectPath"),
  setProjectButton: document.getElementById("setProjectButton"),
  refreshButton: document.getElementById("refreshButton"),
  branchState: document.getElementById("branchState"),
  githubLink: document.getElementById("githubLink"),
  gitState: document.getElementById("gitState"),
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
  const items = [
    ["Projet", deps.project && deps.project.available],
    ["Git", deps.git && deps.git.available],
    ["Aider", deps.aider && deps.aider.available],
    ["Ollama", deps.ollama && deps.ollama.available],
    ["Ornith 9B", deps.ornith && deps.ornith.available],
    ["Hermes", deps.hermes && deps.hermes.available]
  ];
  els.dependencyList.innerHTML = items.map(([name, ok]) => {
    return `<div class="status-item"><span>${name}</span>${statusBadge(Boolean(ok))}</div>`;
  }).join("");
}

function renderCommands(commands) {
  els.commandCatalog.innerHTML = Object.entries(commands).map(([key, command]) => {
    const className = command.template ? "template" : (command.dangerous ? "danger" : "secondary");
    return `
      <div class="command-card">
        <strong>${command.label}</strong>
        <span>${command.group}</span>
        <button class="${className}" data-command="${key}">${command.template ? "Afficher" : "Lancer"}</button>
      </div>
    `;
  }).join("");
}

function renderWorkflow(steps) {
  els.workflowPanel.innerHTML = (steps || []).map((step, index) => {
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
  }).join("");
}

function renderLastRun(lastRun) {
  const info = lastRun || {};
  els.lastRunStatus.textContent = info.label || "En attente";
  const artifacts = info.artifacts || {};
  const links = [
    ["Workspace", artifacts.workspace],
    ["Rapport", artifacts.report],
    ["Validation", artifacts.validation],
    ["Run log", artifacts.run_log],
    ["Summary", artifacts.summary]
  ].filter(([, value]) => value);
  els.artifactLinks.innerHTML = links.length
    ? links.map(([label, value]) => `<span title="${value}">${label}</span>`).join("")
    : `<span>Aucun artefact recent</span>`;
}

function renderJobs(jobs) {
  const visibleJobs = (jobs || []).slice(-4).reverse();
  if (visibleJobs.length === 0) {
    els.jobPanel.innerHTML = "";
    return;
  }
  els.jobPanel.innerHTML = visibleJobs.map((job) => {
    return `<div class="job-entry"><strong>${job.label}</strong><span>${job.status}</span></div>`;
  }).join("");
}

function renderLogs(logs) {
  if (!logs || logs.length === 0) {
    els.logPanel.innerHTML = `<div class="log-entry"><strong>En attente</strong><pre>Choisissez un projet ou lancez une commande.</pre></div>`;
    return;
  }
  els.logPanel.innerHTML = logs.slice().reverse().map((entry) => {
    return `
      <div class="log-entry">
        <strong>${entry.time} - ${entry.message}</strong>
        <pre>${entry.output || entry.level}</pre>
      </div>
    `;
  }).join("");
}

function render(nextState) {
  state = nextState;
  els.projectPath.value = state.project_path || "";
  els.branchState.textContent = `Branche: ${(state.git && state.git.branch) || "-"}`;
  els.gitState.textContent = `Git: ${(state.git && state.git.status) || "-"}`;
  if (state.git && state.git.github_url) {
    els.githubLink.href = state.git.github_url;
    els.githubLink.textContent = state.git.github_url;
  } else {
    els.githubLink.href = "#";
    els.githubLink.textContent = "GitHub non detecte";
  }
  renderDependencies(state.dependencies || {});
  renderLastRun(state.last_run || {});
  renderWorkflow(state.workflow_steps || []);
  renderCommands(state.commands || {});
  renderJobs(state.jobs || []);
  renderLogs(state.logs || []);
}

async function refresh() {
  render(await requestJson("/api/state"));
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
      window.alert(error.message);
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

els.setProjectButton.addEventListener("click", async () => {
  try {
    await requestJson("/api/project", {
      method: "POST",
      body: JSON.stringify({ project_path: els.projectPath.value })
    });
    await refresh();
  } catch (error) {
    window.alert(error.message);
  }
});

els.refreshButton.addEventListener("click", refresh);

els.commandCatalog.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  await runCommand(button.dataset.command);
});

els.workflowPanel.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  await runCommand(button.dataset.command);
});

els.chatForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = els.chatInput.value.trim();
  if (!message) return;
  els.chatInput.value = "";
  try {
    await requestJson("/api/chat", {
      method: "POST",
      body: JSON.stringify({ message })
    });
  } catch (error) {
    window.alert(error.message);
  } finally {
    await refresh();
  }
});

refresh();
