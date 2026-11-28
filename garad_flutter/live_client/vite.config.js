import { defineConfig } from "vite"

// Built into the Flutter assets and served by the app's own localhost server (lib/local_pages.dart):
// the microphone and camera need a secure page, and http://127.0.0.1 is one.
export default defineConfig({
  base: "./",
  build: {
    outDir: "../assets/live",
    emptyOutDir: true,
    assetsDir: "assets",
    sourcemap: false,
    // The microphone worklet must be a real file: data: URLs are refused for audio worklets.
    assetsInlineLimit: 0,
  },
})
