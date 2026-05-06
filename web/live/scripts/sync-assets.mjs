// Copies processor.js + moonbit_dsp.wasm from web/ into web/live/public/
// so Vite's dev server and production build serve them at the site root.
//
// Run by `npm run sync:assets`, automatically before `dev` and `build`.

import { mkdirSync, copyFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const liveDir = resolve(here, "..");
const webDir = resolve(liveDir, "..");
const publicDir = resolve(liveDir, "public");

const ASSETS = ["processor.js", "moonbit_dsp.wasm"];

mkdirSync(publicDir, { recursive: true });

let missing = 0;
for (const name of ASSETS) {
  const src = resolve(webDir, name);
  const dst = resolve(publicDir, name);
  if (!existsSync(src)) {
    console.warn(`[sync-assets] missing ${src}`);
    missing++;
    continue;
  }
  copyFileSync(src, dst);
  console.log(`[sync-assets] ${name}`);
}

if (missing > 0) {
  console.warn(
    `[sync-assets] ${missing} asset(s) missing — build moondsp first ` +
      `(\`moon build browser --target wasm-gc --release\`) then rerun.`,
  );
}
