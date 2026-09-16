import { copyFile, mkdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const build = spawnSync('moon', ['build', 'browser', '--target', 'wasm-gc', '--release'], {
  cwd: fileURLToPath(root),
  env: { ...process.env, NEW_MOON_MOD: '0' },
  stdio: 'inherit',
});
if (build.error) throw build.error;
if (build.status !== 0) process.exit(build.status ?? 1);

const destination = new URL('packages/browser/dist/', root);
await mkdir(destination, { recursive: true });
const core = spawnSync(process.execPath, [
  fileURLToPath(new URL('scripts/build-audio-power-core.mjs', root)),
  fileURLToPath(new URL('audio-power-core.js', destination)),
], { cwd: fileURLToPath(root), stdio: 'inherit' });
if (core.error) throw core.error;
if (core.status !== 0) process.exit(core.status ?? 1);
await Promise.all([
  ...['graph-engine.js', 'graph-engine.d.ts', 'graph-processor.js', 'audio-power.js', 'audio-power.d.ts'].map(name =>
    copyFile(new URL(`web/${name}`, root), new URL(name, destination))),
  copyFile(new URL('_build/wasm-gc/release/build/browser/browser.wasm', root),
    new URL('moonbit_dsp.wasm', destination)),
  copyFile(new URL('LICENSE', root), new URL('LICENSE', destination)),
]);
console.log('Built @moondsp/browser: JS, declarations, Worklet, Wasm, and license.');
