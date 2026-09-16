import { copyFile, mkdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

if (process.argv.length !== 3) throw new Error('Usage: node scripts/build-audio-power-core.mjs <destination>');
const root = new URL('../', import.meta.url);
const build = spawnSync('moon', ['-C', 'packages/browser/host', 'build', 'audio_power', '--target', 'js', '--release'], {
  cwd: fileURLToPath(root),
  env: { ...process.env, NEW_MOON_MOD: '0' },
  stdio: 'inherit',
});
if (build.error) throw build.error;
if (build.status !== 0) process.exit(build.status ?? 1);

const destination = resolve(process.argv[2]);
await mkdir(dirname(destination), { recursive: true });
await copyFile(new URL('packages/browser/host/_build/js/release/build/audio_power/audio_power.js', root), destination);
