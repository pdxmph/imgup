// imgup frontend wiring.
//
// SmugMug upload + recent grid + carry-over interactions (copy buttons,
// lightbox, drop-target) ported verbatim from the Sinatra-era layout.haml
// inline scripts — keep behavior parity.

const RECENT_COUNT = 10; // must match worker CACHED_COUNTS in worker/index.ts
const VIEWS = ["upload", "result", "recent"];

document.addEventListener("DOMContentLoaded", () => {
  initCopyButtons();
  initLightbox();
  initDropTarget();
  initUploadForm();
  initRouter();
  loadRecent();
});

// ---------- routing ----------

function initRouter() {
  applyRoute();
  window.addEventListener("hashchange", applyRoute);
}

function applyRoute() {
  const hash = (location.hash || "#upload").replace(/^#/, "");
  const target = VIEWS.includes(hash) ? hash : "upload";

  // Don't land on #result without a result to show — bounce back to upload.
  if (target === "result" && !document.getElementById("result-thumb").src) {
    location.hash = "#upload";
    return;
  }

  VIEWS.forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.hidden = id !== target;
  });

  document.querySelectorAll("body > header nav a").forEach((a) => {
    const li = a.closest("li");
    if (li) li.hidden = a.getAttribute("href") === `#${target}`;
  });
}

// ---------- upload ----------

function initUploadForm() {
  const form = document.getElementById("upload-form");
  const fileInput = document.getElementById("upload-file");
  const titleInput = document.getElementById("upload-title");
  const captionInput = document.getElementById("upload-caption");
  const submit = document.getElementById("upload-submit");
  const status = document.getElementById("upload-status");
  const result = document.getElementById("result");
  const MAX = 150 * 1024 * 1024; // 150 MB

  form.addEventListener("submit", async (e) => {
    e.preventDefault();

    if (!fileInput.files || !fileInput.files[0]) {
      alert("pick a file first.");
      return;
    }
    const f = fileInput.files[0];
    if (f.size > MAX) {
      alert(`that file is ${Math.round(f.size / 1024 / 1024)} MB. cap is 150 MB.`);
      return;
    }
    if (!/^image\//.test(f.type)) {
      alert(`that is not an image. (${f.type || "unknown type"})`);
      return;
    }

    submit.disabled = true;
    submit.value = "uploading…";
    status.classList.add("is-active");
    result.hidden = true;

    try {
      const fd = new FormData();
      fd.append("file", f);
      fd.append("title", titleInput.value || "");
      fd.append("caption", captionInput.value || "");

      const resp = await fetch("/api/upload", { method: "POST", body: fd });
      const body = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(body.error || `HTTP ${resp.status}`);

      renderResult(body);
      form.reset();
      location.hash = "#result";
      await loadRecent();
    } catch (err) {
      alert(`upload failed: ${err.message}`);
    } finally {
      submit.disabled = false;
      submit.value = "upload";
      status.classList.remove("is-active");
    }
  });
}

function renderResult({ url, markdown, html, org }) {
  const result = document.getElementById("result");
  const photoBtn = document.getElementById("result-photo");
  const thumb = document.getElementById("result-thumb");

  thumb.src = url;
  thumb.alt = "uploaded photo";
  photoBtn.dataset.lightboxSrc = url;
  photoBtn.dataset.lightboxAlt = "just-uploaded photo";

  const buttons = result.querySelectorAll(".copy-icon-btn");
  buttons.forEach((btn) => {
    const target = btn.dataset.copyTarget;
    if (target === "md") btn.dataset.copyText = markdown;
    else if (target === "org") btn.dataset.copyText = org;
    else if (target === "html") btn.dataset.copyText = html;
  });

  // visibility is controlled by the router; just populate fields here.
}

// ---------- recent ----------

async function loadRecent() {
  const grid = document.getElementById("recent-grid");
  const empty = document.getElementById("recent-empty");
  grid.textContent = "";
  empty.hidden = true;

  try {
    const resp = await fetch(`/api/recent?count=${RECENT_COUNT}`);
    if (!resp.ok) {
      const j = await resp.json().catch(() => ({}));
      grid.textContent = `error loading recent: ${j.error || resp.status}`;
      return;
    }
    const items = await resp.json();
    if (items.length === 0) {
      empty.hidden = false;
      return;
    }
    items.forEach((r, i) => grid.appendChild(renderRecentCard(r, i)));
  } catch (err) {
    grid.textContent = `error loading recent: ${err.message}`;
  }
}

function renderRecentCard(r, idx) {
  const cap = r.caption || "";
  const url = r.image_url;
  const md = `![${cap}](${url})`;
  const org = `[[img:${url}][${cap}]]`;
  const html = `<img src='${url}' alt='${cap}' />`;

  const article = document.createElement("article");
  article.className = "contact-card";

  const seq = document.createElement("span");
  seq.className = "contact-card__seq";
  seq.textContent = String(idx + 1).padStart(2, "0");
  article.appendChild(seq);

  const photoBtn = document.createElement("button");
  photoBtn.type = "button";
  photoBtn.className = "contact-card__photo";
  photoBtn.dataset.lightboxSrc = url;
  photoBtn.dataset.lightboxAlt = cap;
  photoBtn.setAttribute("aria-label", `view ${cap || "photo"} larger`);

  const frame = document.createElement("span");
  frame.className = "photo-frame";
  const img = document.createElement("img");
  img.className = "contact-card__thumb";
  img.src = r.thumb;
  img.alt = cap;
  img.loading = "lazy";
  frame.appendChild(img);
  photoBtn.appendChild(frame);
  article.appendChild(photoBtn);

  const copyRow = document.createElement("div");
  copyRow.className = "contact-card__copy-row";
  copyRow.appendChild(makeCopyButton(md, "copy markdown", "fa-brands fa-markdown"));
  copyRow.appendChild(makeCopyButton(org, "copy org", "fa-solid fa-asterisk"));
  copyRow.appendChild(makeCopyButton(html, "copy html", "fa-solid fa-code"));
  article.appendChild(copyRow);

  return article;
}

function makeCopyButton(text, label, iconClass) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = "copy-icon-btn";
  btn.dataset.copyText = text;
  btn.setAttribute("aria-label", label);
  btn.title = label;
  const icon = document.createElement("i");
  icon.className = iconClass;
  btn.appendChild(icon);
  return btn;
}

// ---------- copy buttons (ported verbatim from layout.haml) ----------

function initCopyButtons() {
  document.addEventListener("click", (e) => {
    const btn = e.target.closest(".copy-icon-btn");
    if (!btn) return;
    e.preventDefault();
    const text = btn.dataset.copyText;
    if (text === undefined) return;

    const done = (ok) => {
      btn.classList.toggle("is-copied", ok);
      btn.classList.toggle("is-failed", !ok);
      setTimeout(() => btn.classList.remove("is-copied", "is-failed"), 1400);
    };

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => done(true), () => done(false));
    } else {
      try {
        const ta = document.createElement("textarea");
        ta.value = text;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        const ok = document.execCommand("copy");
        document.body.removeChild(ta);
        done(ok);
      } catch (err) {
        done(false);
      }
    }
  });
}

// ---------- lightbox (ported verbatim from layout.haml) ----------

function initLightbox() {
  const dialog = document.getElementById("lightbox");
  if (!dialog) return;
  const img = dialog.querySelector(".lightbox__img");
  const closeBtn = dialog.querySelector(".lightbox__close");

  document.addEventListener("click", (e) => {
    const trigger = e.target.closest(".contact-card__photo");
    if (!trigger) return;
    const src = trigger.dataset.lightboxSrc;
    const alt = trigger.dataset.lightboxAlt || "";
    if (!src) return;
    img.src = src;
    img.alt = alt;
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "open");
  });

  dialog.addEventListener("click", (e) => {
    if (e.target === dialog) dialog.close();
  });
  if (closeBtn) closeBtn.addEventListener("click", () => dialog.close());
  dialog.addEventListener("close", () => {
    img.src = "";
    img.alt = "";
  });
}

// ---------- drop target (ported verbatim from layout.haml) ----------

function initDropTarget() {
  const form = document.getElementById("upload-form");
  const fileInput = document.getElementById("upload-file");
  if (!form || !fileInput) return;
  let depth = 0;
  const setActive = (on) => form.classList.toggle("is-drop-target", !!on);

  ["dragenter", "dragover"].forEach((ev) => {
    form.addEventListener(ev, (e) => {
      if (!e.dataTransfer || !Array.from(e.dataTransfer.types || []).includes("Files")) return;
      e.preventDefault();
      if (ev === "dragenter") depth++;
      setActive(true);
    });
  });
  form.addEventListener("dragleave", () => {
    depth = Math.max(0, depth - 1);
    if (depth === 0) setActive(false);
  });
  form.addEventListener("drop", (e) => {
    if (!e.dataTransfer || !e.dataTransfer.files || !e.dataTransfer.files.length) return;
    e.preventDefault();
    depth = 0;
    setActive(false);
    const dt = new DataTransfer();
    dt.items.add(e.dataTransfer.files[0]);
    fileInput.files = dt.files;
    fileInput.dispatchEvent(new Event("change", { bubbles: true }));
  });
  ["dragover", "drop"].forEach((ev) => {
    window.addEventListener(ev, (e) => {
      if (e.dataTransfer && Array.from(e.dataTransfer.types || []).includes("Files")) {
        if (!form.contains(e.target)) e.preventDefault();
      }
    });
  });
}

// ---------- service worker ----------

// Fire-and-forget registration. Failure is non-fatal — the app works without it.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch((err) => {
      console.warn("sw register failed:", err);
    });
  });
}
