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

## Repo layout

- `worker/` — TypeScript Worker (entrypoint at `worker/index.ts`)
- `public/` — static SPA served via Workers Static Assets
- `test/`   — vitest unit tests
- `docs/superpowers/` — design specs and implementation plans

The Ruby/Sinatra version that previously ran on Synology is preserved on the `legacy-ruby` branch.
