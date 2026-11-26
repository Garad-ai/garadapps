import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

// Built into the Flutter assets; the app serves them from its own localhost server (the parser's
// worker and WebAssembly need http, not file://). Relative paths, so the folder can live anywhere.
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    outDir: "../assets/slides",
    emptyOutDir: true,
    assetsDir: "assets",
    sourcemap: false,
    chunkSizeWarningLimit: 4000,
  },
})
