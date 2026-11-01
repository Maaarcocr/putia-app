import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export interface Env {
  DB: D1Database;
  PHOTOS: R2Bucket;
  /** OAuth clients, grants and tokens (managed by the OAuth library). */
  OAUTH_KV: KVNamespace;
  /** Injected by OAuthProvider into the default handler. */
  OAUTH_PROVIDER: OAuthHelpers;
}

/** What an agent's access token carries. */
export interface Props extends Record<string, unknown> {
  accountId: string;
  /** The account's agents key when this agent connected; see accounts.ts. */
  agentsKey: string;
  /** The connector's name, as the agent registered it. Changes are attributed to it. */
  agentName: string;
}
