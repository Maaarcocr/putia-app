import { appleRefreshToken, authenticate, disconnectAgents, listAgents, newPairingCode, pairingStatus, removeAccount, signIn } from "./accounts";
import { exchangeCode, revoke, SignInFailed } from "./apple";
import type { Env } from "./env";
import { describeError } from "./errors";
import { addPhoto, MAX_IMAGE_BYTES, photoKey } from "./photos";
import { isKind } from "./schema";
import { Store } from "./store";

// The Putia app's API.
//
//   POST   /v1/sign-in                             { code } from Sign in with Apple → { accountId, secret }
//
// Every other request carries `Authorization: Bearer <secret>`:
//
//   GET    /v1/accounts/:id/changes?since=N        records changed after change N, and the new cursor
//   PUT    /v1/accounts/:id/docs/:kind/:doc        { baseRevision, data, note? } → the saved record (not photos)
//   DELETE /v1/accounts/:id/docs/:kind/:doc?base=N delete (undoable)
//   GET    /v1/accounts/:id/history?before=N       the change log, newest first
//   POST   /v1/accounts/:id/undo/:seq              revert one change
//   PUT    /v1/accounts/:id/photos/:photo          multipart: data (the record's JSON), note?, full and thumb images → the saved record
//   GET    /v1/accounts/:id/photos/:photo/:size    size is "thumb" or "full"
//   POST   /v1/accounts/:id/pairing                a one-time code for connecting an AI
//   GET    /v1/accounts/:id/pairing/:code          waiting, connected (with the agent's name) or expired
//   GET    /v1/accounts/:id/agents                 connected AIs
//   DELETE /v1/accounts/:id/agents                 disconnect them all
//   DELETE /v1/accounts/:id                        delete the account and everything in it

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// Two images and the record's few fields.
const MAX_PHOTO_UPLOAD_BYTES = 2 * MAX_IMAGE_BYTES + 100_000;

const json = (value: unknown, status = 200) => Response.json(value, { status });
const error = (status: number, message: string) => json({ error: message }, status);

export async function handleSignIn(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return error(405, "use POST");
  const body = (await request.json().catch(() => ({}))) as { code?: unknown };
  if (typeof body.code !== "string" || body.code.length === 0 || body.code.length > 1000) return error(400, "missing code");
  try {
    const apple = env.TEST_SIGN_IN === "yes" && body.code.startsWith("test:")
      ? { user: body.code, refreshToken: null }
      : await exchangeCode(env, body.code);
    return json(await signIn(env.DB, apple.user, apple.refreshToken));
  } catch (caught) {
    if (caught instanceof SignInFailed) return error(401, caught.message);
    throw caught;
  }
}

export async function handleAppRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  // ["v1", "accounts", id, ...rest]
  const [, , accountId = "", ...rest] = url.pathname.split("/").filter(Boolean);
  if (!UUID.test(accountId)) return error(404, "not found");

  const secret = request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  if (!secret || !(await authenticate(env.DB, accountId, secret))) return error(401, "sign in again");

  const store = new Store(env.DB, accountId);
  const route = `${request.method} ${rest[0] ?? ""}`;
  try {
    switch (route) {
      case "GET changes": {
        const since = Number(url.searchParams.get("since") ?? "0");
        return json(await store.feed(Number.isInteger(since) && since >= 0 ? since : 0));
      }
      case "PUT docs": {
        const [, kind = "", id = ""] = rest;
        if (!isKind(kind) || !UUID.test(id)) return error(404, "not found");
        if (kind === "photo") return error(405, "add photos with their images: PUT photos/:photo");
        const body = (await request.json()) as { baseRevision?: number; data?: unknown; note?: string };
        const saved = await store.write({ kind, id, actor: "human", baseRevision: body.baseRevision ?? 0, data: body.data, note: body.note });
        return json(saved.doc);
      }
      case "DELETE docs": {
        const [, kind = "", id = ""] = rest;
        if (!isKind(kind) || !UUID.test(id)) return error(404, "not found");
        const removed = await store.remove(kind, id, "human", Number(url.searchParams.get("base") ?? "0"));
        return json(removed.doc);
      }
      case "GET history": {
        const before = Number(url.searchParams.get("before") ?? "0") || undefined;
        return json(await store.history({ before, limit: 100 }));
      }
      case "POST undo": {
        const undone = await store.undo(Number(rest[1]), "human");
        return json(undone.doc);
      }
      case "PUT photos": {
        const [, photoId = ""] = rest;
        if (!UUID.test(photoId)) return error(404, "not found");
        const length = Number(request.headers.get("Content-Length") ?? "");
        if (!length) return error(411, "Content-Length is required");
        if (length > MAX_PHOTO_UPLOAD_BYTES) return error(413, "photo too large");
        const form = await request.formData();
        const full = form.get("full");
        const thumb = form.get("thumb");
        const note = form.get("note");
        if (!(full instanceof File) || !(thumb instanceof File)) return error(400, "a photo needs its full and thumb images");
        const saved = await addPhoto(env, store, {
          id: photoId,
          actor: "human",
          data: JSON.parse(String(form.get("data") ?? "null")),
          note: typeof note === "string" ? note : undefined,
          full: await full.arrayBuffer(),
          thumb: await thumb.arrayBuffer(),
        });
        return json(saved.doc);
      }
      case "GET photos": {
        const [, photoId = "", size = ""] = rest;
        if (!UUID.test(photoId) || (size !== "thumb" && size !== "full")) return error(404, "not found");
        const object = await env.PHOTOS.get(photoKey(accountId, photoId, size));
        if (!object) return error(404, "not found");
        return new Response(object.body, { headers: { "Content-Type": object.httpMetadata?.contentType ?? "image/jpeg" } });
      }
      case "POST pairing":
        return json(await newPairingCode(env.DB, accountId));
      case "GET pairing":
        return json(await pairingStatus(env.DB, accountId, rest[1] ?? ""));
      case "GET agents":
        return json(await listAgents(env.DB, accountId));
      case "DELETE agents":
        await disconnectAgents(env, accountId);
        return new Response(null, { status: 204 });
      case "DELETE ": {
        // Apple requires ending the sign-in when the account is deleted.
        const refreshToken = await appleRefreshToken(env.DB, accountId);
        if (refreshToken && !(await revoke(env, refreshToken))) console.error(`Apple didn't revoke the sign-in for ${accountId}`);
        await disconnectAgents(env, accountId);
        await store.wipe();
        await removeAccount(env.DB, accountId);
        let cursor: string | undefined;
        do {
          const listing = await env.PHOTOS.list({ prefix: `${accountId}/`, cursor });
          if (listing.objects.length > 0) await env.PHOTOS.delete(listing.objects.map((object) => object.key));
          cursor = listing.truncated ? listing.cursor : undefined;
        } while (cursor);
        return new Response(null, { status: 204 });
      }
      default:
        return error(404, "not found");
    }
  } catch (caught) {
    if (caught instanceof SyntaxError) return error(400, "not valid JSON");
    const { status, body } = describeError(caught);
    return json(body, status);
  }
}
