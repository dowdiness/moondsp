// Copies processor.js + moonbit_dsp.wasm from web/ into web/live/public/
// so Vite's dev server and production build serve them at the site root.
//
// Run by `npm run sync:assets`, automatically before `dev` and `build`.

import { mkdirSync, copyFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const liveDir = resolve(here, "..");
const webDir = resolve(liveDir, "..");
const repoDir = resolve(webDir, "..");
const publicDir = resolve(liveDir, "public");
const generatedDir = resolve(liveDir, "src/generated");
const ASSETS = ["playback-controller.js", "processor.js", "scheduler-processor.js", "moonbit_dsp.wasm"];
const authoringSource = resolve(repoDir, "_build/js/release/build/browser_authoring/browser_authoring.js");

mkdirSync(generatedDir, { recursive: true });
execFileSync("moon", ["build", "browser_authoring", "--target", "js", "--release"], {
  cwd: repoDir,
  env: { ...process.env, NEW_MOON_MOD: "0" },
  stdio: "inherit",
});
copyFileSync(authoringSource, resolve(generatedDir, "authoring.js"));
console.log("[sync-assets] authoring.js");
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
