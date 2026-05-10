import { defineConfig } from "vite";
import { lezer } from "@lezer/generator/rollup";

export default defineConfig({
  plugins: [lezer()],
  server: {
    port: 5180,
    strictPort: false,
  },
  build: {
    target: "es2022",
    sourcemap: true,
  },
});
