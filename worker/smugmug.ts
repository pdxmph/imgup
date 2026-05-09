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
