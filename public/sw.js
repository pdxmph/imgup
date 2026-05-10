// imgup service worker.
//
// Caches the static shell on install, serves cache-first for shell paths,
// network-only for /api/*, passthrough for everything else. On a same-origin
// fetch returning an opaque-redirect (Cloudflare Access session expired),
// converts the failed fetch into a top-level navigation so the browser can
// follow Access's challenge instead of resolving to a broken Response.

const CACHE_VERSION = "2026-05-09-10"; // bump when shipping frontend changes
const CACHE_NAME = `imgup-shell-v${CACHE_VERSION}`;

const SHELL = [
  "/",
  "/app.js",
  "/style.css",
  "/manifest.webmanifest",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/icon-512-maskable.png",
  "/icons/apple-touch-icon-180.png",
];

const SHELL_SET = new Set(SHELL);

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then(async (names) => {
      await Promise.all(
        names
          .filter((n) => n.startsWith("imgup-shell-v") && n !== CACHE_NAME)
          .map((n) => caches.delete(n))
      );
      await self.clients.claim();
      // Force-reload any controlled windows so they pick up the new shell on
      // the same launch, instead of needing a second force-quit + relaunch.
      try {
        const wins = await self.clients.matchAll({ type: "window" });
        await Promise.all(wins.map((c) => c.navigate(c.url).catch(() => {})));
      } catch {}
    })
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // /api/* — network only, with Access-redirect detection.
  if (url.pathname.startsWith("/api/")) {
    event.respondWith(networkOnlyWithAccessFallback(request));
    return;
  }

  // Shell paths — cache first, fall back to network.
  const shellPath = url.pathname === "/index.html" ? "/" : url.pathname;
  if (SHELL_SET.has(shellPath)) {
    event.respondWith(cacheFirst(shellPath, request));
    return;
  }

  // Anything else — passthrough.
});

async function cacheFirst(shellPath, request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(shellPath);
  if (cached) return cached;
  const network = await fetch(request);
  if (network.ok) cache.put(shellPath, network.clone()).catch(() => {});
  return network;
}

async function networkOnlyWithAccessFallback(request) {
  const response = await fetch(request);
  if (response.type === "opaqueredirect" || response.status === 0) {
    // Cloudflare Access redirected; bounce to a top-level nav so the browser
    // can follow the challenge.
    return Response.redirect(request.url, 302);
  }
  return response;
}
