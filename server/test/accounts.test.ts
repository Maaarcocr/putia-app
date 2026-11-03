import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { authenticate } from "../src/accounts";
import { handleAppRequest, handleSignIn } from "../src/app-api";
import type { Env } from "../src/env";
import { testDatabase } from "./d1";

// Sign-in and sessions, with a stand-in for Apple's token endpoint.

const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
const idToken = (claims: Record<string, unknown>) => `${encode({ alg: "RS256" })}.${encode(claims)}.signature`;

let env: Env;
let apple: { codes: Record<string, string>; requests: { path: string; form: URLSearchParams }[] };

beforeEach(async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  env = {
    DB: testDatabase(),
    APPLE_CLIENT_ID: "com.example.putia",
    APPLE_TEAM_ID: "TEAM123456",
    APPLE_KEY_ID: "KEY1234567",
    APPLE_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----\n`,
  } as Env;
  apple = { codes: { "code-ada": "apple-user-ada", "code-ada-2": "apple-user-ada", "code-bea": "apple-user-bea" }, requests: [] };
  vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
    const path = new URL(url).pathname;
    const form = new URLSearchParams(String(init.body));
    apple.requests.push({ path, form });
    if (path === "/auth/revoke") return new Response(null, { status: 200 });
    const user = apple.codes[form.get("code") ?? ""];
    if (!user) return Response.json({ error: "invalid_grant" }, { status: 400 });
    delete apple.codes[form.get("code") ?? ""];
    return Response.json({ id_token: idToken({ iss: "https://appleid.apple.com", aud: "com.example.putia", sub: user }), refresh_token: `refresh-${user}` });
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

const signIn = async (code: string) => handleSignIn(new Request("https://api.example/v1/sign-in", { method: "POST", body: JSON.stringify({ code }) }), env);
const app = (session: { accountId: string; secret: string }, method: string, path: string) =>
  handleAppRequest(new Request(`https://api.example/v1/accounts/${session.accountId}${path}`, { method, headers: { Authorization: `Bearer ${session.secret}` } }), env);

describe("sign in with Apple", () => {
  it("makes an account on the first sign-in, and gives each sign-in its own secret", async () => {
    const first = await (await signIn("code-ada")).json();
    const again = await (await signIn("code-ada-2")).json();
    const other = await (await signIn("code-bea")).json();
    expect(again.accountId).toBe(first.accountId);
    expect(again.secret).not.toBe(first.secret);
    expect(other.accountId).not.toBe(first.accountId);
    expect(await authenticate(env.DB, first.accountId, first.secret)).toBe(true);
    expect(await authenticate(env.DB, first.accountId, again.secret)).toBe(true);
    expect(await authenticate(env.DB, first.accountId, other.secret)).toBe(false);

    // The client secret Apple gets is a JWT signed with the team's key.
    const [header, claims] = apple.requests[0].form.get("client_secret")!.split(".").slice(0, 2).map((part) => JSON.parse(Buffer.from(part, "base64url").toString()));
    expect(header).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(claims).toMatchObject({ iss: "TEAM123456", sub: "com.example.putia", aud: "https://appleid.apple.com" });
  });

  it("refuses a code Apple doesn't accept, and an answer meant for another app", async () => {
    expect((await signIn("made-up")).status).toBe(401);
    expect((await signIn("code-ada")).status).toBe(200);
    expect((await signIn("code-ada")).status).toBe(401);
    env.APPLE_CLIENT_ID = "com.example.other";
    expect((await signIn("code-bea")).status).toBe(401);
  });

  it("only accepts test codes where TEST_SIGN_IN is set", async () => {
    expect((await signIn("test:someone")).status).toBe(401);
    env.TEST_SIGN_IN = "yes";
    const session = await (await signIn("test:someone")).json();
    expect(await authenticate(env.DB, session.accountId, session.secret)).toBe(true);
  });

  it("refuses requests without a session: an account can't be made up by the phone", async () => {
    const madeUp = { accountId: crypto.randomUUID(), secret: "a".repeat(64) };
    expect((await app(madeUp, "GET", "/changes")).status).toBe(401);
  });

  it("revokes the sign-in with Apple and ends every session when the account is deleted", async () => {
    const session = await (await signIn("code-ada")).json();
    env.PHOTOS = { list: async () => ({ objects: [], truncated: false }) } as unknown as R2Bucket;
    env.OAUTH_PROVIDER = { listUserGrants: async () => ({ items: [] }) } as unknown as Env["OAUTH_PROVIDER"];
    expect((await app(session, "DELETE", "")).status).toBe(204);
    const revoked = apple.requests.find((request) => request.path === "/auth/revoke");
    expect(revoked?.form.get("token")).toBe("refresh-apple-user-ada");
    expect((await app(session, "GET", "/changes")).status).toBe(401);
  });
});
