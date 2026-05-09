# imgup PWA shell

## Goal

Make imgup installable on iOS and Android home screens and Desktop app shelves, with a service worker that caches the static shell so the app loads instantly on subsequent visits. Same JSON API, same Worker, same Cloudflare Access. No offline upload queue — the shell, no more.

## Non-goals

- Offline-tolerant uploads (Background Sync). Listed in the migration spec as a future; not part of this scope.
- `share_target` / `file_handlers` integrations.
- Push notifications.
- Hand-crafted iOS splash screens. iOS 16+ generates these from the manifest.
- Workbox or other PWA frameworks. The hand-rolled service worker is small enough not to need one.

## Architecture

Three new artifacts in `public/`, plus head-tag additions in `index.html` and a service-worker registration call in `app.js`.

```
public/
├── manifest.webmanifest          # PWA manifest (JSON)
├── sw.js                         # service worker (vanilla JS)
├── icons/
│   ├── imgup.svg                 # source mark — single artifact you edit
│   ├── icon-192.png              # generated from svg
│   ├── icon-512.png              # generated from svg
│   ├── icon-512-maskable.png     # Android adaptive-icon variant w/ safe zone
│   └── apple-touch-icon-180.png  # iOS home screen
├── index.html                    # adds <link rel="manifest"> + apple-touch-icon meta + theme-color meta
├── app.js                        # adds navigator.serviceWorker.register("/sw.js")
└── style.css                     # unchanged
scripts/
└── render-icons.mjs              # one-shot rasterizer (manual, run after editing imgup.svg)
package.json                      # adds "icons" npm script and `sharp` devDependency
```

`sw.js` lives at the static-asset root so its scope claim is `/`. No bundler. Workers Static Assets serves it the same way it serves `index.html`.

## Components

### `public/manifest.webmanifest`

```json
{
  "name": "imgup",
  "short_name": "imgup",
  "description": "personal smugmug uploader",
  "start_url": "/#upload",
  "scope": "/",
  "display": "standalone",
  "orientation": "any",
  "background_color": "#1a1110",
  "theme_color": "#1a1110",
  "icons": [
    { "src": "/icons/icon-192.png",          "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-512.png",          "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-512-maskable.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

Choices:

- `start_url: "/#upload"` — opens straight to the upload view via the existing hash router.
- `display: standalone` — no browser chrome when launched from the home screen.
- `theme_color` and `background_color` set to the dark-theme background hex (`#1a1110`, sRGB approximation of `oklch(13% 0.025 25)`) so the iOS status bar and Android splash blend with the app rather than flashing white. Light-mode users see a half-second dark splash on launch — accepted trade.
- Three icon entries: two `purpose: any` (192/512) and one `purpose: maskable` (512) so Android's adaptive-icon mask doesn't clip the crop-mark corners. The maskable variant has 25% safe-zone padding baked in.
- No `share_target` or `file_handlers` — out of scope (see follow-ups).

### `public/index.html` head-tag additions

Add inside `<head>`, immediately after the inline theme `<script>` (so the manifest and apple-touch links land at the bottom of the head, just before `</head>`):

```html
<link rel="manifest" href="/manifest.webmanifest" />
<meta name="theme-color" content="#1a1110" />
<link rel="apple-touch-icon" href="/icons/apple-touch-icon-180.png" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<meta name="apple-mobile-web-app-title" content="imgup" />
```

Nothing else in `index.html` changes.

### `public/app.js` registration

At the bottom of the existing file (after the `initDropTarget` block, outside any function), add:

```js
// register the service worker. fire-and-forget; failure is non-fatal.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch((err) => {
      console.warn("sw register failed:", err);
    });
  });
}
```

### `public/sw.js`

Vanilla JS service worker, ~80 lines. Three responsibilities:

**1. Pre-cache the shell on install.**

```js
const CACHE_VERSION = "2026-05-09-1"; // bump when shipping frontend changes
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
```

CDN-hosted assets (SimpleCSS, Fraunces, IBM Plex Mono, FontAwesome) are not cached by the SW — their own long max-age headers + the browser HTTP cache handle them.

**2. Fetch handling.**

- Same-origin GET to a path in `SHELL` → cache-first, fall back to network. On cache miss with successful network, write back to cache.
- `/api/*` → network-only, no caching. (User data; the Worker's edge cache is server-side authoritative.)
- Anything else → passthrough (`fetch(event.request)`).

**3. Update lifecycle.**

- `install`: open the versioned cache, `cache.addAll(SHELL)`, then `self.skipWaiting()`.
- `activate`: enumerate cache names, delete any that doesn't match `CACHE_NAME`, then `clients.claim()`.

**Cloudflare Access compatibility.**

While the `CF_AppSession` cookie is valid (24h default), all fetches succeed transparently — the SW is unaware Access exists. When the cookie expires while the PWA is open, the next `fetch("/api/...")` returns a 302 to `*.cloudflareaccess.com`. The SW detects this and bounces to a top-level navigation:

```js
if (response.type === "opaqueredirect" || response.status === 0) {
  // session expired — bounce to Access challenge
  return Response.redirect(event.request.url, 302);
}
```

This makes Cloudflare re-issue the challenge on a top-level navigation, which the browser handles natively (Access page → login → back to app). The shell HTML stays cache-first, so the app *opens* fine even with an expired session; only the first API call triggers re-auth.

**Cache-Control on `/sw.js` itself.**

The SW file must not be HTTP-cached aggressively, or browsers won't notice version bumps. Workers Static Assets defaults `Cache-Control: public, max-age=0, must-revalidate` for unknown extensions, which is what we want; no Worker-side override needed. Verify in production that `/sw.js` returns this header (or `no-cache`) — if Cloudflare's CDN over-caches it, set an explicit header from the Worker.

### `public/icons/imgup.svg`

Hand-rolled SVG: warm-paper background, four oxblood crop-mark corner brackets, a centered lowercase `i` in IBM Plex Mono semi-bold oxblood. Single source of truth — edit this, re-run `npm run icons` to regenerate the four PNGs.

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="imgup">
  <rect width="512" height="512" fill="#f1e5cf"/>
  <g stroke="#a3393a" stroke-width="14" fill="none">
    <path d="M 80 80 L 80 160 M 80 80 L 160 80"/>
    <path d="M 432 80 L 432 160 M 432 80 L 352 80"/>
    <path d="M 80 432 L 80 352 M 80 432 L 160 432"/>
    <path d="M 432 432 L 432 352 M 432 432 L 352 432"/>
  </g>
  <text x="256" y="345"
        font-family="'IBM Plex Mono', ui-monospace, monospace"
        font-weight="600"
        font-size="280"
        fill="#a3393a"
        text-anchor="middle">i</text>
</svg>
```

Colors are sRGB approximations of the OKLCH design tokens (`oklch(96% 0.018 75)` → `#f1e5cf` warm paper; `oklch(60% 0.180 25)` → `#a3393a` oxblood). Tune during implementation if the rendered PNG looks off; tweak inside the SVG and rerun the rasterizer.

### `scripts/render-icons.mjs`

Reads `public/icons/imgup.svg`, writes four PNGs:

- `icon-192.png` — 192×192, full SVG.
- `icon-512.png` — 512×512, full SVG.
- `icon-512-maskable.png` — 512×512, SVG composited at 65% scale on the warm-paper background (Android safe zone).
- `apple-touch-icon-180.png` — 180×180, full SVG.

Uses `sharp` (added as a devDependency). Manual one-shot — invoked via `npm run icons` after editing the SVG, output PNGs are committed to the repo. Not part of `npm run deploy` so deploy stays fast and PNG drift is intentional, not accidental.

## Cloudflare Access edge cases

| Scenario                                                | Behavior                                                                                       |
|---------------------------------------------------------|------------------------------------------------------------------------------------------------|
| Cookie valid, app open, user uses normally              | All fetches transparent. SW caches shell, network for API. Indistinguishable from no-PWA case. |
| Cookie expires while app open, user idle                | Nothing happens until next API call.                                                           |
| Cookie expires while app open, user uploads             | SW detects 302 redirect → top-level nav to API URL → Access challenges → user re-auths → app reloads at the URL → user retries upload. |
| First-ever visit while not authed                       | Cloudflare Access intercepts at edge, before the Worker. SW is never registered. User auths first, then app loads, then SW installs. |
| User clears cookies / logs out                          | Same as cookie expiry. Next API call triggers Access challenge.                                |

## Versioning workflow

Bumping `CACHE_VERSION` in `sw.js` is the single step needed to ship a frontend change. Format: `YYYY-MM-DD-N` (e.g. `"2026-05-09-1"`). Manual — no build-time injection.

When shipping a frontend change:

1. Edit the relevant frontend file (`index.html`, `app.js`, or `style.css`).
2. Edit `public/sw.js` — bump `CACHE_VERSION` (e.g. `"2026-05-09-1"` → `"2026-05-09-2"`).
3. `npm run deploy`.
4. On the visitor's next visit: the browser refetches `/sw.js`, sees byte-difference, installs as the waiting worker, activates on the same page load via `skipWaiting()` + `clients.claim()`, evicts the old cache.

When shipping a backend (Worker) change with no frontend change: don't bump `CACHE_VERSION`. The cached shell is identical; only the Worker code changes.

When editing the SVG icon: `npm run icons` regenerates PNGs, commit, then ship as a frontend change (bump `CACHE_VERSION` so the PWA refetches the new icon assets).

Forgetting to bump means returning users see the old cached shell until they force-reload — recoverable but annoying. If this becomes a foot-gun, revisit with a pre-deploy `sed` substitution. Not worth the build-step complexity today.

## Testing & verification

- **No vitest unit tests.** The new code is a service worker (only runs in browser SW context) and declarative JSON. Vitest can't meaningfully cover either. Existing 10 tests must continue to pass — no regression. `npm run typecheck` stays clean (sw.js is plain JS, no TS coverage).
- **Desktop smoke (Chrome):** DevTools → Application → Service Workers shows `sw.js` registered with scope `/`. Manifest tab shows all fields populate. Lighthouse PWA audit passes "Installable" + clean PWA score. After one refresh, Network tab shows `/`, `/app.js`, `/style.css` served from `(ServiceWorker)` not the Worker.
- **iOS smoke:** Open production via Access in Safari. Share → Add to Home Screen. Confirm (a) right icon, (b) launches in standalone (no browser chrome), (c) upload + recent + copy buttons all work as in-browser.
- **Android smoke:** Chrome shows the install prompt automatically once installability criteria are met. Install, launch, repeat the iOS confirmations.
- **Cache invalidation rehearsal:** bump `CACHE_VERSION`, deploy, reload the PWA twice (first reload installs new SW, second activates and serves from new cache). DevTools → Cache Storage shows old `imgup-shell-v…` cache deleted, new one populated.
- **Access expiry rehearsal:** open the PWA, manually delete the `CF_AppSession` cookie in DevTools, attempt an upload. Confirm the app navigates to the Access challenge instead of throwing a JSON parse error.

## Errors

| Source                              | Behavior                                                                                  |
|-------------------------------------|-------------------------------------------------------------------------------------------|
| `navigator.serviceWorker.register` rejects | Console warning, app continues to work without SW. Non-fatal.                              |
| SW `install` fails to cache shell   | SW does not activate. Old cached version (if any) keeps serving. App still works without SW. |
| SW `fetch` handler throws           | Browser falls back to default network behavior — equivalent to no SW.                      |
| Network error during cache-first fallback | Throws to the page; same UX as a network failure today.                                    |

## Out-of-scope follow-ups

Listed for the spec's record so the shell stays a shell:

- **Offline upload queue** via Background Sync. iOS support is poor; revisit when a real workflow needs it.
- **`share_target`.** "Share to imgup" from Photos.app or the Android share sheet — drops the user into the upload form with the photo pre-attached. Real workflow win for mobile; keep on the list.
- **`file_handlers`.** Register imgup as a handler for `.jpg/.png/.heic` so OS file pickers can launch the upload form pre-attached. Desktop niche.
- **Push notifications.** No use case identified.
- **Hand-crafted iOS splash images per device size.** iOS 16+ does this automatically from the manifest. Manual splash files only if the auto version proves wrong.
- **Build-time `CACHE_VERSION` injection** (git SHA via pre-deploy `sed`). Adopt only if manual bumps prove forgettable.
