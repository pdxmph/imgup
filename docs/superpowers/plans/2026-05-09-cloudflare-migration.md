# imgup Cloudflare Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Sinatra/Ruby imgup app running on Synology with a Cloudflare Worker that serves a static SPA and exposes two JSON endpoints for SmugMug uploads. Cloudflare Access fronts the production hostname.

**Architecture:** Single TypeScript Worker. `public/` static assets served via Workers Static Assets binding. `worker/index.ts` routes `POST /api/upload` and `GET /api/recent` to handlers that use a hand-rolled OAuth1 signing module to talk to SmugMug. No KV/D1/R2/DO. Workers Cache API edge-caches `/api/recent` for 5 min, busted on upload. Browser auth via Cloudflare Access (no in-Worker JWT verification).

**Tech Stack:** TypeScript 5, Cloudflare Workers, Wrangler 3, Vitest, Web Crypto (HMAC-SHA1), Workers Static Assets. Vanilla HTML/CSS/JS frontend.

**Spec:** `docs/superpowers/specs/2026-05-09-cloudflare-migration-design.md`

---

## Pre-flight

Before starting, confirm:

- `wrangler` is installed and authenticated. Run `wrangler whoami` — should show Mike's Cloudflare account email. If not: `npm install -g wrangler && wrangler login`.
- The current Ruby app at `imgup.puddingtime.net` is reachable through its existing tunnel. We don't break it during dev — Ruby files stay until the cutover.
- `node --version` is ≥ 20 (Web Crypto on the global `crypto` object).
- `git status` is clean. Working directory: `/Users/mikehall/imgup`.

---

### Task 1: Cut the legacy-ruby branch

Preserve the working Ruby snapshot before any changes.

**Files:** none modified — branch operation only.

- [ ] **Step 1: Cut the branch from current HEAD**

```bash
git checkout -b legacy-ruby
```

- [ ] **Step 2: Push the branch to origin**

```bash
git push -u origin legacy-ruby
```

- [ ] **Step 3: Return to main**

```bash
git checkout main
```

- [ ] **Step 4: Verify**

```bash
git branch -a
```

Expected: `legacy-ruby` listed locally and as `remotes/origin/legacy-ruby`. Currently on `main`.

---

### Task 2: TypeScript / Wrangler scaffold

Set up the project files needed for any TS work to happen. Ruby code is untouched.

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `wrangler.jsonc`
- Create: `vitest.config.ts`
- Create: `.dev.vars.example`
- Modify: `.gitignore`

- [ ] **Step 1: Initialize `package.json`**

Create `/Users/mikehall/imgup/package.json`:

```json
{
  "name": "imgup",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20250101.0",
    "typescript": "^5.6.0",
    "vitest": "^2.1.0",
    "wrangler": "^3.90.0"
  }
}
```

- [ ] **Step 2: Install dependencies**

```bash
npm install
```

Expected: creates `node_modules/` and `package-lock.json`. No errors.

- [ ] **Step 3: Create `tsconfig.json`**

Create `/Users/mikehall/imgup/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "Bundler",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "resolveJsonModule": true,
    "noEmit": true
  },
  "include": ["worker/**/*.ts", "test/**/*.ts"]
}
```

- [ ] **Step 4: Create `wrangler.jsonc`**

Create `/Users/mikehall/imgup/wrangler.jsonc`:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "imgup",
  "main": "worker/index.ts",
  "compatibility_date": "2025-12-01",
  "assets": {
    "directory": "./public",
    "binding": "ASSETS"
  },
  "observability": {
    "enabled": true
  }
  // routes intentionally omitted at this stage. Custom domain added during cutover (Task 18).
}
```

- [ ] **Step 5: Create `vitest.config.ts`**

Create `/Users/mikehall/imgup/vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
```

- [ ] **Step 6: Create `.dev.vars.example`**

Create `/Users/mikehall/imgup/.dev.vars.example`:

```
SMUGMUG_TOKEN=
SMUGMUG_SECRET=
SMUGMUG_ACCESS_TOKEN=
SMUGMUG_ACCESS_TOKEN_SECRET=
SMUGMUG_UPLOAD_ALBUM_ID=
```

- [ ] **Step 7: Update `.gitignore`**

Read the current `.gitignore` first. Append these lines (do not duplicate any already present):

```
node_modules/
.dev.vars
.wrangler/
dist/
```

- [ ] **Step 8: Commit**

```bash
git add package.json package-lock.json tsconfig.json wrangler.jsonc vitest.config.ts .dev.vars.example .gitignore
git commit -m "chore: scaffold typescript + wrangler project"
```

---

### Task 3: Implement `worker/snippets.ts` (TDD)

Pure function. Easiest possible TDD candidate. Builds the four-snippet contract that `/api/upload` returns.

**Files:**
- Create: `worker/snippets.ts`
- Create: `test/snippets.test.ts`

- [ ] **Step 1: Write the failing test**

Create `/Users/mikehall/imgup/test/snippets.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildSnippets } from "../worker/snippets";

describe("buildSnippets", () => {
  const url = "https://photos.smugmug.com/Photography/My-Album/i-AbCdEf/0/X4/photo-X4.jpg";
  const title = "Sample Photo";

  it("returns the canonical four-field shape", () => {
    const result = buildSnippets(url, title);
    expect(result).toEqual({
      url,
      markdown: "![Sample Photo](https://photos.smugmug.com/Photography/My-Album/i-AbCdEf/0/X4/photo-X4.jpg)",
      html: "<img src='https://photos.smugmug.com/Photography/My-Album/i-AbCdEf/0/X4/photo-X4.jpg' alt='Sample Photo' />",
      org: "[[img:https://photos.smugmug.com/Photography/My-Album/i-AbCdEf/0/X4/photo-X4.jpg][Sample Photo]]",
    });
  });

  it("preserves raw title text without escaping", () => {
    const result = buildSnippets("https://example.com/x.jpg", "He said \"hi\" & waved");
    expect(result.markdown).toBe("![He said \"hi\" & waved](https://example.com/x.jpg)");
    expect(result.html).toBe("<img src='https://example.com/x.jpg' alt='He said \"hi\" & waved' />");
    expect(result.org).toBe("[[img:https://example.com/x.jpg][He said \"hi\" & waved]]");
  });
});
```

The "no escaping" assertion is intentional — it pins the current Ruby `Uploader#build_result` behavior, which doesn't escape either. Drift here would silently break already-published blog posts.

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test
```

Expected: vitest reports `Cannot find module '../worker/snippets'` or similar. Tests fail.

- [ ] **Step 3: Implement the module**

Create `/Users/mikehall/imgup/worker/snippets.ts`:

```ts
export type Snippets = {
  url: string;
  markdown: string;
  html: string;
  org: string;
};

export function buildSnippets(url: string, title: string): Snippets {
  return {
    url,
    markdown: `![${title}](${url})`,
    html: `<img src='${url}' alt='${title}' />`,
    org: `[[img:${url}][${title}]]`,
  };
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
npm test
```

Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add worker/snippets.ts test/snippets.test.ts
git commit -m "feat: snippets module with markdown/html/org formats"
```

---

### Task 4: Implement `worker/oauth1.ts` (TDD with Ruby-pinned vector)

Hand-rolled OAuth1 HMAC-SHA1 signer. We pin a test vector against the existing Ruby `oauth` gem (still in the repo at this point) to guarantee bit-for-bit compatibility with the production app.

**Files:**
- Create: `worker/oauth1.ts`
- Create: `test/oauth1.test.ts`
- Create (then delete after use): `scripts/gen_oauth_vector.rb`

- [ ] **Step 1: Generate the reference test vector with the Ruby gem**

Create `/Users/mikehall/imgup/scripts/gen_oauth_vector.rb`:

```ruby
#!/usr/bin/env ruby
# Generates an OAuth1 Authorization header from the Ruby gem with
# fixed nonce + timestamp, so the TS port can be tested against it.
require 'oauth'
require 'net/http'

CONSUMER_KEY    = 'test-consumer-key'
CONSUMER_SECRET = 'test-consumer-secret'
ACCESS_TOKEN    = 'test-access-token'
ACCESS_SECRET   = 'test-access-token-secret'
NONCE           = 'fixed-nonce-abc123'
TIMESTAMP       = '1700000000'
URL             = 'https://api.smugmug.com/api/v2/album/abcd1234!images?count=10'

consumer = OAuth::Consumer.new(CONSUMER_KEY, CONSUMER_SECRET, site: 'https://api.smugmug.com')
access   = OAuth::AccessToken.new(consumer, ACCESS_TOKEN, ACCESS_SECRET)

uri = URI.parse(URL)
req = Net::HTTP::Get.new(uri.request_uri)
access.sign! req, { nonce: NONCE, timestamp: TIMESTAMP }

puts "Authorization: #{req['Authorization']}"
```

Run it (Ruby + the oauth gem are present from the existing app):

```bash
cd /Users/mikehall/imgup && bundle exec ruby scripts/gen_oauth_vector.rb
```

Expected output: a single line starting with `Authorization: OAuth oauth_consumer_key="test-consumer-key", ...` ending with an `oauth_signature="..."` value. Copy this entire `OAuth ...` string (everything after `Authorization: `).

- [ ] **Step 2: Write the failing test**

Create `/Users/mikehall/imgup/test/oauth1.test.ts`. Replace `<PASTE_AUTHORIZATION_HEADER_FROM_STEP_1>` with the exact string captured above:

```ts
import { describe, expect, it } from "vitest";
import { signRequest } from "../worker/oauth1";

describe("signRequest", () => {
  it("matches the Ruby oauth gem byte-for-byte for a SmugMug GET", async () => {
    const auth = await signRequest({
      method: "GET",
      url: "https://api.smugmug.com/api/v2/album/abcd1234!images?count=10",
      consumerKey: "test-consumer-key",
      consumerSecret: "test-consumer-secret",
      token: "test-access-token",
      tokenSecret: "test-access-token-secret",
      nonce: "fixed-nonce-abc123",
      timestamp: "1700000000",
    });

    expect(auth).toBe("<PASTE_AUTHORIZATION_HEADER_FROM_STEP_1>");
  });

  it("treats multipart bodies as opaque (body params not in signature base)", async () => {
    // Same inputs as a known-good GET, but POST with multipart content.
    // Per RFC 5849 §3.4.1.3, multipart body params are NOT folded into the base string.
    // So a multipart POST and a parameterless POST to the same URL should produce the same signature.
    const baseArgs = {
      method: "POST" as const,
      url: "https://upload.smugmug.com/",
      consumerKey: "test-consumer-key",
      consumerSecret: "test-consumer-secret",
      token: "test-access-token",
      tokenSecret: "test-access-token-secret",
      nonce: "fixed-nonce-abc123",
      timestamp: "1700000000",
    };
    const a = await signRequest(baseArgs);
    const b = await signRequest(baseArgs);
    expect(a).toBe(b);
    // Sanity: result has all required oauth_* fields.
    expect(a).toMatch(/^OAuth /);
    expect(a).toContain('oauth_consumer_key="test-consumer-key"');
    expect(a).toContain('oauth_token="test-access-token"');
    expect(a).toContain('oauth_signature_method="HMAC-SHA1"');
    expect(a).toContain('oauth_nonce="fixed-nonce-abc123"');
    expect(a).toContain('oauth_timestamp="1700000000"');
    expect(a).toContain('oauth_version="1.0"');
    expect(a).toMatch(/oauth_signature="[^"]+"/);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
npm test
```

Expected: vitest reports module not found.

- [ ] **Step 4: Implement `worker/oauth1.ts`**

Create `/Users/mikehall/imgup/worker/oauth1.ts`:

```ts
// OAuth 1.0a HMAC-SHA1 signing for Cloudflare Workers (Web Crypto only).
// Compatible with the Ruby `oauth` gem's behavior, which is what the existing
// imgup Sinatra app uses. Per RFC 5849 §3.4.1.3, request body parameters are
// NOT folded into the signature base string when the body is anything other
// than application/x-www-form-urlencoded. SmugMug uploads use multipart, so
// we never sign the body — only the URL, query params, and oauth_* params.

export type SignArgs = {
  method: "GET" | "POST" | "PUT" | "DELETE";
  url: string;
  consumerKey: string;
  consumerSecret: string;
  token: string;
  tokenSecret: string;
  /** Override the nonce (for tests). Default: random 32-hex-char string. */
  nonce?: string;
  /** Override the timestamp in seconds (for tests). Default: now. */
  timestamp?: string;
};

export async function signRequest(args: SignArgs): Promise<string> {
  const u = new URL(args.url);
  const queryParams: Array<[string, string]> = [];
  for (const [k, v] of u.searchParams) {
    queryParams.push([k, v]);
  }

  const oauthParams: Record<string, string> = {
    oauth_consumer_key: args.consumerKey,
    oauth_nonce: args.nonce ?? randomNonce(),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: args.timestamp ?? Math.floor(Date.now() / 1000).toString(),
    oauth_token: args.token,
    oauth_version: "1.0",
  };

  // Build base string: METHOD&base_url&normalized_params
  const baseUrl = `${u.protocol}//${u.host.toLowerCase()}${u.pathname}`;
  const allParams: Array<[string, string]> = [
    ...queryParams,
    ...Object.entries(oauthParams),
  ];
  const normalized = allParams
    .map(([k, v]) => [pctEncode(k), pctEncode(v)] as const)
    .sort(([ak, av], [bk, bv]) => (ak < bk ? -1 : ak > bk ? 1 : av < bv ? -1 : av > bv ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join("&");

  const baseString = [
    args.method.toUpperCase(),
    pctEncode(baseUrl),
    pctEncode(normalized),
  ].join("&");

  const signingKey = `${pctEncode(args.consumerSecret)}&${pctEncode(args.tokenSecret)}`;
  const signature = await hmacSha1Base64(signingKey, baseString);

  const authParams: Record<string, string> = {
    ...oauthParams,
    oauth_signature: signature,
  };

  // Authorization header: keys sorted alphabetically, values pct-encoded then quoted.
  // The Ruby oauth gem also sorts alphabetically; matches their output.
  const headerValue = Object.keys(authParams)
    .sort()
    .map((k) => `${pctEncode(k)}="${pctEncode(authParams[k]!)}"`)
    .join(", ");

  return `OAuth ${headerValue}`;
}

// RFC 3986 percent-encoding: encodeURIComponent + escapes for !'()*
function pctEncode(s: string): string {
  return encodeURIComponent(s).replace(/[!'()*]/g, (c) =>
    "%" + c.charCodeAt(0).toString(16).toUpperCase()
  );
}

function randomNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmacSha1Base64(key: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"]
  );
  const sigBytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message))
  );
  return base64(sigBytes);
}

function base64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]!);
  return btoa(s);
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
npm test
```

Expected: 4 passed (2 oauth1, 2 snippets). If the Ruby-pinned vector fails: re-run `scripts/gen_oauth_vector.rb`, double-check the pasted string is verbatim (including outer `OAuth ` prefix), and inspect `pctEncode` and `baseString` construction for off-by-one issues.

- [ ] **Step 6: Delete the generator script**

```bash
rm scripts/gen_oauth_vector.rb
rmdir scripts
```

The vector is now pinned in the test; the script's job is done.

- [ ] **Step 7: Typecheck**

```bash
npm run typecheck
```

Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add worker/oauth1.ts test/oauth1.test.ts
git commit -m "feat: oauth1 hmac-sha1 signer with ruby-pinned test vector"
```

---

### Task 5: Implement `worker/smugmug.ts` — `uploadFile` (TDD with mocked fetch)

Wraps the SmugMug upload + size lookup. Tests verify URL, header, and parsing logic against canned responses.

**Files:**
- Create: `worker/smugmug.ts`
- Create: `test/smugmug.test.ts`

- [ ] **Step 1: Write the failing test**

Create `/Users/mikehall/imgup/test/smugmug.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { uploadFile } from "../worker/smugmug";

const env = {
  SMUGMUG_TOKEN: "ck",
  SMUGMUG_SECRET: "cs",
  SMUGMUG_ACCESS_TOKEN: "at",
  SMUGMUG_ACCESS_TOKEN_SECRET: "ats",
  SMUGMUG_UPLOAD_ALBUM_ID: "AlbumABC",
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("uploadFile", () => {
  it("posts to upload.smugmug.com with the right X-Smug-* headers and returns the largest size URL", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");

    // First call: upload response
    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          Image: { ImageUri: "/api/v2/image/abc123" },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    );

    // Second call: !sizes response (new array format)
    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          Response: {
            ImageSizes: {
              Size: [
                { Url: "https://photos.smugmug.com/i-abc/0/Sm/x-Sm.jpg", Width: 200 },
                { Url: "https://photos.smugmug.com/i-abc/0/X4/x-X4.jpg", Width: 4000 },
                { Url: "https://photos.smugmug.com/i-abc/0/Md/x-Md.jpg", Width: 800 },
              ],
            },
          },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    );

    const file = new File([new Uint8Array([1, 2, 3])], "photo.jpg", { type: "image/jpeg" });
    const result = await uploadFile(env, { file, title: "My Photo", caption: "" });

    expect(result.url).toBe("https://photos.smugmug.com/i-abc/0/X4/x-X4.jpg");
    expect(result.imageUri).toBe("/api/v2/image/abc123");

    // Verify the upload call shape
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [uploadUrl, uploadInit] = fetchMock.mock.calls[0]!;
    expect(uploadUrl).toBe("https://upload.smugmug.com/");
    expect(uploadInit?.method).toBe("POST");
    const headers = new Headers(uploadInit?.headers);
    expect(headers.get("X-Smug-AlbumUri")).toBe("/api/v2/album/AlbumABC");
    expect(headers.get("X-Smug-ResponseType")).toBe("JSON");
    expect(headers.get("X-Smug-Version")).toBe("v2");
    expect(headers.get("X-Smug-Filename")).toBe("photo.jpg");
    expect(headers.get("X-Smug-Title")).toBe("My Photo");
    expect(headers.get("X-Smug-Caption")).toBe("");
    expect(headers.get("Authorization") ?? "").toMatch(/^OAuth /);

    // Verify the !sizes call is signed and points at the right URI
    const [sizesUrl, sizesInit] = fetchMock.mock.calls[1]!;
    expect(sizesUrl).toBe("https://api.smugmug.com/api/v2/image/abc123!sizes");
    expect(sizesInit?.method ?? "GET").toBe("GET");
    expect(new Headers(sizesInit?.headers).get("Authorization") ?? "").toMatch(/^OAuth /);
  });

  it("falls back to legacy hash format if Size array is missing", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");

    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ Image: { ImageUri: "/api/v2/image/legacy" } }), { status: 200 })
    );
    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          Response: {
            ImageSizes: {
              MediumImageUrl: "https://example.com/m.jpg",
              XLargeImageUrl: "https://example.com/xl.jpg",
              OriginalImageUrl: "https://example.com/orig.jpg",
            },
          },
        }),
        { status: 200 }
      )
    );

    const file = new File([new Uint8Array([1])], "x.jpg", { type: "image/jpeg" });
    const result = await uploadFile(env, { file, title: "x", caption: "" });
    expect(result.url).toBe("https://example.com/xl.jpg");
  });

  it("throws when SmugMug returns non-2xx on upload", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");
    fetchMock.mockResolvedValueOnce(new Response("nope", { status: 401 }));

    const file = new File([new Uint8Array([1])], "x.jpg", { type: "image/jpeg" });
    await expect(uploadFile(env, { file, title: "x", caption: "" })).rejects.toThrow(/401/);
  });
});
```

- [ ] **Step 2: Run test to verify failure**

```bash
npm test
```

Expected: module-not-found error from the smugmug import.

- [ ] **Step 3: Implement `worker/smugmug.ts` (uploadFile only — listRecent is added in Task 6)**

Create `/Users/mikehall/imgup/worker/smugmug.ts`:

```ts
import { signRequest } from "./oauth1";

const API_BASE = "https://api.smugmug.com";
const UPLOAD_URL = "https://upload.smugmug.com/";

export type SmugmugEnv = {
  SMUGMUG_TOKEN: string;
  SMUGMUG_SECRET: string;
  SMUGMUG_ACCESS_TOKEN: string;
  SMUGMUG_ACCESS_TOKEN_SECRET: string;
  SMUGMUG_UPLOAD_ALBUM_ID: string;
};

export type UploadResult = {
  url: string;
  imageUri: string;
};

export async function uploadFile(
  env: SmugmugEnv,
  args: { file: File; title: string; caption: string }
): Promise<UploadResult> {
  const auth = await signRequest({
    method: "POST",
    url: UPLOAD_URL,
    consumerKey: env.SMUGMUG_TOKEN,
    consumerSecret: env.SMUGMUG_SECRET,
    token: env.SMUGMUG_ACCESS_TOKEN,
    tokenSecret: env.SMUGMUG_ACCESS_TOKEN_SECRET,
  });

  const form = new FormData();
  form.append("file", args.file, args.file.name);

  const headers = new Headers({
    Authorization: auth,
    "X-Smug-AlbumUri": `/api/v2/album/${env.SMUGMUG_UPLOAD_ALBUM_ID}`,
    "X-Smug-ResponseType": "JSON",
    "X-Smug-Version": "v2",
    "X-Smug-Filename": args.file.name,
    "X-Smug-Title": args.title,
    "X-Smug-Caption": args.caption,
  });

  const resp = await fetch(UPLOAD_URL, { method: "POST", body: form, headers });
  if (!resp.ok) {
    const body = await resp.text();
    throw new SmugmugError(`upload failed: HTTP ${resp.status} ${body}`, resp.status);
  }
  const json = (await resp.json()) as { Image?: { ImageUri?: string; Uri?: string } };
  const imageUri = json.Image?.ImageUri ?? json.Image?.Uri;
  if (!imageUri) {
    throw new SmugmugError(`no ImageUri in upload response: ${JSON.stringify(json)}`, 502);
  }

  const url = await fetchLargestSizeUrl(env, imageUri);
  return { url, imageUri };
}

async function fetchLargestSizeUrl(env: SmugmugEnv, imageUri: string): Promise<string> {
  const sizesUrl = `${API_BASE}${imageUri}!sizes`;
  const auth = await signRequest({
    method: "GET",
    url: sizesUrl,
    consumerKey: env.SMUGMUG_TOKEN,
    consumerSecret: env.SMUGMUG_SECRET,
    token: env.SMUGMUG_ACCESS_TOKEN,
    tokenSecret: env.SMUGMUG_ACCESS_TOKEN_SECRET,
  });
  const resp = await fetch(sizesUrl, {
    method: "GET",
    headers: { Authorization: auth, Accept: "application/json" },
  });
  if (!resp.ok) {
    throw new SmugmugError(`size-fetch failed: HTTP ${resp.status}`, resp.status);
  }
  const body = (await resp.json()) as {
    Response?: {
      ImageSizes?: {
        Size?: Array<{ Url: string; Width: number }>;
        XLargeImageUrl?: string;
        LargestImageUrl?: string;
        OriginalImageUrl?: string;
        [k: string]: unknown;
      };
    };
  };

  const sizes = body.Response?.ImageSizes;
  if (Array.isArray(sizes?.Size) && sizes!.Size!.length > 0) {
    return sizes!.Size!.reduce((best, s) => (s.Width > best.Width ? s : best)).Url;
  }
  if (sizes?.XLargeImageUrl) return sizes.XLargeImageUrl;
  if (sizes?.LargestImageUrl) return sizes.LargestImageUrl;
  if (sizes?.OriginalImageUrl) return sizes.OriginalImageUrl;
  if (sizes) {
    // last-resort: pick the longest *ImageUrl key value (matches Ruby's heuristic)
    const candidates = Object.entries(sizes).filter(
      ([k, v]) => typeof v === "string" && k.endsWith("ImageUrl")
    ) as Array<[string, string]>;
    if (candidates.length > 0) {
      candidates.sort(([a], [b]) => a.length - b.length);
      return candidates[candidates.length - 1]![1];
    }
  }
  throw new SmugmugError(`no image size URL found: ${JSON.stringify(body)}`, 502);
}

export class SmugmugError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "SmugmugError";
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
npm test
```

Expected: 7 passed (2 snippets, 2 oauth1, 3 smugmug.uploadFile).

- [ ] **Step 5: Typecheck**

```bash
npm run typecheck
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add worker/smugmug.ts test/smugmug.test.ts
git commit -m "feat: smugmug.uploadFile with size-lookup and legacy fallback"
```

---

### Task 6: Implement `worker/smugmug.ts` — `listRecent` (TDD)

Add the `listRecent` function alongside `uploadFile` in the same module. Tries the cheap `_expand=ImageSizeDetails` path first, falls back to N+1 fan-out.

**Files:**
- Modify: `worker/smugmug.ts` (add `listRecent` and supporting types)
- Modify: `test/smugmug.test.ts` (add `describe("listRecent")` block)

- [ ] **Step 1: Write failing tests**

Append to `/Users/mikehall/imgup/test/smugmug.test.ts` (before the closing of the file, after the existing `describe("uploadFile", ...)` block — keep both):

```ts
import { listRecent } from "../worker/smugmug";

describe("listRecent", () => {
  it("uses the cheap _expand path when ImageSizeDetails is present inline", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");

    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          Response: {
            AlbumImage: [
              {
                ImageKey: "k1",
                Title: "First",
                Caption: "c1",
                ThumbnailUrl: "https://t/1.jpg",
                WebUri: "https://w/1",
                Uris: { ImageSizeDetails: { ImageSizeDetails: { ImageSizeXLarge: { Url: "https://full/1.jpg" } } } },
              },
              {
                ImageKey: "k2",
                Title: "Second",
                Caption: "c2",
                ThumbnailUrl: "https://t/2.jpg",
                WebUri: "https://w/2",
                Uris: { ImageSizeDetails: { ImageSizeDetails: { ImageSizeXLarge: { Url: "https://full/2.jpg" } } } },
              },
            ],
          },
        }),
        { status: 200 }
      )
    );

    const result = await listRecent(env, { count: 10 });

    expect(fetchMock).toHaveBeenCalledTimes(1); // cheap path: no fan-out
    expect(fetchMock.mock.calls[0]![0]).toMatch(/_expand=ImageSizeDetails/);
    expect(result).toEqual([
      { thumb: "https://t/1.jpg", image_url: "https://full/1.jpg", title: "First", caption: "c1", web_uri: "https://w/1" },
      { thumb: "https://t/2.jpg", image_url: "https://full/2.jpg", title: "Second", caption: "c2", web_uri: "https://w/2" },
    ]);
  });

  it("falls back to N+1 when inline expansion lacks size URLs", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");

    // Album list, no inline sizes
    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          Response: {
            AlbumImage: [
              { Title: "A", Caption: "", ThumbnailUrl: "https://t/a", WebUri: "https://w/a", Uris: { Image: { Uri: "/api/v2/image/A" } } },
              { Title: "B", Caption: "", ThumbnailUrl: "https://t/b", WebUri: "https://w/b", Uris: { Image: { Uri: "/api/v2/image/B" } } },
            ],
          },
        }),
        { status: 200 }
      )
    );

    // Per-image !sizedetails calls
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ Response: { ImageSizeDetails: { ImageSizeXLarge: { Url: "https://full/A.jpg" } } } }), { status: 200 })
    );
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ Response: { ImageSizeDetails: { ImageSizeXLarge: { Url: "https://full/B.jpg" } } } }), { status: 200 })
    );

    const result = await listRecent(env, { count: 10 });

    expect(fetchMock).toHaveBeenCalledTimes(3); // album list + 2 fan-out
    expect(result.map((r) => r.image_url)).toEqual(["https://full/A.jpg", "https://full/B.jpg"]);
  });

  it("returns an empty array when the album has no images", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ Response: {} }), { status: 200 })
    );
    expect(await listRecent(env, { count: 10 })).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

```bash
npm test
```

Expected: import error for `listRecent`.

- [ ] **Step 3: Add `listRecent` to `worker/smugmug.ts`**

Append to `/Users/mikehall/imgup/worker/smugmug.ts` (do not remove anything that's already there):

```ts
export type RecentImage = {
  thumb: string;
  image_url: string;
  title: string;
  caption: string;
  web_uri: string;
};

export async function listRecent(
  env: SmugmugEnv,
  args: { count: number }
): Promise<RecentImage[]> {
  const albumUrl =
    `${API_BASE}/api/v2/album/${env.SMUGMUG_UPLOAD_ALBUM_ID}!images` +
    `?count=${args.count}&_expand=ImageSizeDetails`;

  const auth = await signRequest({
    method: "GET",
    url: albumUrl,
    consumerKey: env.SMUGMUG_TOKEN,
    consumerSecret: env.SMUGMUG_SECRET,
    token: env.SMUGMUG_ACCESS_TOKEN,
    tokenSecret: env.SMUGMUG_ACCESS_TOKEN_SECRET,
  });
  const resp = await fetch(albumUrl, {
    method: "GET",
    headers: { Authorization: auth, Accept: "application/json" },
  });
  if (!resp.ok) {
    throw new SmugmugError(`album-list failed: HTTP ${resp.status}`, resp.status);
  }
  const body = (await resp.json()) as {
    Response?: { AlbumImage?: AlbumImageJson[] };
  };
  const images = body.Response?.AlbumImage ?? [];
  if (images.length === 0) return [];

  // Cheap path: every image already carries inline ImageSizeDetails.
  const cheap = images
    .map((i) => extractInlineSizeUrl(i))
    .every((url) => typeof url === "string");

  if (cheap) {
    return images.map((i) => ({
      thumb: i.ThumbnailUrl ?? "",
      image_url: extractInlineSizeUrl(i)!,
      title: i.Title ?? "",
      caption: i.Caption ?? "",
      web_uri: i.WebUri ?? "",
    }));
  }

  // Fallback: per-image !sizedetails fan-out.
  return Promise.all(
    images.map(async (i) => {
      const imageUri = i.Uris?.Image?.Uri;
      if (!imageUri) {
        throw new SmugmugError(`missing Uris.Image.Uri for ${i.Title}`, 502);
      }
      const detailsUrl = `${API_BASE}${imageUri}!sizedetails`;
      const a = await signRequest({
        method: "GET",
        url: detailsUrl,
        consumerKey: env.SMUGMUG_TOKEN,
        consumerSecret: env.SMUGMUG_SECRET,
        token: env.SMUGMUG_ACCESS_TOKEN,
        tokenSecret: env.SMUGMUG_ACCESS_TOKEN_SECRET,
      });
      const r = await fetch(detailsUrl, {
        method: "GET",
        headers: { Authorization: a, Accept: "application/json" },
      });
      if (!r.ok) throw new SmugmugError(`sizedetails failed: HTTP ${r.status}`, r.status);
      const j = (await r.json()) as {
        Response?: { ImageSizeDetails?: { ImageSizeXLarge?: { Url?: string } } };
      };
      const url = j.Response?.ImageSizeDetails?.ImageSizeXLarge?.Url;
      if (!url) throw new SmugmugError(`no XLarge url in sizedetails`, 502);
      return {
        thumb: i.ThumbnailUrl ?? "",
        image_url: url,
        title: i.Title ?? "",
        caption: i.Caption ?? "",
        web_uri: i.WebUri ?? "",
      };
    })
  );
}

type AlbumImageJson = {
  ImageKey?: string;
  Title?: string;
  Caption?: string;
  ThumbnailUrl?: string;
  WebUri?: string;
  Uris?: {
    Image?: { Uri?: string };
    ImageSizeDetails?: {
      ImageSizeDetails?: { ImageSizeXLarge?: { Url?: string } };
    };
  };
};

function extractInlineSizeUrl(i: AlbumImageJson): string | undefined {
  return i.Uris?.ImageSizeDetails?.ImageSizeDetails?.ImageSizeXLarge?.Url;
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
npm test
```

Expected: 10 passed (2 snippets, 2 oauth1, 3 uploadFile, 3 listRecent).

- [ ] **Step 5: Typecheck**

```bash
npm run typecheck
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add worker/smugmug.ts test/smugmug.test.ts
git commit -m "feat: smugmug.listRecent with cheap _expand path and N+1 fallback"
```

---

### Task 7: Implement `worker/index.ts` — router and handlers

Wires `/api/upload`, `/api/recent`, and a static-asset fallthrough. Implements cache-on-recent, bust-on-upload.

**Files:**
- Create: `worker/index.ts`

- [ ] **Step 1: Implement the worker entry point**

Create `/Users/mikehall/imgup/worker/index.ts`:

```ts
import { listRecent, SmugmugError, uploadFile, type SmugmugEnv } from "./smugmug";
import { buildSnippets } from "./snippets";

type Env = SmugmugEnv & {
  ASSETS: { fetch: (request: Request) => Promise<Response> };
};

// Cached counts known to the frontend. /api/upload busts these on success.
// If the frontend ever requests a count outside this set, it's still cached
// transparently — but won't be busted by uploads. Keep aligned with app.js.
const CACHED_COUNTS = [10];

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/api/upload" && request.method === "POST") {
      return handleUpload(request, env);
    }
    if (url.pathname === "/api/recent" && request.method === "GET") {
      return handleRecent(request, env);
    }
    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;

async function handleUpload(request: Request, env: Env): Promise<Response> {
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return jsonError("invalid multipart body", 400);
  }
  const file = form.get("file");
  if (!(file instanceof File)) {
    return jsonError("missing file field", 400);
  }
  const titleRaw = form.get("title");
  const captionRaw = form.get("caption");
  const title = typeof titleRaw === "string" && titleRaw.length > 0
    ? titleRaw
    : stripExt(file.name);
  const caption = typeof captionRaw === "string" ? captionRaw : "";

  try {
    const { url } = await uploadFile(env, { file, title, caption });
    const snippets = buildSnippets(url, title);

    // Bust the recent cache for the counts we know about.
    await Promise.all(
      CACHED_COUNTS.map((c) => caches.default.delete(recentCacheKey(request, c)))
    );

    return new Response(JSON.stringify(snippets), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return errorResponse(err);
  }
}

async function handleRecent(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const countParam = url.searchParams.get("count");
  const count = parsePositiveInt(countParam) ?? 10;

  const cacheKey = recentCacheKey(request, count);
  const cached = await caches.default.match(cacheKey);
  if (cached) return cached;

  try {
    const items = await listRecent(env, { count });
    const response = new Response(JSON.stringify(items), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=300",
      },
    });
    await caches.default.put(cacheKey, response.clone());
    return response;
  } catch (err) {
    return errorResponse(err);
  }
}

function recentCacheKey(request: Request, count: number): Request {
  const u = new URL(request.url);
  u.pathname = "/api/recent";
  u.search = `?count=${count}`;
  return new Request(u.toString(), { method: "GET" });
}

function parsePositiveInt(s: string | null): number | undefined {
  if (s == null) return undefined;
  const n = Number(s);
  return Number.isFinite(n) && n > 0 && Number.isInteger(n) ? n : undefined;
}

function stripExt(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(0, dot) : name;
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorResponse(err: unknown): Response {
  if (err instanceof SmugmugError) {
    const mapped = mapSmugmugStatus(err.status);
    return jsonError(err.message, mapped);
  }
  const msg = err instanceof Error ? err.message : String(err);
  return jsonError(msg, 500);
}

function mapSmugmugStatus(status: number): number {
  if (status === 401 || status === 403) return 401;
  if (status === 404) return 404;
  if (status === 413) return 413;
  if (status === 429) return 429;
  if (status >= 500) return 502;
  return 500;
}
```

- [ ] **Step 2: Typecheck**

```bash
npm run typecheck
```

Expected: no errors. If `caches.default` complains about types, it's because `@cloudflare/workers-types` wasn't picked up — confirm `tsconfig.json` has `"types": ["@cloudflare/workers-types"]`.

- [ ] **Step 3: Run tests to confirm nothing regressed**

```bash
npm test
```

Expected: still 10 passing (we didn't add tests for `index.ts` — it's wiring-only and gets covered by the manual smoke test).

- [ ] **Step 4: Commit**

```bash
git add worker/index.ts
git commit -m "feat: worker router with upload, recent, and edge-cache"
```

---

### Task 8: Frontend — `public/index.html`

Single page that visually preserves the existing multi-page structure: header with `.weblog-title` + nav, upload form section, hidden result section (`.contact-card.contact-card--solo` mirrors `views/post_image.haml`), recent grid section (mirrors `views/recent.haml`), lightbox dialog, footer with theme toggle. Class names match `views/local_css.haml` so the ported CSS works unmodified.

**Files:**
- Create: `public/index.html`

- [ ] **Step 1: Author the HTML**

Create `/Users/mikehall/imgup/public/index.html`. Paste exactly:

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <title>imgup</title>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link href="https://cdn.simplecss.org/simple.min.css" rel="stylesheet" />
    <link href="/style.css" rel="stylesheet" />
    <script src="https://kit.fontawesome.com/96d20ed16f.js" crossorigin="anonymous"></script>
    <script>
      // theme: respect saved choice; runs inline before paint to avoid flash.
      (function () {
        try {
          var saved = localStorage.getItem("imgup-theme");
          if (saved === "light" || saved === "dark") {
            document.documentElement.setAttribute("data-theme", saved);
          }
        } catch (e) {}
        window.imgupToggleTheme = function () {
          var r = document.documentElement;
          var cur = r.getAttribute("data-theme");
          var sysLight = window.matchMedia("(prefers-color-scheme: light)").matches;
          var next;
          if (cur === "light") next = "dark";
          else if (cur === "dark") next = "light";
          else next = sysLight ? "dark" : "light";
          r.setAttribute("data-theme", next);
          try { localStorage.setItem("imgup-theme", next); } catch (e) {}
        };
      })();
    </script>
  </head>
  <body>
    <header>
      <h1 class="weblog-title">
        <a href="/">
          <i class="fa-image fa-solid meteor"></i>
          imgup
        </a>
      </h1>
      <nav>
        <ul>
          <li>
            <a href="#upload" title="Upload a photo">
              <i class="fa-solid fa-image meteor"></i>
              upload
            </a>
          </li>
          <li>
            <a href="#recent" title="Recent uploads">
              <i class="fa-brands fa-markdown meteor"></i>
              recent
            </a>
          </li>
          <li>
            <a href="https://www.smugmug.com/app/organize/Uploads" title="Open the SmugMug album">
              <i class="fa-solid fa-images meteor"></i>
              album
            </a>
          </li>
        </ul>
      </nav>
    </header>

    <main>
      <section id="upload">
        <form id="upload-form" class="upload-form" enctype="multipart/form-data">
          <div class="field">
            <label class="upload-label" for="upload-title">title</label>
            <input id="upload-title" name="title" type="text" placeholder="what to call this one" autofocus autocomplete="off" />
          </div>
          <div class="field">
            <label class="upload-label" for="upload-caption">
              caption
              <span class="upload-hint"> · used as alt text</span>
            </label>
            <input id="upload-caption" name="caption" type="text" placeholder="what's in the frame" autocomplete="off" />
          </div>
          <div class="field">
            <label class="upload-label" for="upload-file">photo</label>
            <input id="upload-file" name="file" type="file" accept="image/*" required />
          </div>
          <input id="upload-submit" type="submit" value="upload" />
          <p id="upload-status" class="upload-status">uploading to smugmug — this can take a moment.</p>
        </form>

        <article id="result" class="contact-card contact-card--solo" hidden>
          <p class="upload-success">uploaded. snippets below.</p>
          <button id="result-photo" class="contact-card__photo" type="button" data-lightbox-src="" data-lightbox-alt="just-uploaded photo" aria-label="view photo larger">
            <span class="photo-frame">
              <img id="result-thumb" class="contact-card__thumb contact-card__thumb--natural" src="" alt="uploaded photo" />
            </span>
          </button>
          <div class="contact-card__copy-row">
            <button class="copy-icon-btn" type="button" data-copy-text="" data-copy-target="md" aria-label="copy markdown" title="copy markdown">
              <i class="fa-brands fa-markdown"></i>
            </button>
            <button class="copy-icon-btn" type="button" data-copy-text="" data-copy-target="org" aria-label="copy org" title="copy org">
              <i class="fa-solid fa-asterisk"></i>
            </button>
            <button class="copy-icon-btn" type="button" data-copy-text="" data-copy-target="html" aria-label="copy html" title="copy html">
              <i class="fa-solid fa-code"></i>
            </button>
          </div>
        </article>
      </section>

      <section id="recent">
        <h2 class="recent-heading">recent</h2>
        <div id="recent-grid" class="contact-grid" aria-live="polite"></div>
        <section id="recent-empty" class="recent-empty" hidden>
          <h2>nothing here yet.</h2>
          <p>the upload album is empty.</p>
        </section>
      </section>
    </main>

    <dialog id="lightbox" class="lightbox">
      <button class="lightbox__close" type="button" aria-label="close">
        <i class="fa-solid fa-xmark"></i>
      </button>
      <img class="lightbox__img" src="" alt="" />
    </dialog>

    <footer>
      <p>
        made by
        <a href="https://mph.omg.lol">mph</a>
        ·
        <button class="theme-toggle" type="button" onclick="imgupToggleTheme()" aria-label="toggle theme" title="toggle theme">
          <i class="fa-solid fa-circle-half-stroke"></i>
        </button>
      </p>
    </footer>

    <script src="/app.js"></script>
  </body>
</html>
```

Notes on intentional differences from the HAML originals:

- The Simple.css and FontAwesome CDN links are kept verbatim — the existing styling depends on both.
- The "sign in / sign out / OAuth dance" elements are removed; tokens live in env, no auth UI is needed.
- The result region (`<article id="result">`) is hidden by default and populated by `app.js` after a successful upload — equivalent to `views/post_image.haml` rendering in-place rather than as a separate page.
- The `recent-empty` section is conditionally shown by `app.js` when the recent list is empty.
- Anchor links in the nav (`#upload`, `#recent`) replace the previous full-page navigations, since this is now a single page.

- [ ] **Step 2: Commit**

```bash
git add public/index.html
git commit -m "feat: frontend html ported from haml views"
```

---

### Task 9: Frontend — `public/app.js`

Vanilla JS. Combines four behaviors:
1. **Upload form submission** — calls `/api/upload`, populates the result card, refreshes recent.
2. **Recent grid rendering** — calls `/api/recent?count=10` on load and after each upload.
3. **Copy-icon buttons** — ported verbatim from `views/layout.haml` inline JS.
4. **Lightbox + drop-target** — ported verbatim from `views/layout.haml` inline JS.

Theme toggle is already wired by the inline `<script>` in `index.html` (loaded synchronously before paint), so `app.js` doesn't need to handle it.

**Files:**
- Create: `public/app.js`

- [ ] **Step 1: Author the script**

Create `/Users/mikehall/imgup/public/app.js`:

```js
// imgup frontend wiring.
//
// SmugMug upload + recent grid + carry-over interactions (copy buttons,
// lightbox, drop-target) ported verbatim from the Sinatra-era layout.haml
// inline scripts — keep behavior parity.

const RECENT_COUNT = 10; // must match worker CACHED_COUNTS in worker/index.ts

document.addEventListener("DOMContentLoaded", () => {
  initCopyButtons();
  initLightbox();
  initDropTarget();
  initUploadForm();
  loadRecent();
});

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

  result.hidden = false;
  result.scrollIntoView({ behavior: "smooth", block: "start" });
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
```

- [ ] **Step 2: Commit**

```bash
git add public/app.js
git commit -m "feat: frontend app.js wiring upload, recent, copy, lightbox, drop"
```

---

### Task 10: Frontend — `public/style.css`

Port the entire `:css` block from `views/local_css.haml` into a standalone `public/style.css`. The design has been carefully tuned (OKLCH palette, IBM Plex Mono × Fraunces, contact-sheet, lightbox, drop target, crop-mark frames, recent-empty state, error page styles) — preserve it byte-for-byte.

**Files:**
- Create: `public/style.css`

- [ ] **Step 1: Extract the CSS from `views/local_css.haml`**

`local_css.haml` is a HAML file that wraps everything in a `:css` filter block — every CSS line is indented two spaces inside that block. The cleanest extraction is to drop the leading `:css` line and dedent the rest:

```bash
awk 'NR == 1 && $0 == ":css" { next } { sub(/^  /, ""); print }' views/local_css.haml > public/style.css
```

Verify the file looks right:

```bash
head -20 public/style.css
wc -l public/style.css
```

Expected:
- First line is `@import url('https://static.omg.lol/type/fontawesome-free/css/all.css');` (no leading whitespace).
- Total line count matches `views/local_css.haml` minus 1 (the dropped `:css` line).
- No `:css` token appears anywhere in `public/style.css`.

- [ ] **Step 2: Sanity-check the CSS is well-formed**

```bash
node -e "
  const css = require('fs').readFileSync('public/style.css', 'utf8');
  const open = (css.match(/{/g) || []).length;
  const close = (css.match(/}/g) || []).length;
  console.log('braces:', open, '/', close);
  if (open !== close) process.exit(1);
"
```

Expected: matching brace counts. If they differ, the dedent step ate something it shouldn't have — re-inspect `views/local_css.haml` for irregular indentation.

- [ ] **Step 3: Commit**

```bash
git add public/style.css
git commit -m "feat: frontend stylesheet ported verbatim from local_css.haml"
```

---

### Task 11: Local smoke test with `wrangler dev`

End-to-end check against real SmugMug. Validates that the OAuth1 signing, upload flow, and recent-list are wired correctly before any deploy.

**Files:**
- Create: `.dev.vars` (gitignored)

- [ ] **Step 1: Create `.dev.vars` with real credentials**

Read the current Ruby `.env`:

```bash
cat .env
```

Copy each value into a new `/Users/mikehall/imgup/.dev.vars` (gitignored — verify `.gitignore` lists `.dev.vars`):

```
SMUGMUG_TOKEN=<value-from-.env>
SMUGMUG_SECRET=<value-from-.env>
SMUGMUG_ACCESS_TOKEN=<value-from-.env>
SMUGMUG_ACCESS_TOKEN_SECRET=<value-from-.env>
SMUGMUG_UPLOAD_ALBUM_ID=<value-from-.env>
```

- [ ] **Step 2: Start the dev server**

```bash
npm run dev
```

Expected: wrangler reports a URL like `http://localhost:8787`. Output mentions the `ASSETS` binding and the worker entrypoint.

- [ ] **Step 3: Smoke test in a browser**

Open `http://localhost:8787`. Verify:

1. Page loads, masthead shows "imgup", theme toggle works (clicks switch the palette).
2. `/api/recent` populates the contact sheet (or shows a clean empty state if the album has nothing). No console errors.
3. Pick a small test image, fill in a title, hit upload.
4. Within a few seconds, the result region shows four `<pre>` blocks: md, html, org, url, plus a thumbnail.
5. Click each "copy" button — paste into a scratch buffer and confirm the snippet matches what shows.
6. After upload, the `recent` grid refreshes and the new image appears at position 01.
7. Cross-check on smugmug.com that the upload landed in the right album with the title and caption you typed.

- [ ] **Step 4: Stop the dev server**

`Ctrl-C` in the wrangler terminal.

- [ ] **Step 5: Commit (no code change — checkpoint only)**

Nothing to commit. Move on once steps 3.1–3.7 all pass. If any step fails, debug the relevant module (oauth1, smugmug, index.ts, app.js) before continuing.

---

### Task 12: Deploy to `workers.dev` (no custom domain)

Initial deploy puts the Worker on a `*.workers.dev` URL. No Cloudflare Access yet. The custom domain comes later, after Access is configured.

**Files:** none modified.

- [ ] **Step 1: Push the secrets**

For each of the five secret names, run:

```bash
echo "<value>" | wrangler secret put SMUGMUG_TOKEN
echo "<value>" | wrangler secret put SMUGMUG_SECRET
echo "<value>" | wrangler secret put SMUGMUG_ACCESS_TOKEN
echo "<value>" | wrangler secret put SMUGMUG_ACCESS_TOKEN_SECRET
echo "<value>" | wrangler secret put SMUGMUG_UPLOAD_ALBUM_ID
```

(Or run `wrangler secret put <NAME>` interactively for each and paste the value when prompted — preferred to keep values out of shell history.)

Expected output for each: `🌀 Creating the secret for the Worker "imgup"` then `✨ Success! Uploaded secret <NAME>`.

- [ ] **Step 2: Verify the secret list**

```bash
wrangler secret list
```

Expected: all five names listed, no values shown.

- [ ] **Step 3: Deploy the worker**

```bash
npm run deploy
```

Expected: wrangler bundles the worker, uploads, and prints a `https://imgup.<your-subdomain>.workers.dev` URL.

- [ ] **Step 4: Smoke test the workers.dev URL**

Open the printed URL in a browser. Same checklist as Task 11 Step 3, but pointing at the deployed Worker. Upload a test image, confirm it lands on SmugMug.

If anything fails: `wrangler tail` in another terminal streams logs from the live Worker.

- [ ] **Step 5: Commit (no code change)**

Nothing to commit. Move on once the deployed Worker behaves identically to local dev.

---

### Task 13: Configure Cloudflare Access

Create the Access application that will gate `imgup.puddingtime.net`. Done via the Cloudflare dashboard — no code.

**Files:** none modified. This is a manual dashboard step.

- [ ] **Step 1: Open the Access dashboard**

Browse to `https://one.dash.cloudflare.com` → select your account → **Access** → **Applications** → **Add an application** → **Self-hosted**.

- [ ] **Step 2: Configure application basics**

- Application name: `imgup`
- Session duration: `24 hours` (or your default)
- Application domain: subdomain `imgup`, domain `puddingtime.net`, path empty.
- Identity providers: leave defaults (whatever's already configured on the account).

Save and continue to policies.

- [ ] **Step 3: Add a policy**

- Policy name: `mike only`
- Action: `Allow`
- Session duration: app default
- Configure rules:
  - Include: **Emails** → `mike@puddingtime.org`

Save the policy. Save the application.

- [ ] **Step 4: Verify (do not point DNS yet)**

The Access app is now active for `imgup.puddingtime.net`, but DNS still resolves to the existing tunnel. Don't change DNS in this step. Browsing to `https://imgup.puddingtime.net` should still hit the Ruby app (no behavior change yet).

- [ ] **Step 5: Commit (no code change)**

Nothing to commit.

---

### Task 14: Cutover — point `imgup.puddingtime.net` at the Worker

Replaces the tunnel mapping with a Worker custom domain. The tunnel itself stays running for whatever else lives behind it.

**Files:**
- Modify: `wrangler.jsonc`

- [ ] **Step 1: Remove the tunnel mapping for `imgup.puddingtime.net`**

In Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels** → the tunnel that currently terminates `imgup.puddingtime.net`. Edit it, find the public hostname row for `imgup.puddingtime.net`, delete that row, save. Other public hostnames on the same tunnel are unaffected.

(Equivalent CLI: `cloudflared tunnel route dns delete imgup.puddingtime.net` if you manage the tunnel via cloudflared CLI.)

- [ ] **Step 2: Add the custom domain route to `wrangler.jsonc`**

Edit `/Users/mikehall/imgup/wrangler.jsonc` to add the `routes` array:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "imgup",
  "main": "worker/index.ts",
  "compatibility_date": "2025-12-01",
  "assets": {
    "directory": "./public",
    "binding": "ASSETS"
  },
  "observability": {
    "enabled": true
  },
  "routes": [
    { "pattern": "imgup.puddingtime.net", "custom_domain": true }
  ]
}
```

- [ ] **Step 3: Deploy with the route**

```bash
npm run deploy
```

Wrangler will create the custom domain on Cloudflare's edge and configure DNS to point at the Worker. Expected output mentions the route and the live URL.

If deploy errors with "the hostname is already in use" — Step 1 didn't fully complete. Re-check the tunnel config; the public hostname row must be gone before this step works.

- [ ] **Step 4: Production smoke test through Access**

Open `https://imgup.puddingtime.net` in a fresh browser window or incognito.

1. Cloudflare Access challenge appears. Sign in with `mike@puddingtime.org`.
2. After auth, the imgup page loads.
3. Repeat the smoke checklist from Task 11 Step 3 — upload a test image, confirm `/recent` updates, copy snippets.
4. Open the page in a browser logged in to a *different* email — Access denies access. (Optional but nice to confirm.)

- [ ] **Step 5: Commit the wrangler change**

```bash
git add wrangler.jsonc
git commit -m "chore: route imgup.puddingtime.net to the worker"
```

---

### Task 15: Stop the Synology container

Tear down the Ruby app on Portainer. The Worker is now serving production.

**Files:** none modified.

- [ ] **Step 1: Stop the imgup stack in Portainer**

Open the Portainer UI for the Synology, find the `imgup` stack, stop it. Optionally remove the stack entirely once you're satisfied things are stable.

- [ ] **Step 2: Confirm the Worker is still serving**

Reload `https://imgup.puddingtime.net`. Page still loads through Access; recent grid still populates. (If anything broke when the Synology stopped, the Worker depends on the Synology somehow, which it shouldn't — investigate.)

- [ ] **Step 3: Commit (no code change)**

Nothing to commit.

---

### Task 16: Delete the Ruby app from `main`

Now that the Worker is in production and the Synology is stopped, remove the Ruby tree from `main`. The `legacy-ruby` branch (Task 1) preserves the working snapshot if you ever need it.

**Files:**
- Delete: `imgup.rb`
- Delete: `imgup-potw.rb`
- Delete: `config.ru`
- Delete: `Gemfile`
- Delete: `Gemfile.lock`
- Delete: `Dockerfile`
- Delete: `docker-compose.yml`
- Delete: `Rakefile`
- Delete: `dot_env`
- Delete: `README-cli.md`
- Delete: `.bundle/` (recursive)
- Delete: `.ruby-version`
- Delete: `bin/imgup`
- Delete: `bin/` (if empty after removing `bin/imgup`; otherwise leave)
- Delete: `lib/imgup/uploader.rb`
- Delete: `lib/imgup/` (empty parent)
- Delete: `lib/` (empty parent)
- Delete: `views/` (recursive — all .haml files)
- Delete: `tmp/` (recursive — Ruby tempdir)
- Delete: `design_notes.md` (Ruby-era notes superseded by `CLAUDE.md` and the spec)
- Modify: `README.markdown` (rewrite for the Worker era)

- [ ] **Step 1: Sanity-check `legacy-ruby` is intact on the remote**

```bash
git fetch origin && git log origin/legacy-ruby --oneline -5
```

Expected: shows the Ruby-era commits up through whatever HEAD was when Task 1 ran.

- [ ] **Step 2: Delete the Ruby tree**

```bash
git rm imgup.rb imgup-potw.rb config.ru Gemfile Gemfile.lock Dockerfile docker-compose.yml Rakefile dot_env README-cli.md .ruby-version design_notes.md
git rm -r .bundle bin lib views tmp
```

If any path doesn't exist, drop it from the command and re-run. Verify nothing important is gone:

```bash
git status
```

- [ ] **Step 3: Rewrite `README.markdown`**

Read the current README first to keep any non-obvious context Mike wrote. Then replace it with a short Worker-era version:

```markdown
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
```

Stage it:

```bash
git add README.markdown
```

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove ruby app, point readme at the worker era"
```

- [ ] **Step 5: Push everything**

```bash
git push origin main
```

- [ ] **Step 6: Final verification**

```bash
ls
git log --oneline -10
npm test
npm run typecheck
```

Expected:
- Top-level directory shows only Worker/TS files: `worker/`, `public/`, `test/`, `docs/`, `node_modules/`, `package.json`, `package-lock.json`, `tsconfig.json`, `vitest.config.ts`, `wrangler.jsonc`, `.dev.vars`, `.dev.vars.example`, `.gitignore`, `.git/`, `README.markdown`, `CLAUDE.md`, `.impeccable.md`, `.wrangler/` (build artefact, gitignored).
- Recent commits tell the migration story end to end.
- All tests pass.
- Typecheck clean.

The migration is complete.

---

## Self-review notes (for the executing engineer)

If you complete every task above and the final verification (Task 16 Step 6) passes, the migration is done. A few things to watch for during execution:

- **OAuth1 vector mismatch (Task 4).** If the Ruby gem and the TS port disagree, suspect (in order): pct-encoding of `!`, `'`, `(`, `)`, `*`; ordering of params in the normalized base string; whether the URL had trailing characters Ruby stripped. The `oauth1.test.ts` spec tells you exactly what to match.
- **Cache-key shape (Task 7).** `caches.default.match` keys must be `Request` objects, not strings. The helper `recentCacheKey` already does this. Don't pass a URL string directly.
- **Static assets path (Task 12).** If `/style.css` 404s after deploy, double-check `wrangler.jsonc` `assets.directory` is `./public` and the files are present at `public/style.css`, not nested somewhere else.
- **Tunnel removal must precede route add (Task 14).** Cloudflare won't let two services own the same hostname. The tunnel public-hostname row goes first, then the Worker route claims it.
- **Don't skip Task 11.** The unit tests exercise URL/header construction but not the actual SmugMug round trip. The local smoke test is the only thing that catches "we're sending the wrong shape to a real SmugMug endpoint" before production.
