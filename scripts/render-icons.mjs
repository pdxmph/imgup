// One-shot rasterizer: reads public/icons/imgup.svg, writes four PNGs.
// Run via: npm run icons
//
// Outputs:
//   public/icons/icon-192.png            — full SVG, 192×192
//   public/icons/icon-512.png            — full SVG, 512×512
//   public/icons/icon-512-maskable.png   — SVG composited at 65% scale on the
//                                          warm-paper background (Android safe zone)
//   public/icons/apple-touch-icon-180.png — full SVG, 180×180

import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const SRC = path.resolve("public/icons/imgup.svg");
const OUT = path.resolve("public/icons");
const BG = "#f1e5cf"; // warm-paper, must match the SVG background

const svg = await readFile(SRC);

async function render(filename, size) {
  const png = await sharp(svg, { density: 600 })
    .resize(size, size, { fit: "contain", background: BG })
    .png({ compressionLevel: 9 })
    .toBuffer();
  await writeFile(path.join(OUT, filename), png);
  console.log(`✓ ${filename} (${size}×${size}, ${png.length} bytes)`);
}

async function renderMaskable(filename, size) {
  const innerSize = Math.round(size * 0.65);
  const inner = await sharp(svg, { density: 600 })
    .resize(innerSize, innerSize, { fit: "contain", background: BG })
    .png()
    .toBuffer();

  const png = await sharp({
    create: { width: size, height: size, channels: 4, background: BG },
  })
    .composite([{ input: inner, gravity: "center" }])
    .png({ compressionLevel: 9 })
    .toBuffer();
  await writeFile(path.join(OUT, filename), png);
  console.log(`✓ ${filename} (${size}×${size} maskable, ${png.length} bytes)`);
}

await render("icon-192.png", 192);
await render("icon-512.png", 512);
await render("apple-touch-icon-180.png", 180);
await renderMaskable("icon-512-maskable.png", 512);

console.log("done.");
