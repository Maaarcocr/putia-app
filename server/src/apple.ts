import type { Env } from "./env";

// Sign in with Apple, on the server. The app sends the one-time authorization code Apple gave it;
// the server trades it with Apple for the person's id and a refresh token. The code works once and
// only for this app, and the answer comes straight from Apple, so nothing else needs checking
// (OpenID Connect Core 3.1.3.7). The refresh token is kept to revoke the sign-in when the account
// is deleted, as Apple requires.
// https://developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens

const APPLE = "https://appleid.apple.com";

export class SignInFailed extends Error {}

export async function exchangeCode(env: Env, code: string): Promise<{ user: string; refreshToken: string | null }> {
  const response = await fetch(`${APPLE}/auth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env.APPLE_CLIENT_ID, client_secret: await clientSecret(env), code, grant_type: "authorization_code" }),
  });
  if (!response.ok) throw new SignInFailed(`Apple refused the sign-in (${response.status}).`);
  const body = (await response.json()) as { id_token?: string; refresh_token?: string };
  let claims: { iss?: string; aud?: string; sub?: string } = {};
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(body.id_token?.split(".")[1] ?? "")));
  } catch {
    // Checked below.
  }
  if (claims.iss !== APPLE || claims.aud !== env.APPLE_CLIENT_ID || typeof claims.sub !== "string") throw new SignInFailed("Apple's answer wasn't for this app.");
  return { user: claims.sub, refreshToken: body.refresh_token ?? null };
}

/** Ends the sign-in. False when Apple couldn't be reached or refused. */
export async function revoke(env: Env, refreshToken: string): Promise<boolean> {
  try {
    const response = await fetch(`${APPLE}/auth/revoke`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ client_id: env.APPLE_CLIENT_ID, client_secret: await clientSecret(env), token: refreshToken, token_type_hint: "refresh_token" }),
    });
    return response.ok;
  } catch {
    return false;
  }
}

/** A short-lived JWT signed with the Sign in with Apple key (ES256), which Apple takes as the client secret. */
async function clientSecret(env: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: env.APPLE_KEY_ID };
  const claims = { iss: env.APPLE_TEAM_ID, iat: now, exp: now + 300, aud: APPLE, sub: env.APPLE_CLIENT_ID };
  const pem = env.APPLE_PRIVATE_KEY.replace(/-----[A-Z ]+-----|\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", fromBase64Url(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const input = `${toBase64Url(new TextEncoder().encode(JSON.stringify(header)))}.${toBase64Url(new TextEncoder().encode(JSON.stringify(claims)))}`;
  // Web Crypto's ECDSA signature is already the r||s form a JWT uses.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  return `${input}.${toBase64Url(new Uint8Array(signature))}`;
}

function toBase64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Decodes base64 or base64url. */
function fromBase64Url(text: string): Uint8Array {
  return Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), (char) => char.charCodeAt(0));
}
