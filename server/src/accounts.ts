import type { Env } from "./env";

// Accounts, pairing codes and connected agents. A phone makes up a random account ID and a long
// random secret; the first request claims the account and later ones must carry the same secret.

export const PAIRING_SECONDS = 600;
// No 0/O or 1/I, so codes are easy to read and type.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** True when `secret` owns the account (claiming it if it's new). */
export async function claim(db: D1Database, accountId: string, secret: string): Promise<boolean> {
  const hash = await sha256(secret);
  const owner = () => db.prepare("SELECT secret_hash FROM accounts WHERE id = ?").bind(accountId).first<{ secret_hash: string }>();
  const row = await owner();
  if (row) return row.secret_hash === hash;
  await db
    .prepare("INSERT OR IGNORE INTO accounts (id, secret_hash, agents_key, created_at) VALUES (?, ?, ?, ?)")
    .bind(accountId, hash, crypto.randomUUID(), new Date().toISOString())
    .run();
  return (await owner())?.secret_hash === hash;
}

/**
 * Every agent token carries the key that was current when it connected. Replacing the key cuts off
 * every agent at once. Null for an account that doesn't exist (deleted).
 */
export async function agentsKey(db: D1Database, accountId: string): Promise<string | null> {
  const row = await db.prepare("SELECT agents_key FROM accounts WHERE id = ?").bind(accountId).first<{ agents_key: string }>();
  return row?.agents_key ?? null;
}

export async function disconnectAgents(env: Env, accountId: string): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("UPDATE accounts SET agents_key = ? WHERE id = ?").bind(crypto.randomUUID(), accountId),
    env.DB.prepare("DELETE FROM agents WHERE account_id = ?").bind(accountId),
  ]);
  // Access already ended through the key; this cleans up the OAuth grants.
  let cursor: string | undefined;
  do {
    const page = await env.OAUTH_PROVIDER.listUserGrants(accountId, { cursor });
    for (const grant of page.items) await env.OAUTH_PROVIDER.revokeGrant(grant.id, accountId);
    cursor = page.cursor;
  } while (cursor);
}

export async function newPairingCode(db: D1Database, accountId: string): Promise<{ code: string; expiresInSeconds: number }> {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const code = [...bytes].map((byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
  await db
    .prepare("INSERT INTO pairings (code, account_id, expires_at) VALUES (?, ?, ?)")
    .bind(code, accountId, Date.now() + PAIRING_SECONDS * 1000)
    .run();
  return { code, expiresInSeconds: PAIRING_SECONDS };
}

export type PairingStatus = { status: "waiting" } | { status: "connected"; agent: string } | { status: "expired" };

export async function pairingStatus(db: D1Database, accountId: string, code: string): Promise<PairingStatus> {
  const row = await db
    .prepare("SELECT expires_at, agent FROM pairings WHERE code = ? AND account_id = ?")
    .bind(code.trim().toUpperCase(), accountId)
    .first<{ expires_at: number; agent: string | null }>();
  if (row?.agent) return { status: "connected", agent: row.agent };
  if (!row || row.expires_at <= Date.now()) return { status: "expired" };
  return { status: "waiting" };
}

/** The account a still-valid, unused code belongs to. */
export async function pairingAccount(db: D1Database, code: string): Promise<string | null> {
  const row = await db
    .prepare("SELECT account_id FROM pairings WHERE code = ? AND agent IS NULL AND expires_at > ?")
    .bind(code.trim().toUpperCase(), Date.now())
    .first<{ account_id: string }>();
  return row?.account_id ?? null;
}

/** Uses the code (once) for `agent`. Returns the account, or null if the code is no longer valid. */
export async function redeemPairingCode(db: D1Database, code: string, agent: string): Promise<string | null> {
  const row = await db
    .prepare("UPDATE pairings SET agent = ? WHERE code = ? AND agent IS NULL AND expires_at > ? RETURNING account_id")
    .bind(agent, code.trim().toUpperCase(), Date.now())
    .first<{ account_id: string }>();
  if (!row) return null;
  await db
    .prepare("INSERT INTO agents (account_id, name, connected_at) VALUES (?, ?, ?)")
    .bind(row.account_id, agent, new Date().toISOString())
    .run();
  return row.account_id;
}

export async function listAgents(db: D1Database, accountId: string): Promise<{ name: string; connectedAt: string }[]> {
  const { results } = await db
    .prepare("SELECT name, connected_at AS connectedAt FROM agents WHERE account_id = ? ORDER BY id")
    .bind(accountId)
    .all<{ name: string; connectedAt: string }>();
  return results;
}
