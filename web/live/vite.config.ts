import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig, normalizePath } from "vite";
import type { Plugin } from "vite";
import { lezer } from "@lezer/generator/rollup";

const helpSections = [
  { id: "syntax-reference", file: "../../docs/mini-notation.md", marker: "LIVE_SYNTAX_REFERENCE", slot: "MINI_SYNTAX_REFERENCE" },
  { id: "recipes", file: "../../docs/guides/live-coding-cookbook.md", marker: "LIVE_RECIPES", slot: "LIVE_RECIPES" },
  { id: "playback-guide", file: "../../docs/guides/live-playback.md", marker: "LIVE_PLAYBACK_GUIDE", slot: "LIVE_PLAYBACK_GUIDE" },
].map(section => ({ ...section, url: new URL(section.file, import.meta.url) }));

const authoringHelp: Plugin = {
  name: "authoring-help",
  buildStart() {
    for (const section of helpSections) this.addWatchFile(fileURLToPath(section.url));
  },
  transformIndexHtml(html) {
    for (const section of helpSections) {
      const document = readFileSync(section.url, "utf8");
      const match = document.match(new RegExp(`<!-- ${section.marker}_START -->([\\s\\S]*?)<!-- ${section.marker}_END -->`));
      if (!match?.[1].trim()) {
        throw new Error(`${section.file} is missing its ${section.marker} block`);
      }
      const parts = html.split(`<!-- ${section.slot} -->`);
      if (parts.length !== 2) {
        throw new Error(`index.html must contain exactly one ${section.slot} placeholder`);
      }
      // Keep source links useful in Markdown; embedded chapters navigate within help.
      const content = match[1].trim().replace(/href="([^"]+)"/g, (attribute, href: string) => {
        const link = new URL(href, section.url);
        const chapter = helpSections.find(candidate =>
          candidate.url.origin === link.origin && candidate.url.pathname === link.pathname);
        return chapter ? `href="${link.hash || `#${chapter.id}`}"` : attribute;
      });
      html = parts[0] + content + parts[1];
    }
    return html;
  },
  handleHotUpdate({ file, server }) {
    if (helpSections.some(section => normalizePath(file) === normalizePath(fileURLToPath(section.url)))) {
      server.ws.send({ type: "full-reload" });
      return [];
    }
  },
};

export default defineConfig({
  plugins: [lezer(), authoringHelp],
  server: {
    port: 5180,
    strictPort: false,
  },
  build: {
    target: "es2022",
    sourcemap: true,
  },
});
