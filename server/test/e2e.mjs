// End-to-end check against a local server (`npm run db:local && npx cf dev`):
//   node test/e2e.mjs [base URL, default http://localhost:5173]
// The person signs in and adds a piece with a photo, an AI pairs and signs in, reads it, renames and
// tags it, proposes an outfit; the person tries it and comments; the AI suggests something missing,
// with a link and a photo; changes are undone; the account is deleted.
import assert from "node:assert/strict";
import { createHash, randomBytes, randomUUID } from "node:crypto";

const base = process.argv[2] ?? "http://localhost:5173";
// With TEST_SIGN_IN, "test:<anything>" stands in for the code Sign in with Apple gives the app.
const signIn = async (code) => {
  const response = await fetch(`${base}/v1/sign-in`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code }) });
  assert.equal(response.status, 200, await response.clone().text());
  return response.json();
};
const person = `test:${randomUUID()}`;
const { accountId, secret } = await signIn(person);
const app = (path, init = {}) =>
  fetch(`${base}/v1/accounts/${accountId}${path}`, { ...init, headers: { Authorization: `Bearer ${secret}`, ...init.headers } });
const put = (path, value) => app(path, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(value) });
// A photo is saved with its images: the full photo and the thumbnail (the cut-out).
const addPhoto = (photoId, data, image = png, type = "image/png") => {
  const form = new FormData();
  form.set("data", JSON.stringify(data));
  form.set("full", new Blob([image], { type }));
  form.set("thumb", new Blob([image], { type }));
  return app(`/photos/${photoId}`, { method: "PUT", body: form });
};
// A 1x1 PNG stands in for the cut-out.
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");

// 1. The person signs in with Apple and adds a piece with a photo.
assert.deepEqual(await (await app("/changes?since=0")).json(), { cursor: 0, docs: [] });
const intruder = await fetch(`${base}/v1/accounts/${accountId}/changes`, { headers: { Authorization: `Bearer ${"x".repeat(64)}` } });
assert.equal(intruder.status, 401, "another secret is refused");
const madeUp = await fetch(`${base}/v1/accounts/${randomUUID()}/changes`, { headers: { Authorization: `Bearer ${randomBytes(32).toString("hex")}` } });
assert.equal(madeUp.status, 401, "a phone can't make up an account");
const secondPhone = await signIn(person);
assert.equal(secondPhone.accountId, accountId, "signing in again opens the same bench");
assert.notEqual(secondPhone.secret, secret, "with a secret of its own");

const jacketId = randomUUID();
const trousersId = randomUUID();
const photoId = randomUUID();
const piece = (name) => ({ name, attrs: {} });
assert.equal((await put(`/docs/piece/${jacketId}`, { baseRevision: 0, data: piece("Navy chore jacket") })).status, 200);
assert.equal((await put(`/docs/piece/${trousersId}`, { baseRevision: 0, data: piece("Grey trousers") })).status, 200);
const upload = await addPhoto(photoId, { ownerKind: "piece", ownerId: jacketId });
assert.equal(upload.status, 200, await upload.clone().text());
assert.equal((await upload.json()).data.ownerId, jacketId);
const thumb = await app(`/photos/${photoId}/thumb`);
assert.equal(thumb.headers.get("Content-Type"), "image/webp", "the server keeps its own copy of every image");
assert.ok((await thumb.arrayBuffer()).byteLength > 0);
const notAnImage = await addPhoto(randomUUID(), { ownerKind: "piece", ownerId: jacketId }, Buffer.from("not a photo, just a file"), "image/jpeg");
assert.equal(notAnImage.status, 422, "only images are kept");
assert.equal((await put(`/docs/photo/${randomUUID()}`, { baseRevision: 0, data: { ownerKind: "piece", ownerId: jacketId } })).status, 405,
  "a photo record can't be made without its images");
const orphan = await addPhoto(randomUUID(), { ownerKind: "piece", ownerId: randomUUID() });
assert.equal(orphan.status, 422, "a photo must belong to a record that exists");
const withPhoto = await put(`/docs/piece/${jacketId}`, { baseRevision: 1, data: { ...piece("Navy chore jacket"), mainPhotoId: photoId } });
assert.equal(withPhoto.status, 200, await withPhoto.clone().text());
// A photo of the person, for try-ons: it belongs to the account, not to a record.
const personPhotoId = randomUUID();
assert.equal((await addPhoto(personPhotoId, { ownerKind: "person", ownerId: accountId })).status, 200);
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
assert.deepEqual(tools, ["add_photo", "comment", "delete", "get", "get_photo", "guidance", "history", "list", "overview",
  "save_outfit", "save_piece", "save_wish", "undo"]);
assert.match((await call("guidance")).text, /Candid Menswear Assessment/);

const overview = await json("overview");
assert.equal(overview.pieces, 2);
assert.equal(overview.piecesNeedingReview.length, 2);
assert.deepEqual(overview.photosOfUser, [personPhotoId], "the AI finds the person's photos for try-ons");
const photo = await call("get_photo", { photo_id: photoId });
assert.equal(photo.type, "image");
assert.equal(photo.mimeType, "image/webp");

const jacket = await json("get", { kind: "piece", id: jacketId });
const attrs = {
  category: { value: "jacket", state: "suggested", by: "Test Agent" },
  material: { value: "cotton canvas", state: "suggested", by: "Test Agent" },
};
const tagged = await json("save_piece", {
  id: jacketId, revision: jacket.revision, note: "Named and tagged from the label",
  data: { name: "Arpenteur Travail jacket", attrs, mainPhotoId: jacket.mainPhotoId },
});
assert.equal(tagged.saved.name, "Arpenteur Travail jacket", "the AI renames the piece");
assert.deepEqual(tagged.saved.attrs, attrs, "the AI's tags are saved as sent");

// The AI adds a photo of the product it found online (the app icon stands in for a shop's image).
const repoFile = (path) => `https://raw.githubusercontent.com/Maaarcocr/putia-app/main/${path}`;
const productPage = "https://github.com/Maaarcocr/putia-app";
const found = await json("add_photo", {
  owner_kind: "piece", owner_id: jacketId, image_url: repoFile("ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
  note: `Found on ${productPage}: same product code as on the label`,
});
assert.equal(found.saved.by, "agent:Test Agent", JSON.stringify(found));
assert.equal((await call("get_photo", { photo_id: found.saved.id })).mimeType, "image/webp");
assert.deepEqual((await json("get", { kind: "piece", id: jacketId })).photos.map((photo) => photo.id).sort(), [photoId, found.saved.id].sort());
assert.match((await call("add_photo", { owner_kind: "piece", owner_id: jacketId, image_url: repoFile("README.md"), note: productPage })).text,
  /must be a JPEG, PNG or WebP/, "only images are saved");
assert.match((await call("add_photo", {
  owner_kind: "piece", owner_id: jacketId, image_url: `data:image/png;base64,${Buffer.from("plain text").toString("base64")}`, note: productPage,
})).text, /must be a JPEG, PNG or WebP/, "an image is judged by its contents, not its label");

const proposal = await json("save_outfit", {
  note: "Built around the jacket",
  data: {
    title: "Soft workwear", pieceIds: [jacketId, trousersId],
    note: "Relaxed and textured: a boxy jacket over a straight leg, canvas against flannel. Drape can't be judged from flat photos.",
  },
});
const outfitId = proposal.saved.id;
// The AI adds a try-on it made, as a data: URL (the 1x1 PNG stands in for it).
const tryOn = await json("add_photo", {
  owner_kind: "outfit", owner_id: outfitId, image_url: `data:image/png;base64,${png.toString("base64")}`, note: "A try-on I made from your photos",
});
assert.equal(tryOn.saved.ownerKind, "outfit", JSON.stringify(tryOn));
assert.equal((await app(`/photos/${tryOn.saved.id}/full`)).headers.get("Content-Type"), "image/webp");

// 4. The person marks it a favourite and comments; the AI sees that and suggests something missing.
const feed = await (await app("/changes?since=0")).json();
const outfit = feed.docs.find((doc) => doc.id === outfitId);
assert.equal(outfit.createdBy, "agent:Test Agent");
assert.equal(outfit.data.favourite, false);
assert.equal((await put(`/docs/outfit/${outfitId}`, { baseRevision: outfit.revision, data: { ...outfit.data, favourite: true } })).status, 200);
assert.equal((await put(`/docs/comment/${randomUUID()}`, {
  baseRevision: 0, data: { subjectKind: "outfit", subjectId: outfitId, text: "Comfortable all day." },
})).status, 200);
const seen = await json("get", { kind: "outfit", id: outfitId });
assert.equal(seen.favourite, true);
assert.equal((await json("overview", {})).favouriteOutfits, 1);
assert.equal(seen.comments[0].by, "human");

const suggestion = await json("save_wish", {
  data: { name: "Ecru knit polo", note: "A lighter layer under the jacket for spring.", links: [productPage] },
});
assert.deepEqual(suggestion.saved.links, [productPage]);
const productPhoto = await json("add_photo", {
  owner_kind: "wish", owner_id: suggestion.saved.id, image_url: `data:image/png;base64,${png.toString("base64")}`, note: `Found on ${productPage}`,
});
assert.equal(productPhoto.saved.ownerKind, "wish", JSON.stringify(productPhoto));
assert.deepEqual((await json("overview")).missing, [{ id: suggestion.saved.id, name: "Ecru knit polo" }]);

// 5. History and undo, from both sides.
const history = await json("history", { limit: 5 });
assert.deepEqual(history.slice(0, 2).map((change) => change.kind), ["photo", "wish"]);
const commentChange = (await (await app("/history")).json()).find((change) => change.kind === "comment").seq;
await json("undo", { change: commentChange });
assert.deepEqual((await json("get", { kind: "outfit", id: outfitId })).comments, [], "the AI undoes the person's comment");
const undone = await (await app(`/undo/${tagged.change}`, { method: "POST" })).json();
assert.equal(undone.data.name, "Navy chore jacket", "the person undoes the AI's rename");
assert.deepEqual(undone.data.attrs, {});

// 6. Disconnecting cuts the AI off at once; deleting removes everything.
assert.equal((await app("/agents", { method: "DELETE" })).status, 204);
const revoked = await fetch(`${base}/mcp`, { method: "POST", headers: { Authorization: `Bearer ${tokens.access_token}` } });
assert.equal(revoked.status, 401);
assert.equal((await app("", { method: "DELETE" })).status, 204);
assert.equal((await app(`/photos/${photoId}/thumb`)).status, 401, "every sign-in ends with the account");
const fresh = await signIn(person);
assert.notEqual(fresh.accountId, accountId, "signing in again starts an empty bench");
const freshFeed = await (await fetch(`${base}/v1/accounts/${fresh.accountId}/changes?since=0`, { headers: { Authorization: `Bearer ${fresh.secret}` } })).json();
assert.deepEqual(freshFeed, { cursor: 0, docs: [] });
console.log("e2e OK");
