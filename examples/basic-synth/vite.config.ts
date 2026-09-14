import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  optimizeDeps: {
    exclude: ["@moondsp/browser"],
  },
  build: {
    target: "es2022",
    assetsInlineLimit: 0,
  },
});
