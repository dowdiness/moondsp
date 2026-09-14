import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig, normalizePath } from "vite";
import type { Plugin } from "vite";
import { lezer } from "@lezer/generator/rollup";

const referencePath = fileURLToPath(new URL("../../docs/mini-notation.md", import.meta.url));
const referencePlaceholder = "<!-- MINI_SYNTAX_REFERENCE -->";

const syntaxReference: Plugin = {
  name: "mini-syntax-reference",
  buildStart() {
    this.addWatchFile(referencePath);
  },
  transformIndexHtml(html) {
    const reference = readFileSync(referencePath, "utf8");
    const match = reference.match(/<!-- LIVE_SYNTAX_REFERENCE_START -->([\s\S]*?)<!-- LIVE_SYNTAX_REFERENCE_END -->/);
    if (!match?.[1].trim()) {
      throw new Error("docs/mini-notation.md is missing its live syntax reference block");
    }
    const parts = html.split(referencePlaceholder);
    if (parts.length !== 2) {
      throw new Error("index.html must contain exactly one MINI_SYNTAX_REFERENCE placeholder");
    }
    return parts[0] + match[1].trim() + parts[1];
  },
  handleHotUpdate({ file, server }) {
    if (normalizePath(file) === normalizePath(referencePath)) {
      server.ws.send({ type: "full-reload" });
      return [];
    }
  },
};

export default defineConfig({
  plugins: [lezer(), syntaxReference],
  server: {
    port: 5180,
    strictPort: false,
  },
  build: {
    target: "es2022",
    sourcemap: true,
  },
});
