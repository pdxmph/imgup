# imgup → Cloudflare migration

## Goal

Move imgup off the Synology (Portainer) and onto Cloudflare so it can be iterated on as a personal tool — eventually as a PWA wired into the rest of the asystem ecosystem. Behavioral parity with today: web upload form, copy-pasteable markdown/HTML/org snippet, `/recent` contact sheet. CLI, POTW endpoint, and OAuth-dance views are dropped.

## Non-goals

- The CLI binary (`bin/imgup`).
- The POTW endpoint and view (already pulled from nav).
- The interactive OAuth1 token-minting flow (`/`, `/request`, `/auth`, `/tokens` views). Tokens are already minted and live in env.
- Multiple-album selection / album browsing UI.
- Rich features beyond what currently exists. The point is to land on Cloudflare, not to grow the tool.

## Architecture

Single Cloudflare Worker. Serves a static SPA from `public/` via Workers Static Assets, plus two JSON endpoints under `/api/*`. No KV, D1, R2, or Durable Objects. Files stream straight through the Worker into SmugMug's upload endpoint — no persistence anywhere.

Cloudflare Access fronts the production hostname (`imgup.puddingtime.net`); the Worker itself does no auth checks. Local dev runs unprotected on `localhost`.

```
imgup/
├── public/
│   ├── index.html
│   ├── app.js
│   └── style.css
├── worker/
│   ├── index.ts
│   ├── oauth1.ts
│   ├── smugmug.ts
│   └── snippets.ts
├── test/
│   ├── oauth1.test.ts
│   └── snippets.test.ts
├── wrangler.jsonc
├── package.json
├── tsconfig.json
├── .dev.vars              # gitignored
├── .gitignore
└── README.md
```

The current Ruby tree (`imgup.rb`, `lib/`, `views/`, `bin/`, `Dockerfile`, `docker-compose.yml`, `Gemfile*`, `Rakefile`, `config.ru`, `.bundle/`, `tmp/`, `dot_env`, `imgup-potw.rb`, `README-cli.md`) is removed from `main` in the same commit that introduces the Worker. A `legacy-ruby` branch is cut from current `main` first so the working Ruby snapshot remains one `git checkout` away.

## Components

### `worker/index.ts`

Request router. Three concerns:

1. `POST /api/upload` → `handleUpload(request, env)`.
2. `GET /api/recent` → `handleRecent(request, env)`.
3. Everything else → fall through to Workers Static Assets binding for `public/`.

Returns `Response`s. JSON errors have shape `{error: string}` and forward upstream HTTP status when relevant (401/403/404/413/429/5xx from SmugMug pass through).

### `worker/oauth1.ts`

Self-contained OAuth1 signing module, no dependencies beyond Web Crypto.

Exports:

- `signRequest({method, url, consumerKey, consumerSecret, token, tokenSecret, queryParams?, formParams?, nonce?, timestamp?}) → Promise<string>` — returns the `Authorization` header value.

Implementation details:

- HMAC-SHA1 via `crypto.subtle.importKey` + `crypto.subtle.sign`.
- Per RFC 5849 §3.4.1.3: body parameters are folded into the signature base string only when the body is `application/x-www-form-urlencoded`. For multipart uploads the body is opaque; only URL + query params + OAuth params are signed. This matches the Ruby `oauth` gem's behavior and is what SmugMug expects.
- `nonce` and `timestamp` accept overrides (for tests); default to random/`Date.now()`.

### `worker/smugmug.ts`

Higher-level SmugMug operations. Two functions:

- `uploadFile(env, {file: Blob, title: string, caption: string}) → Promise<{url, imageUri}>`:
  1. Build `FormData` with single `file` field (the Blob, with filename).
  2. Sign `POST https://upload.smugmug.com/` with `oauth1.signRequest` (no form params in signature; multipart).
  3. `fetch()` with these headers in addition to the `Authorization`:
     - `X-Smug-AlbumUri: /api/v2/album/${env.SMUGMUG_UPLOAD_ALBUM_ID}`
     - `X-Smug-ResponseType: JSON`
     - `X-Smug-Version: v2`
     - `X-Smug-Filename: <file.name>`
     - `X-Smug-Title: <title>`
     - `X-Smug-Caption: <caption>`
  4. Parse response → `Image.ImageUri`.
  5. Sign and `fetch()` `GET ${API_BASE}${ImageUri}!sizes`.
  6. Pick the largest size by `Width` from the returned `ImageSizes.Size` array. Fall back to legacy hash format (`XLargeImageUrl` etc.) if `Size` is absent — preserves the Ruby `fetch_full_url` fallback chain.
  7. Return `{url, imageUri}`.

- `listRecent(env, {count: number}) → Promise<RecentImage[]>`:
  1. **Cheap path:** sign and fetch `GET ${API_BASE}/api/v2/album/${ALBUM_ID}!images?count=${count}&_expand=ImageSizeDetails`. If each `AlbumImage` carries an inline `ImageSizeDetails.ImageSizeXLarge.Url`, build the result array from the single response.
  2. **Fallback:** if the expansion doesn't carry size URLs, fan out — one `!sizedetails` call per image. Same shape as the current Ruby `/recent`.
  3. Each result item: `{thumb, image_url, title, caption, web_uri}`.

`API_BASE` is `https://api.smugmug.com`. Hardcoded in `smugmug.ts` — not an env var (the Ruby code only made it overridable for testing, which we're not doing here).

### `worker/snippets.ts`

Pure function. Given `(url, title)`, returns:

```ts
{
  url,
  markdown: `![${title}](${url})`,
  html:     `<img src='${url}' alt='${title}' />`,
  org:      `[[img:${url}][${title}]]`,
}
```

Identical strings to today's Ruby `Uploader#build_result`. The org link format is the bespoke `img:` link type Mike's blog tooling expects — do not "improve" it.

## Data flow

### Upload (`POST /api/upload`)

1. Browser submits `multipart/form-data` with `file`, `title`, `caption`.
2. Worker parses with `request.formData()`. Pulls the `File` Blob.
3. Calls `smugmug.uploadFile(env, {file, title, caption})`.
4. Calls `snippets.build(url, title)`.
5. Calls `caches.default.delete()` for the recent-cache keys (one per `count` we've seen — see below).
6. Returns `200 {url, markdown, html, org}`.

Errors from SmugMug forward their status with `{error: <message>}`. Worker exceptions return `500 {error: <message>}`.

### Recent (`GET /api/recent?count=10`)

1. Build cache key from request URL.
2. `caches.default.match(cacheKey)` — if hit, return immediately.
3. On miss: call `smugmug.listRecent(env, {count})`.
4. Build a `Response` with `Cache-Control: max-age=300, public` and `caches.default.put(cacheKey, response.clone())`.
5. Return the response.

### Cache invalidation

`/api/upload` busts the cache on success by deleting a fixed, known-up-front set of recent-cache keys: one per `count` value the frontend uses (default `10`, plus whatever else `app.js` ever requests — likely just `10`). `caches.default.delete()` for each. No reliance on Worker isolate state surviving across requests. If a request comes in for an uncached count, it pays a single SmugMug round-trip and populates cache; the next upload busts that key too.

## Snippet contract

The strings returned by `/api/upload` are the user-facing product. They must match the current Ruby outputs exactly:

| Format   | Template                          |
|----------|-----------------------------------|
| markdown | `![<title>](<url>)`               |
| html     | `<img src='<url>' alt='<title>' />` |
| org      | `[[img:<url>][<title>]]`          |

`<url>` is the largest available size from SmugMug's `!sizes` endpoint. `<title>` is what the user typed (or the filename minus extension if they didn't type one — same default the Ruby `Uploader#initialize` applies).

## Frontend

Three files in `public/`:

- **`index.html`** — single page. Upload form (file, title, caption). Result region (initially hidden) that shows the four snippet strings as `<pre>` blocks with click-to-copy. Below that, a contact-sheet grid for `/api/recent`.
- **`app.js`** — vanilla JS. On form submit, posts `multipart/form-data` to `/api/upload` via `fetch()`, renders the result region. On page load (and after upload), fetches `/api/recent` and renders the grid. Click-to-copy wires `navigator.clipboard.writeText`.
- **`style.css`** — carries over the visual design from the current `views/local_css.haml` and `views/layout.haml` reskin: warm-paper / safelight palette, monospace + serif pairing, contact-sheet sequence numbers, crop-mark corners. Theme toggle respects `prefers-color-scheme` on first load.

Frontend talks to the Worker only via `/api/*`. No HTML rendering on the server. This is the JSON boundary that makes a future PWA possible — service workers, offline-tolerant uploads, install prompts all fit cleanly on top.

## Auth

Cloudflare Access application on `imgup.puddingtime.net`:

- Single rule: `email == mike@puddingtime.org`.
- Default session lifetime.
- No bypass policies.

Browser flow: hit hostname → Access challenge → Google login → Access cookie set → `/api/*` calls ride the cookie. Worker code does no auth verification. JWT verification (`Cf-Access-Jwt-Assertion`) is intentionally out of scope; it's defense-in-depth for a multi-user world we're not in.

`localhost` (`wrangler dev`) has no Access in front and no Worker-side check — same trust model as running `ruby imgup.rb` today.

## Secrets

Five values, all secrets. None in `wrangler.jsonc`.

| Name                          | Source today                           |
|-------------------------------|----------------------------------------|
| `SMUGMUG_TOKEN`               | Portainer env / `.env`                 |
| `SMUGMUG_SECRET`              | Portainer env / `.env`                 |
| `SMUGMUG_ACCESS_TOKEN`        | Portainer env / `.env`                 |
| `SMUGMUG_ACCESS_TOKEN_SECRET` | Portainer env / `.env`                 |
| `SMUGMUG_UPLOAD_ALBUM_ID`     | Portainer env / `.env`                 |

Production: `wrangler secret put <NAME>` for each.
Local: `.dev.vars` file at repo root, gitignored, same `KEY=value` format as `.env` today.

`SMUGMUG_UPLOAD_ALBUM_ID` is treated as a secret rather than a `vars` entry. Not a credential, but Mike doesn't want it leaked in the repo.

## Hostname & cutover

`imgup.puddingtime.net` already resolves to a Cloudflare Tunnel pointing at the Synology container. Cutover steps:

1. Cut `legacy-ruby` branch from current `main`.
2. Land the Worker code on `main` (Ruby files removed in the same commit).
3. `wrangler deploy` — Worker lives at `imgup.<account>.workers.dev` initially.
4. Smoke test the `.workers.dev` URL by hand (no Access yet at this stage, since it's not the production hostname).
5. Configure the Cloudflare Access application targeting `imgup.puddingtime.net`.
6. Add the custom domain route to the Worker (Cloudflare dashboard or `wrangler.jsonc` `routes`). This replaces the existing tunnel mapping for that hostname; the tunnel itself stays running for whatever else lives behind it.
7. Smoke test through the production hostname (Access challenge → upload → snippet → `/recent` shows it).
8. Stop the Synology container in Portainer and remove the stack.

## Local dev

- `wrangler dev` runs the Worker on `localhost:8787` with `.dev.vars` populating `env`.
- Static assets in `public/` served by the dev server.
- Real SmugMug API on the other end — same as running `ruby imgup.rb` today.
- No Access challenge, no JWT — straight in.

## Errors

| Source                                | Worker response                          |
|---------------------------------------|------------------------------------------|
| Missing/invalid form fields           | `400 {error: "..."}`                     |
| SmugMug 401/403                       | `401 {error: "..."}`                     |
| SmugMug 404                           | `404 {error: "..."}`                     |
| SmugMug 413 (file too big)            | `413 {error: "..."}`                     |
| SmugMug 429 (rate limited)            | `429 {error: "..."}`                     |
| SmugMug 5xx                           | `502 {error: "..."}`                     |
| Worker exception                      | `500 {error: "..."}`                     |

Frontend renders the `error` string in an inline message region. Same status mapping as the current Ruby `error do` block.

## Testing

- **`test/oauth1.test.ts`** (Vitest). Fixed nonce + timestamp, sign a known request, assert the `Authorization` header byte-for-byte. Test vector generated once from the running Ruby `oauth` gem and pinned. This is the only piece with cryptographic correctness risk.
- **`test/snippets.test.ts`** (Vitest). Three assertions: markdown, html, org strings match the Ruby outputs for a known `(url, title)` pair.
- **No integration tests against SmugMug.** Mocking the API surface isn't worth it; the manual cutover smoke test (step 7 above) is the integration test.
- **`tsc --noEmit`** runs locally before every commit. CI is deferred (see follow-ups).

## Open questions

None. All in-scope decisions resolved during brainstorming.

## Out-of-scope follow-ups

Not part of this migration; noted for the future:

- PWA shell (manifest, service worker, installable, offline-tolerant upload queue).
- Multiple-album selection UI.
- Hooking imgup into acloud (e.g. an MCP tool that uploads images and returns the snippet, callable from other agents).
- In-Worker JWT verification of `Cf-Access-Jwt-Assertion` if a second user ever shows up.
- CI for typecheck + tests.
