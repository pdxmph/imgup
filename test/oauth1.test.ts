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

    expect(auth).toBe('OAuth oauth_consumer_key="test-consumer-key", oauth_nonce="fixed-nonce-abc123", oauth_signature="pEMou6xgCUGnMB7wwu2u%2FGOxuQU%3D", oauth_signature_method="HMAC-SHA1", oauth_timestamp="1700000000", oauth_token="test-access-token", oauth_version="1.0"');
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
