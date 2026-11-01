import { claim, disconnectAgents, listAgents, newPairingCode, pairingStatus } from "./accounts";
import type { Env } from "./env";
import { describeError } from "./errors";
import { HUMAN } from "./rules";
import { isKind } from "./schema";
import { Store } from "./store";

// The Putia app's API. Every request carries `Authorization: Bearer <secret>`.
//
//   GET    /v1/accounts/:id/changes?since=N        records changed after change N, and the new cursor
//   PUT    /v1/accounts/:id/docs/:kind/:doc        { baseRevision, data, note? } → the saved record
//   DELETE /v1/accounts/:id/docs/:kind/:doc?base=N delete (undoable)
//   GET    /v1/accounts/:id/history?before=N       the change log, newest first
//   POST   /v1/accounts/:id/undo/:seq              revert one change
//   PUT    /v1/accounts/:id/photos/:photo/:size    image bytes; size is "thumb" or "full"
//   GET    /v1/accounts/:id/photos/:photo/:size
//   POST   /v1/accounts/:id/pairing                a one-time code for connecting an AI
//   GET    /v1/accounts/:id/pairing/:code          waiting, connected (with the agent's name) or expired
//   GET    /v1/accounts/:id/agents                 connected AIs
//   DELETE /v1/accounts/:id/agents                 disconnect them all
//   DELETE /v1/accounts/:id                        delete the account and everything in it

const MAX_PHOTO_BYTES = 8_000_000;
const PHOTO_TYPES = ["image/jpeg", "image/png", "image/heic"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const json = (value: unknown, status = 200) => Response.json(value, { status });
const error = (status: number, message: string) => json({ error: message }, status);

export const photoKey = (accountId: string, photoId: string, size: string) => `${accountId}/${photoId}/${size}`;

export async function handleAppRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  // ["v1", "accounts", id, ...rest]
  const [, , accountId = "", ...rest] = url.pathname.split("/").filter(Boolean);
  if (!UUID.test(accountId)) return error(404, "not found");

  const secret = request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  if (secret.length < 32) return error(401, "missing secret");
  if (!(await claim(env.DB, accountId, secret))) return error(401, "wrong secret");

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
        const body = (await request.json()) as { baseRevision?: number; data?: unknown; note?: string };
        const saved = await store.write({ kind, id, actor: HUMAN, baseRevision: body.baseRevision ?? 0, data: body.data, note: body.note });
        return json(saved.doc);
      }
      case "DELETE docs": {
        const [, kind = "", id = ""] = rest;
        if (!isKind(kind) || !UUID.test(id)) return error(404, "not found");
        const removed = await store.remove(kind, id, HUMAN, Number(url.searchParams.get("base") ?? "0"));
        return json(removed.doc);
      }
      case "GET history": {
        const before = Number(url.searchParams.get("before") ?? "0") || undefined;
        return json(await store.history({ before, limit: 100 }));
      }
      case "POST undo": {
        const undone = await store.undo(Number(rest[1]), HUMAN);
        return json(undone.doc);
      }
      case "PUT photos":
      case "GET photos": {
        const [, photoId = "", size = ""] = rest;
        if (!UUID.test(photoId) || (size !== "thumb" && size !== "full")) return error(404, "not found");
        const key = photoKey(accountId, photoId, size);
        if (request.method === "GET") {
          const object = await env.PHOTOS.get(key);
          if (!object) return error(404, "not found");
          return new Response(object.body, { headers: { "Content-Type": object.httpMetadata?.contentType ?? "image/jpeg" } });
        }
        const type = request.headers.get("Content-Type") ?? "";
        if (!PHOTO_TYPES.includes(type)) return error(415, "photos must be JPEG, PNG or HEIC");
        const bytes = await request.arrayBuffer();
        if (bytes.byteLength > MAX_PHOTO_BYTES) return error(413, "photo too large");
        await env.PHOTOS.put(key, bytes, { httpMetadata: { contentType: type } });
        return new Response(null, { status: 204 });
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
        await disconnectAgents(env, accountId);
        await store.wipe();
        await env.DB.prepare("DELETE FROM accounts WHERE id = ?").bind(accountId).run();
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
    const { status, body } = describeError(caught);
    return json(body, status);
  }
}
