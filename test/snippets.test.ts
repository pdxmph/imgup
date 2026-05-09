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
