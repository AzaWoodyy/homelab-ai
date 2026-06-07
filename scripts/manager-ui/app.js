(function () {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const app = $("#app");
  const loginForm = $("#login-form");
  const loginSecret = $("#login-secret");
  const loginError = $("#login-error");
  const refreshButton = $("#refresh-button");
  const logoutButton = $("#logout-button");
  const connectionDot = $("#connection-dot");
  const pendingBanner = $("#pending-apply");
  const pendingText = $("#pending-apply-text");
  const statusGrid = $("#status-grid");
  const jobStatusChip = $("#job-status-chip");
  const jobSummary = $("#job-summary");
  const jobLog = $("#job-log");
  const jobHistory = $("#job-history");
  const jobHistoryCount = $("#job-history-count");
  const actionState = $("#action-state");
  const configForm = $("#config-form");
  const configReadOnly = $("#config-read-only");
  const modelsForm = $("#models-form");
  const modelsTextarea = $("#models-textarea");
  const modelsUninstallRemoved = $("#models-uninstall-removed");
  const installedModels = $("#installed-models");
  const tabs = $$(".tab");
  const tabIndicator = $(".tab-indicator");
  const tabsRoot = $(".tabs");
  const toastRegion = $("#toast-region");

  const ROUTES = ["dashboard", "manage"];

  let authenticated = false;
  let eventSource = null;
  let latestSummary = null;
  let lastSummaryAt = 0;
  let summaryInFlight = null;
  let configDirty = false;
  let modelsDirty = false;
  let pendingRefreshAfterAction = false;

  // ====================================================================
  // tiny render helpers — only update the DOM when the value actually changed
  // ====================================================================

  function setText(node, value) {
    const next = value == null ? "" : String(value);
    if (node.textContent !== next) node.textContent = next;
  }

  function setAttr(node, name, value) {
    const next = value == null ? "" : String(value);
    if (node.getAttribute(name) !== next) node.setAttribute(name, next);
  }

  function listify(value) {
    if (Array.isArray(value)) return value;
    if (value == null) return [];
    if (typeof value === "string") return value ? [value] : [];
    if (typeof value[Symbol.iterator] === "function") return Array.from(value);

    if (typeof value === "object") {
      const numericKeys = Object.keys(value)
        .filter((key) => /^\d+$/.test(key))
        .sort((a, b) => Number(a) - Number(b));

      if (numericKeys.length) {
        return numericKeys.map((key) => value[key]);
      }

      return Object.values(value).filter((item) => item != null && typeof item !== "function");
    }

    return [value];
  }

  function toneFor(value) {
    const v = String(value || "").toLowerCase();
    if (["ready", "healthy", "running", "true", "ok", "live"].includes(v)) return "ok";
    if (["stopped", "disabled", "unknown", "missing", "daemon-unavailable", "false", "queued"].includes(v)) return "warn";
    if (["failed", "error", "not responding", "unreachable", "exited", "dead"].includes(v)) return "danger";
    return "muted";
  }

  // ====================================================================
  // toast
  // ====================================================================

  function toast(message, tone = "info") {
    const el = document.createElement("div");
    el.className = "toast";
    el.dataset.tone = tone;
    el.dataset.state = "enter";
    el.textContent = message;
    toastRegion.appendChild(el);

    requestAnimationFrame(() => {
      el.dataset.state = "visible";
      el.style.opacity = "";
      el.style.transform = "";
    });

    setTimeout(() => {
      el.dataset.state = "exit";
      setTimeout(() => el.remove(), 320);
    }, 2800);
  }

  // ====================================================================
  // routing
  // ====================================================================

  function currentRoute() {
    const hash = (location.hash || "").replace(/^#\/?/, "");
    return ROUTES.includes(hash) ? hash : "dashboard";
  }

  function moveTabIndicator(route) {
    const activeTab = tabs.find((t) => t.dataset.route === route);
    if (!activeTab) return;

    const tabsRect = tabsRoot.getBoundingClientRect();
    const tabRect = activeTab.getBoundingClientRect();
    const left = tabRect.left - tabsRect.left;

    tabIndicator.style.transform = `translateX(${left - 4}px)`;
    tabIndicator.style.width = `${tabRect.width}px`;
    tabsRoot.dataset.ready = "true";
  }

  function applyRoute() {
    const route = currentRoute();

    tabs.forEach((tab) => {
      const active = tab.dataset.route === route;
      tab.setAttribute("aria-selected", active ? "true" : "false");
    });

    $$(".page").forEach((page) => {
      page.hidden = page.dataset.page !== route;
    });

    moveTabIndicator(route);
  }

  window.addEventListener("hashchange", applyRoute);
  window.addEventListener("resize", () => moveTabIndicator(currentRoute()));

  // ====================================================================
  // fetch
  // ====================================================================

  async function api(path, options = {}) {
    const response = await fetch(path, {
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      ...options,
    });

    if (response.status === 401) {
      handleUnauthorized();
      throw new Error("unauthorized");
    }

    const isJson = (response.headers.get("Content-Type") || "").includes("application/json");
    const body = isJson ? await response.json() : null;

    if (!response.ok) {
      throw new Error(body && body.message ? body.message : `Request failed (${response.status})`);
    }

    return body;
  }

  function handleUnauthorized() {
    authenticated = false;
    closeStream();
    app.dataset.view = "login";
    setAttr(connectionDot, "data-state", "idle");
    requestAnimationFrame(() => loginSecret.focus());
  }

  // ====================================================================
  // status grid — stable DOM, in-place updates
  // ====================================================================

  const statusCards = new Map(); // id -> { root, dot, state, rows: Map<key, {row, val}> }

  function ensureStatusCard(id, title) {
    let card = statusCards.get(id);
    if (card) {
      setText(card.title, title);
      return card;
    }

    const root = document.createElement("article");
    root.className = "status-card";
    root.dataset.id = id;

    const head = document.createElement("div");
    head.className = "status-card-head";

    const dot = document.createElement("span");
    dot.className = "status-dot";
    dot.dataset.tone = "muted";

    const titleEl = document.createElement("h3");
    titleEl.textContent = title;

    const stateEl = document.createElement("span");
    stateEl.className = "status-state";

    head.appendChild(dot);
    head.appendChild(titleEl);
    head.appendChild(stateEl);

    const rows = document.createElement("div");
    rows.className = "status-rows";

    root.appendChild(head);
    root.appendChild(rows);
    statusGrid.appendChild(root);

    card = { root, dot, title: titleEl, state: stateEl, rowsRoot: rows, rows: new Map() };
    statusCards.set(id, card);
    return card;
  }

  function setCardTone(card, tone, stateLabel) {
    setAttr(card.dot, "data-tone", tone);
    setText(card.state, stateLabel);
  }

  function setCardRow(card, key, label, value, options = {}) {
    let row = card.rows.get(key);
    if (!row) {
      const rowEl = document.createElement("div");
      rowEl.className = "status-row";
      const keyEl = document.createElement("span");
      keyEl.className = "status-row-key";
      keyEl.textContent = label;
      const valEl = document.createElement("span");
      valEl.className = "status-row-val";
      rowEl.appendChild(keyEl);
      rowEl.appendChild(valEl);
      card.rowsRoot.appendChild(rowEl);
      row = { rowEl, valEl, keyEl };
      card.rows.set(key, row);
    }

    setText(row.keyEl, label);
    setText(row.valEl, value == null || value === "" ? "—" : value);
    if (options.title !== undefined) setAttr(row.valEl, "title", options.title);
  }

  function renderStatusCards(summary) {
    const m = summary.manager;
    const s = summary.stack;
    const t = summary.tailscale;

    {
      const c = ensureStatusCard("manager", "Manager");
      const tone = m.running ? "ok" : "danger";
      setCardTone(c, tone, m.running ? "Running" : "Stopped");
      setCardRow(c, "pid", "PID", m.pid || "—");
      setCardRow(c, "url", "Local", m.local_url, { title: m.local_url });
      setCardRow(c, "task", "Scheduled", m.scheduled_task_registered ? "yes" : "no");
    }
    {
      const c = ensureStatusCard("ollama", "Ollama");
      setCardTone(c, toneFor(s.ollama.ready), s.ollama.ready ? "Ready" : "Down");
      setCardRow(c, "version", "Version", s.ollama.version || "—");
    }
    {
      const c = ensureStatusCard("docker", "Docker");
      setCardTone(c, toneFor(s.docker.ready), s.docker.ready ? "Ready" : "Down");
      setCardRow(c, "engine", "Engine", s.docker.ready ? "running" : "unavailable");
    }
    {
      const c = ensureStatusCard("openwebui", "Open WebUI");
      setCardTone(c, toneFor(s.open_webui.health), String(s.open_webui.health));
      setCardRow(c, "reach", "Reachable", s.open_webui.local_reachable ? "yes" : "no");
      setCardRow(c, "patch", "Patch", s.open_webui.runtime_patch);
      setCardRow(c, "url", "URL", s.open_webui.local_url, { title: s.open_webui.local_url });
    }
    {
      const c = ensureStatusCard("tts", "Local TTS");
      const tone = !s.tts.enabled ? "muted" : toneFor(s.tts.health);
      setCardTone(c, tone, s.tts.enabled ? String(s.tts.health) : "Disabled");
      setCardRow(c, "enabled", "Enabled", s.tts.enabled ? "yes" : "no");
      setCardRow(c, "reach", "Reachable", s.tts.local_reachable ? "yes" : "no");
    }
    {
      const c = ensureStatusCard("tailscale", "Tailscale");
      setCardTone(c, toneFor(t.available), t.available ? "Available" : "Unavailable");
      setCardRow(c, "ui", "Open WebUI", t.https_url || "—", { title: t.https_url || "" });
      setCardRow(c, "mgr", "Manager", t.management_remote_url || "—", { title: t.management_remote_url || "" });
      setCardRow(c, "serve-ui", "Serve 443", t.open_webui ? (t.open_webui.configured_expected ? "yes" : "no") : "—");
      setCardRow(c, "serve-mgr", `Serve ${m.management_https_port}`, t.management ? (t.management.configured_expected ? "yes" : "no") : "—");
    }
    {
      const c = ensureStatusCard("models", "Models");
      const configured = listify(summary.models.configured).length;
      const installed = listify(summary.models.installed).length;
      const tone = installed >= configured && configured > 0 ? "ok" : (installed === 0 ? "warn" : "muted");
      setCardTone(c, tone, `${installed}/${configured}`);
      setCardRow(c, "configured", "Configured", configured);
      setCardRow(c, "installed", "Installed", installed);
    }
  }

  // ====================================================================
  // pending apply
  // ====================================================================

  function renderPending(summary) {
    const pending = summary && summary.jobs && summary.jobs.pending_apply;
    if (!pending || !pending.has_pending) {
      pendingBanner.hidden = true;
      return;
    }
    const steps = (pending.remaining_actions || []).join(" → ") || "no remaining steps";
    setText(pendingText, `${steps}. Saves persist config; nothing applies automatically.`);
    pendingBanner.hidden = false;
  }

  // ====================================================================
  // jobs
  // ====================================================================

  function renderJobs(snapshot) {
    if (!snapshot) return;

    const active = snapshot.current || snapshot.latest;
    const busy = snapshot.current && ["queued", "running"].includes(snapshot.current.status);

    // chip & action availability
    if (active) {
      const tone = toneFor(active.status);
      setAttr(jobStatusChip, "data-tone", tone);
      setText(jobStatusChip, active.status);
    } else {
      setAttr(jobStatusChip, "data-tone", "muted");
      setText(jobStatusChip, "Idle");
    }

    setText(actionState, busy ? "Busy" : "Ready");

    $$(".action-button").forEach((btn) => {
      btn.disabled = !!busy;
    });

    if (!active) {
      jobSummary.classList.add("muted");
      jobSummary.replaceChildren(document.createTextNode("No job has run yet."));
      setText(jobLog, "Logs appear here while a job runs.");
    } else {
      jobSummary.classList.remove("muted");
      const fields = [
        ["Action",   active.action],
        ["Status",   active.status],
        ["Created",  formatTime(active.created_at)],
        ["Started",  formatTime(active.started_at)],
        ["Finished", formatTime(active.finished_at)],
        ["Log",      active.log_relative_path],
      ];
      const frag = document.createDocumentFragment();
      fields.forEach(([k, v]) => {
        const wrap = document.createElement("div");
        const key = document.createElement("span");
        const val = document.createElement("span");
        key.textContent = k;
        val.textContent = v == null || v === "" ? "—" : v;
        val.title = String(v ?? "");
        wrap.appendChild(key);
        wrap.appendChild(val);
        frag.appendChild(wrap);
      });
      jobSummary.replaceChildren(frag);

      const tail = active.log_tail && active.log_tail.length ? active.log_tail.join("\n") : "Waiting for log output…";
      if (jobLog.textContent !== tail) {
        const atBottom = Math.abs(jobLog.scrollHeight - jobLog.clientHeight - jobLog.scrollTop) < 20;
        jobLog.textContent = tail;
        if (atBottom) jobLog.scrollTop = jobLog.scrollHeight;
      }
    }

    const history = snapshot.history || [];
    setText(jobHistoryCount, String(history.length));

    if (!history.length) {
      jobHistory.classList.add("muted");
      jobHistory.replaceChildren(document.createTextNode("No jobs yet."));
    } else {
      jobHistory.classList.remove("muted");
      const frag = document.createDocumentFragment();
      history.slice(0, 8).forEach((job) => {
        const li = document.createElement("li");

        const meta = document.createElement("div");
        meta.className = "history-meta";
        const dot = document.createElement("span");
        dot.className = "status-dot";
        dot.dataset.tone = toneFor(job.status);
        const action = document.createElement("span");
        action.className = "history-action";
        action.textContent = job.action;
        const status = document.createElement("span");
        status.className = "chip";
        status.dataset.tone = toneFor(job.status);
        status.textContent = job.status;

        meta.appendChild(dot);
        meta.appendChild(action);
        meta.appendChild(status);

        const time = document.createElement("span");
        time.className = "history-time";
        time.textContent = formatTime(job.finished_at) || formatTime(job.created_at) || "—";

        li.appendChild(meta);
        li.appendChild(time);
        frag.appendChild(li);
      });
      jobHistory.replaceChildren(frag);
    }

    // if a job just finished, refresh the heavy summary once
    if (pendingRefreshAfterAction && !busy) {
      pendingRefreshAfterAction = false;
      loadSummary({ silent: true }).catch(() => {});
    }
  }

  function formatTime(iso) {
    if (!iso) return "";
    try {
      const d = new Date(iso);
      if (Number.isNaN(d.getTime())) return iso;
      return d.toLocaleString(undefined, { hour12: false });
    } catch {
      return iso;
    }
  }

  // ====================================================================
  // config / models
  // ====================================================================

  function renderConfigForm(editable) {
    if (configDirty) return;
    const els = configForm.elements;
    if (els.openwebui_image_tag.value !== (editable.openwebui_image_tag || "")) els.openwebui_image_tag.value = editable.openwebui_image_tag || "";
    if (els.voice_vision_model.value !== (editable.voice_vision_model || "")) els.voice_vision_model.value = editable.voice_vision_model || "";
    if (els.voice_vision_fallback_model.value !== (editable.voice_vision_fallback_model || "")) els.voice_vision_fallback_model.value = editable.voice_vision_fallback_model || "";
    els.tts_enabled.checked = !!editable.tts.enabled;
    if (els.tts_default_voice.value !== (editable.tts.default_voice || "")) els.tts_default_voice.value = editable.tts.default_voice || "";
    if (els.tts_fallback_voice.value !== (editable.tts.fallback_voice || "")) els.tts_fallback_voice.value = editable.tts.fallback_voice || "";
    if (els.stt_model.value !== (editable.stt.model || "")) els.stt_model.value = editable.stt.model || "";
    if (els.stt_language.value !== (editable.stt.language || "")) els.stt_language.value = editable.stt.language || "";
    els.stt_auto_update.checked = !!editable.stt.auto_update;
  }

  function renderReadOnly(readOnly) {
    const entries = Object.entries(readOnly || {});
    const frag = document.createDocumentFragment();
    entries.forEach(([key, value]) => {
      const item = document.createElement("div");
      item.className = "readonly-item";
      const k = document.createElement("span");
      k.className = "key";
      k.textContent = key;
      const v = document.createElement("span");
      v.className = "val";
      v.textContent = value == null || value === "" ? "—" : String(value);
      item.appendChild(k);
      item.appendChild(v);
      frag.appendChild(item);
    });
    configReadOnly.replaceChildren(frag);
  }

  function renderModels(models) {
    if (!modelsDirty) {
      const next = (models.configured || []).join("\n");
      if (modelsTextarea.value !== next) modelsTextarea.value = next;
    }

    const installed = models.installed || [];
    if (!installed.length) {
      installedModels.replaceChildren(Object.assign(document.createElement("li"), {
        className: "empty", textContent: "No installed models",
      }));
      return;
    }
    const frag = document.createDocumentFragment();
    installed.forEach((m) => {
      const li = document.createElement("li");
      li.textContent = m;
      frag.appendChild(li);
    });
    installedModels.replaceChildren(frag);
  }

  // ====================================================================
  // summary
  // ====================================================================

  function renderSummary(summary) {
    latestSummary = summary;
    lastSummaryAt = Date.now();
    renderStatusCards(summary);
    renderPending(summary);
    renderConfigForm(summary.config.editable);
    renderReadOnly(summary.config.read_only);
    renderModels(summary.models);
    renderJobs(summary.jobs);
  }

  function loadSummary(options = {}) {
    if (summaryInFlight) return summaryInFlight;
    if (!options.silent) refreshButton.dataset.spin = "true";

    summaryInFlight = api("/api/summary", { method: "GET" })
      .then((summary) => {
        authenticated = true;
        if (app.dataset.view !== "app") {
          app.dataset.view = "app";
          requestAnimationFrame(() => moveTabIndicator(currentRoute()));
        }
        renderSummary(summary);
        ensureEventStream();
      })
      .catch((err) => {
        if (err.message !== "unauthorized") {
          console.error(err);
          if (!options.silent) toast(err.message || "Failed to refresh", "error");
        }
      })
      .finally(() => {
        summaryInFlight = null;
        delete refreshButton.dataset.spin;
      });

    return summaryInFlight;
  }

  // ====================================================================
  // SSE
  // ====================================================================

  function closeStream() {
    if (eventSource) {
      try { eventSource.close(); } catch {}
      eventSource = null;
    }
  }

  function ensureEventStream() {
    if (!authenticated || eventSource) return;

    eventSource = new EventSource("/api/jobs/stream", { withCredentials: true });
    setAttr(connectionDot, "data-state", "live");

    eventSource.addEventListener("update", (event) => {
      try {
        const payload = JSON.parse(event.data);
        if (latestSummary) latestSummary.jobs = payload;
        renderJobs(payload);
        renderPending({ jobs: payload });
        setAttr(connectionDot, "data-state", "live");
      } catch (err) {
        console.error(err);
      }
    });

    eventSource.onerror = () => {
      closeStream();
      setAttr(connectionDot, "data-state", "stale");
      if (authenticated) setTimeout(ensureEventStream, 2000);
    };
  }

  // ====================================================================
  // submits & actions
  // ====================================================================

  async function submitConfig(event) {
    event.preventDefault();
    const els = configForm.elements;
    const payload = {
      openwebui_image_tag: els.openwebui_image_tag.value.trim(),
      voice_vision_model: els.voice_vision_model.value.trim(),
      voice_vision_fallback_model: els.voice_vision_fallback_model.value.trim(),
      tts: {
        enabled: els.tts_enabled.checked,
        default_voice: els.tts_default_voice.value.trim(),
        fallback_voice: els.tts_fallback_voice.value.trim(),
      },
      stt: {
        model: els.stt_model.value.trim(),
        language: els.stt_language.value.trim(),
        auto_update: els.stt_auto_update.checked,
      },
    };

    try {
      await api("/api/config", { method: "PUT", body: JSON.stringify(payload) });
      configDirty = false;
      configForm.classList.remove("field-dirty");
      toast("Runtime config saved.", "ok");
      loadSummary({ silent: true });
    } catch (err) {
      toast(err.message || "Failed to save config", "error");
    }
  }

  async function submitModels(event) {
    event.preventDefault();
    try {
      const models = modelsTextarea.value
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean);

      const response = await api("/api/models", {
        method: "PUT",
        body: JSON.stringify({
          models,
          uninstall_removed: !!modelsUninstallRemoved.checked,
        }),
      });

      modelsDirty = false;
      modelsForm.classList.remove("field-dirty");

      if (modelsUninstallRemoved.checked) {
        modelsUninstallRemoved.checked = false;
      }

      if (response && response.uninstall_result && response.uninstall_result.error) {
        toast(`Model list saved, but uninstall failed: ${response.uninstall_result.error}`, "error");
      } else if (response && response.uninstall_removed && response.uninstall_result) {
        const removedModels = listify(response.uninstall_result.removed);

        if (removedModels.length) {
          toast(`Model list saved. Uninstalled: ${removedModels.join(", ")}`, "ok");
        } else {
          toast("Model list saved.", "ok");
        }
      } else {
        toast("Model list saved.", "ok");
      }

      loadSummary({ silent: true });
    } catch (err) {
      toast(err.message || "Failed to save models", "error");
    }
  }

  async function login(event) {
    event.preventDefault();
    setText(loginError, "");

    try {
      await api("/api/auth/login", { method: "POST", body: JSON.stringify({ secret: loginSecret.value }) });
      loginSecret.value = "";
      await loadSummary();
    } catch (err) {
      setText(loginError, err.message || "Sign in failed");
    }
  }

  async function logout() {
    try {
      await api("/api/auth/logout", { method: "POST", body: "{}" });
    } catch (err) {
      console.error(err);
    }
    handleUnauthorized();
  }

  function actionIsDangerous(name) {
    return name === "manager-stop";
  }

  async function runAction(name) {
    if (actionIsDangerous(name) && !window.confirm("This action will take the manager offline. Continue?")) return;

    try {
      await api(`/api/actions/${name}`, { method: "POST", body: "{}" });
      pendingRefreshAfterAction = true;
      toast(`Started: ${name}`, "ok");
    } catch (err) {
      toast(err.message || "Failed to start action", "error");
    }
  }

  // ====================================================================
  // dirty tracking
  // ====================================================================

  function markConfigDirty() {
    configDirty = true;
    configForm.classList.add("field-dirty");
  }

  function markModelsDirty() {
    modelsDirty = true;
    modelsForm.classList.add("field-dirty");
  }

  function resetConfigForm() {
    if (latestSummary) {
      configDirty = false;
      configForm.classList.remove("field-dirty");
      renderConfigForm(latestSummary.config.editable);
    }
  }

  function resetModelsForm() {
    if (latestSummary) {
      modelsDirty = false;
      modelsForm.classList.remove("field-dirty");
      renderModels(latestSummary.models);
    }

    if (modelsUninstallRemoved) {
      modelsUninstallRemoved.checked = false;
    }
  }

  // ====================================================================
  // visibility-aware refresh — only when user actually looks
  // ====================================================================

  function onVisibilityChange() {
    if (!authenticated) return;
    if (document.visibilityState !== "visible") return;
    if (Date.now() - lastSummaryAt > 30_000) {
      loadSummary({ silent: true });
    }
  }

  const originalRenderPending = renderPending;
  renderPending = function (summary) {
    if (summary && summary.jobs && summary.jobs.pending_apply) {
      summary.jobs.pending_apply.remaining_actions = listify(summary.jobs.pending_apply.remaining_actions);
    }

    return originalRenderPending(summary);
  };

  const originalRenderJobs = renderJobs;
  renderJobs = function (snapshot) {
    if (snapshot && snapshot.current) {
      snapshot.current.log_tail = listify(snapshot.current.log_tail);
    }

    if (snapshot && snapshot.latest) {
      snapshot.latest.log_tail = listify(snapshot.latest.log_tail);
    }

    if (snapshot && Array.isArray(snapshot.history)) {
      snapshot.history.forEach((job) => {
        if (job) {
          job.log_tail = listify(job.log_tail);
        }
      });
    }

    return originalRenderJobs(snapshot);
  };

  const originalRenderModels = renderModels;
  renderModels = function (models) {
    if (models) {
      models.configured = listify(models.configured);
      models.installed = listify(models.installed);
    }

    return originalRenderModels(models);
  };

  // ====================================================================
  // wire up
  // ====================================================================

  loginForm.addEventListener("submit", login);
  configForm.addEventListener("submit", submitConfig);
  modelsForm.addEventListener("submit", submitModels);
  refreshButton.addEventListener("click", () => loadSummary());
  logoutButton.addEventListener("click", logout);

  $$(".action-button").forEach((btn) => {
    btn.addEventListener("click", () => runAction(btn.dataset.action));
  });

  configForm.addEventListener("input", markConfigDirty);
  configForm.addEventListener("change", markConfigDirty);
  modelsTextarea.addEventListener("input", markModelsDirty);

  $$('[data-action-form="reset-config"]').forEach((b) => b.addEventListener("click", resetConfigForm));
  $$('[data-action-form="reset-models"]').forEach((b) => b.addEventListener("click", resetModelsForm));

  document.addEventListener("visibilitychange", onVisibilityChange);
  window.addEventListener("beforeunload", closeStream);
  window.addEventListener("pagehide", closeStream);

  applyRoute();
  loadSummary().then(() => {
    if (!authenticated) loginSecret.focus();
  });
})();
