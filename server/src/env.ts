import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export interface Env {
  DB: D1Database;
  PHOTOS: R2Bucket;
  /** Cloudflare Images: every photo is decoded and saved again by the server (photos.ts). */
  IMAGES: ImagesBinding;
  /** OAuth clients, grants and tokens (managed by the OAuth library). */
  OAUTH_KV: KVNamespace;
  /** Injected by OAuthProvider into the default handler. */
  OAUTH_PROVIDER: OAuthHelpers;
  /** Sign in with Apple (apple.ts): the app's bundle ID, the team, and the team's Sign in with Apple key. */
  APPLE_CLIENT_ID: string;
  APPLE_TEAM_ID: string;
  APPLE_KEY_ID: string;
  /** The key's .p8 file contents. */
  APPLE_PRIVATE_KEY: string;
  /**
   * "yes" under `cf dev` only (cloudflare.config.ts): the code "test:<anything>" signs in as that
   * test person without asking Apple. The deployed Worker doesn't have it.
   */
  TEST_SIGN_IN?: string;
}

/** What an agent's access token carries. */
export interface Props extends Record<string, unknown> {
  accountId: string;
  /** The account's agents key when this agent connected; see accounts.ts. */
  agentsKey: string;
  /** The connector's name, as the agent registered it. Changes are attributed to it. */
  agentName: string;
}
