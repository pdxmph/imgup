# imgup

Personal SmugMug uploader running on a Cloudflare Worker.

Drop a photo in the browser, get back markdown / HTML / org snippets, paste into a blog post.

## Run locally

    npm install
    cp .dev.vars.example .dev.vars   # then fill in values
    npm run dev

## Deploy

    npm run deploy

Production lives at <https://imgup.puddingtime.net>, gated by Cloudflare Access.

## Shipping a frontend change

`public/sw.js` caches the shell so the PWA loads instantly on subsequent visits. When you change `index.html`, `app.js`, `style.css`, or any icon, bump the cache version so returning users pick up the change:

1. Edit the relevant frontend file.
2. In `public/sw.js`, bump `CACHE_VERSION` (e.g. `"2026-05-09-1"` → `"2026-05-09-2"`).
3. `npm run deploy`.

Worker-only changes (anything in `worker/`) don't need a cache bump — the cached shell is identical; only the API behaviour changes.

## Regenerating icons

When you edit `public/icons/imgup.svg`, run `npm run icons` to refresh the PNGs, then commit them. The rasterizer uses `sharp`; PNGs are committed to the repo (no build-time generation on deploy).

## Repo layout

- `worker/` — TypeScript Worker (entrypoint at `worker/index.ts`)
- `public/` — static SPA served via Workers Static Assets
- `test/`   — vitest unit tests
- `docs/superpowers/` — design specs and implementation plans

The Ruby/Sinatra version that previously ran on Synology is preserved on the `legacy-ruby` branch.
