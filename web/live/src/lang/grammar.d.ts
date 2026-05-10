// Type shim for the Vite/Rollup `@lezer/generator/rollup` plugin —
// it compiles `.grammar` source to a module that exports `parser`.
declare module "*.grammar" {
  export const parser: import("@lezer/lr").LRParser;
}
