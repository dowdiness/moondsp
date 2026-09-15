import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  plugins: [svelte()],
  optimizeDeps: {
    exclude: ["@moondsp/browser"],
  },
  build: {
    target: "es2022",
    assetsInlineLimit: 0,
  },
});
