// Builds the engine and the authoring adapter, then copies them with the shared
// worklet modules into web/live so Vite's dev server and production build serve
// the current engine. Any missing file fails the run.
//
// Run by `npm run sync:assets`, automatically before `dev` and `build`.

import { mkdirSync, copyFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const liveDir = resolve(here, "..");
const webDir = resolve(liveDir, "..");
const repoDir = resolve(webDir, "..");
const publicDir = resolve(liveDir, "public");
const generatedDir = resolve(liveDir, "src/generated");
const releaseBuildDir = (target) => resolve(repoDir, "_build", target, "release/build");

function moonBuild(pkg, target) {
  execFileSync("moon", ["build", pkg, "--target", target, "--release"], {
    cwd: repoDir,
    env: { ...process.env, NEW_MOON_MOD: "0" },
    stdio: "inherit",
  });
}

function copy(source, destination) {
  copyFileSync(source, destination);
  console.log(`[sync-assets] ${destination}`);
}

moonBuild("browser", "wasm-gc");
moonBuild("browser_authoring", "js");

mkdirSync(generatedDir, { recursive: true });
mkdirSync(publicDir, { recursive: true });
copy(resolve(releaseBuildDir("js"), "browser_authoring/browser_authoring.js"), resolve(generatedDir, "authoring.js"));
copy(resolve(releaseBuildDir("wasm-gc"), "browser/browser.wasm"), resolve(publicDir, "moonbit_dsp.wasm"));
for (const worklet of ["playback-controller.js", "playback-onsets.js", "scheduler-processor.js"]) {
  copy(resolve(webDir, worklet), resolve(publicDir, worklet));
}
