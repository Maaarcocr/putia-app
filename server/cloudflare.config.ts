import { bindings, defineConfig } from "cf/config";

// The Putia studio server: the shared records, photos and the AI connector (/mcp).
// Deploy and develop with the `cf` CLI (see docs/architecture.md, "Deploying").
// D1 migrations live in ./migrations, the default for `cf d1 migrations apply`.
export default defineConfig({
	worker: {
		name: "putia",
		compatibilityDate: "2026-10-01",
		// global_fetch_strictly_public: required by the OAuth library for Client ID Metadata Documents.
		compatibilityFlags: ["nodejs_compat", "global_fetch_strictly_public"],
		entrypoint: "src/index.ts",
		observability: { enabled: true },
		env: {
			DB: bindings.d1({ name: "putia", id: "fe7c73d0-0a92-42de-8eec-5e4fbf1af5ab" }),
			OAUTH_KV: bindings.kv({ id: "5d97c6fe2c914ff090e8cc2f6a48a3c6" }),
			PHOTOS: bindings.r2({ name: "putia-photos" }),
		},
	},
});
