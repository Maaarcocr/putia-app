import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

// `cf dev`, `cf build` and `cf deploy` build the Worker with Vite; the Worker itself is in cloudflare.config.ts.
export default defineConfig({
	plugins: [cloudflare()],
});
