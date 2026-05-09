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
