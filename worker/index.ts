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
  const file = form.get("file") as File | string | null;
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
