// End-to-end check against a local server (`npm run db:local && npx wrangler dev --port 8787`):
//   node test/e2e.mjs [base URL, default http://localhost:8787]
// The app adds a piece with a photo, an AI pairs and signs in, reads it, suggests tags and proposes
// an outfit; the person tries it and reacts; the AI records a review; changes are undone.
import assert from "node:assert/strict";
import { createHash, randomBytes, randomUUID } from "node:crypto";

const base = process.argv[2] ?? "http://localhost:8787";
const accountId = randomUUID();
const secret = randomBytes(32).toString("hex");
const app = (path, init = {}) =>
  fetch(`${base}/v1/accounts/${accountId}${path}`, { ...init, headers: { Authorization: `Bearer ${secret}`, ...init.headers } });
const put = (path, value) => app(path, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(value) });

// 1. The app claims its account and adds a piece with a photo.
assert.deepEqual(await (await app("/changes?since=0")).json(), { cursor: 0, docs: [] });
const intruder = await fetch(`${base}/v1/accounts/${accountId}/changes`, { headers: { Authorization: `Bearer ${"x".repeat(64)}` } });
assert.equal(intruder.status, 401, "another secret is refused");

const jacketId = randomUUID();
const trousersId = randomUUID();
const photoId = randomUUID();
const piece = (name, photoIds = []) => ({ name, status: "owned", attrs: {}, swatches: [{ hex: "#1f2a44" }], notes: [], photoIds });
assert.equal((await put(`/docs/piece/${jacketId}`, { baseRevision: 0, data: piece("Navy chore jacket") })).status, 200);
assert.equal((await put(`/docs/piece/${trousersId}`, { baseRevision: 0, data: piece("Grey trousers") })).status, 200);
// A 1x1 PNG stands in for the cut-out.
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
const upload = await app(`/photos/${photoId}/thumb`, { method: "PUT", headers: { "Content-Type": "image/png" }, body: png });
assert.equal(upload.status, 204);
assert.equal((await put(`/docs/photo/${photoId}`, { baseRevision: 0, data: { ownerKind: "piece", ownerId: jacketId, role: "flat", hasCutout: true } })).status, 200);
const withPhoto = await put(`/docs/piece/${jacketId}`, { baseRevision: 1, data: { ...piece("Navy chore jacket", [photoId]), heroPhotoId: photoId } });
assert.equal(withPhoto.status, 200, await withPhoto.clone().text());
const stale = await put(`/docs/piece/${jacketId}`, { baseRevision: 1, data: piece("Stale") });
assert.equal(stale.status, 409, "a stale write is a conflict");
assert.equal((await stale.json()).current.revision, 2);

// 2. The app shows a pairing code; an AI registers and signs in with it.
const { code } = await (await app("/pairing", { method: "POST" })).json();
assert.match(code, /^[A-Z2-9]{8}$/);
assert.deepEqual(await (await app(`/pairing/${code}`)).json(), { status: "waiting" });

const redirectUri = "https://agent.example/callback";
const client = await (await fetch(`${base}/oauth/register`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ client_name: "Test Agent", redirect_uris: [redirectUri], token_endpoint_auth_method: "none" }),
})).json();
assert.ok(client.client_id, JSON.stringify(client));
const verifier = randomBytes(32).toString("base64url");
const challenge = createHash("sha256").update(verifier).digest("base64url");
const authorizeURL = `${base}/authorize?` + new URLSearchParams({
  response_type: "code", client_id: client.client_id, redirect_uri: redirectUri, state: "s1",
  code_challenge: challenge, code_challenge_method: "S256", scope: "putia", resource: `${base}/mcp`,
});
const consent = await fetch(authorizeURL);
assert.equal(consent.status, 200, await consent.clone().text());
const html = await consent.text();
assert.match(html, /Connect Test Agent to Putia\?/);
const italian = await (await fetch(authorizeURL, { headers: { "Accept-Language": "it-IT,it;q=0.9,en;q=0.8" } })).text();
assert.match(italian, /Collegare Test Agent a Putia\?/, "the sign-in page follows the browser's language");
const handle = /name="handle" value="([^"]+)"/.exec(html)[1];
const cookie = consent.headers.getSetCookie().map((value) => value.split(";")[0]).join("; ");
const post = (fields) => fetch(`${base}/authorize`, {
  method: "POST", redirect: "manual",
  headers: { "Content-Type": "application/x-www-form-urlencoded", Cookie: cookie, Origin: base },
  body: new URLSearchParams(fields),
});
assert.equal((await post({ handle, code: "WRONGCOD", decision: "approve", retry: authorizeURL })).status, 400, "a wrong code is refused");
const approved = await post({ handle, code: code.toLowerCase(), decision: "approve", retry: authorizeURL });
assert.equal(approved.status, 302, await approved.text());
const callback = new URL(approved.headers.get("Location"));
assert.deepEqual(await (await app(`/pairing/${code}`)).json(), { status: "connected", agent: "Test Agent" });
assert.deepEqual((await (await app("/agents")).json()).map((agent) => agent.name), ["Test Agent"]);

const tokens = await (await fetch(`${base}/oauth/token`, {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({
    grant_type: "authorization_code", code: callback.searchParams.get("code"), redirect_uri: redirectUri,
    client_id: client.client_id, code_verifier: verifier, resource: `${base}/mcp`,
  }),
})).json();
assert.ok(tokens.access_token, JSON.stringify(tokens));

// 3. The AI works on the same records.
let id = 0;
async function rpc(method, params = {}) {
  const response = await fetch(`${base}/mcp`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${tokens.access_token}`, "Content-Type": "application/json",
      Accept: "application/json, text/event-stream", "MCP-Protocol-Version": "2025-06-18",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
  });
  const body = await response.text();
  assert.equal(response.status, 200, body);
  const message = JSON.parse(body.startsWith("{") ? body : /^data: (.*)$/m.exec(body)[1]);
  assert.ok(!message.error, JSON.stringify(message.error));
  return message.result;
}
const call = async (name, args = {}) => (await rpc("tools/call", { name, arguments: args })).content[0];
const json = async (name, args) => JSON.parse((await call(name, args)).text);

const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "e2e", version: "1" } });
assert.match(init.instructions, /wardrobe studio/);
const tools = (await rpc("tools/list")).tools.map((tool) => tool.name).sort();
assert.deepEqual(tools, ["comment", "delete", "get", "get_photo", "guidance", "history", "list", "overview",
  "save_outfit", "save_piece", "save_reference", "save_review", "save_wish", "undo"]);
assert.match((await call("guidance")).text, /Candid Menswear Assessment/);

const overview = await json("overview");
assert.equal(overview.pieces.owned, 2);
assert.equal(overview.piecesNeedingReview.length, 2);
const photo = await call("get_photo", { photo_id: photoId });
assert.equal(photo.type, "image");
assert.equal(photo.mimeType, "image/png");

const jacket = await json("get", { kind: "piece", id: jacketId });
const tagged = await json("save_piece", {
  id: jacketId, revision: jacket.revision, note: "Tags from the photo",
  data: { ...piece("Navy chore jacket", [photoId]), heroPhotoId: photoId, attrs: {
    category: { value: "jacket", state: "suggested", by: "ai" },
    material: { value: "cotton canvas", state: "confirmed", by: "ai" },
  } },
});
assert.equal(tagged.saved.attrs.material.state, "suggested", "AI tags are suggestions");
assert.equal(tagged.saved.attrs.material.by, "agent:Test Agent");

const proposal = await json("save_outfit", {
  note: "Built around the jacket",
  data: {
    title: "Soft workwear", stage: "proposed", photoIds: [], wornOn: [],
    items: [{ pieceId: jacketId, role: "outerwear" }, { pieceId: trousersId, role: "trousers" }],
    intent: "Relaxed and textured, for weekends",
    rationale: { silhouette: "Boxy jacket over a straight leg", texture: "Canvas against flannel" },
    uncertainty: "Drape of the trousers can't be judged from a flat photo.",
  },
});
const outfitId = proposal.saved.id;
const refused = await call("save_outfit", { id: outfitId, revision: 1, data: { ...proposal.saved, stage: "tried", kind: undefined } });
assert.match(refused.text, /error/i, "the AI can't mark an outfit tried");

// 4. The person tries it and reacts; the AI sees that and records a review.
const feed = await (await app("/changes?since=0")).json();
const outfit = feed.docs.find((doc) => doc.id === outfitId);
assert.equal(outfit.createdBy, "agent:Test Agent");
assert.equal((await put(`/docs/outfit/${outfitId}`, { baseRevision: outfit.revision, data: { ...outfit.data, stage: "tried", wornOn: ["2026-11-01"] } })).status, 200);
const reactionId = randomUUID();
assert.equal((await put(`/docs/comment/${reactionId}`, {
  baseRevision: 0, data: { subjectKind: "outfit", subjectId: outfitId, kind: "reaction", feeling: "loved", text: "Comfortable all day.", by: "human" },
})).status, 200);
const seen = await json("get", { kind: "outfit", id: outfitId });
assert.equal(seen.stage, "tried");
assert.equal(seen.comments[0].feeling, "loved");

const review = await json("save_review", { data: { conclusion: "nothing-needed", summary: "The grey trousers already do the job." } });
assert.equal(review.saved.conclusion, "nothing-needed");

// 5. History and undo, from both sides.
const history = await json("history", { limit: 5 });
assert.equal(history[0].op, "create");
assert.equal(history[0].kind, "review");
assert.match((await call("undo", { change: (await (await app("/history")).json()).find((change) => change.kind === "comment").seq })).text, /error/i,
  "the AI can't undo the person's changes");
const tagChange = tagged.change;
const undone = await (await app(`/undo/${tagChange}`, { method: "POST" })).json();
assert.deepEqual(undone.data.attrs, {}, "the person undoes the AI's tags");

// 6. Disconnecting cuts the AI off at once; deleting removes everything.
assert.equal((await app("/agents", { method: "DELETE" })).status, 204);
const revoked = await fetch(`${base}/mcp`, { method: "POST", headers: { Authorization: `Bearer ${tokens.access_token}` } });
assert.equal(revoked.status, 401);
assert.equal((await app("", { method: "DELETE" })).status, 204);
assert.equal((await app(`/photos/${photoId}/thumb`)).status, 404, "photos are deleted with the account");
console.log("e2e OK");
