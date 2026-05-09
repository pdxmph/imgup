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
