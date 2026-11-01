import { McpServer, WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/server";
import * as z from "zod";
import { agentsKey } from "./accounts";
import { photoKey } from "./app-api";
import type { Env, Props } from "./env";
import { describeError } from "./errors";
import { STYLING_GUIDANCE } from "./guidance";
import { KINDS, schemas } from "./schema";
import { type Doc, Invalid, NotFound, Store } from "./store";

// The tools an AI sees. It works on the same records as the app: everything it saves is
// attributed to it, kept in the history and can be undone.

const INSTRUCTIONS = `Putia is the user's wardrobe studio. You and the user work on the same saved records: the pieces they own, outfits (proposed → tried → favourite), inspiration images, a shortlist of possible additions, and reviews. Start with "overview". Before your first assessment or outfit, read "guidance": the assessment approach to follow here. Everything you save is attributed to you, kept in history, and can be undone.
- Look at the photos ("get_photo") before judging a piece or outfit. A photo can't establish material, true colour, size or comfort: tags you set on pieces are saved as suggestions for the user to confirm.
- Get to know each piece. When a label, tag, barcode or product code is visible, or a comment names the brand and model, search the web for that exact product if you can. Add its clearest photo with "add_photo" (the piece alone on a plain or transparent background: no model, no other items), suggest tags from the listing, and comment on the piece with what you found and the link. Only when you're sure it's the same product: a listing shows the product as sold, not this piece's true colour, wear or alterations.
- When you can't tell exactly what a piece is, ask the user for a photo of its label, care tag or barcode, or the brand and product name or code: in your conversation, or as a comment on the piece (they can add the photo to the piece, or answer with a comment). Ask about the pieces that matter most first, a few at a time.
- Propose outfits only from owned pieces, with a note on the intended effect, silhouette and texture, and what a collage can't show. Only the user marks an outfit tried or favourite; their comments and photos tell you what works.
- Before suggesting a purchase, look for combinations of what they own. "Nothing needed" and "try a different combination" are valid conclusions: record them with "save_review". A shortlist entry's note names the problem it solves and the pieces it goes with.
- Judge whole combinations, name the smallest sufficient change, separate observation from preference. No scores, flattery or universal rules.
- If a save reports a conflict, the user changed the record meanwhile: read it again and redo your change on top.`;

const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_IMAGE_BYTES = 8_000_000;

/** Downloads an image an AI found online. The Worker can reach only public addresses. */
async function download(url: string): Promise<{ bytes: ArrayBuffer; type: string }> {
  if (!url.startsWith("https://")) throw new Invalid(["image_url must be an https address."]);
  const response = await fetch(url, { headers: { "User-Agent": "Putia/1.0 (+https://api.putia.app)" } }).catch(() => null);
  if (!response?.ok) throw new Invalid([`Couldn't download ${url} (${response?.status ?? "no answer"}). Try another image.`]);
  const type = (response.headers.get("Content-Type") ?? "").split(";")[0].trim().toLowerCase();
  if (!IMAGE_TYPES.includes(type)) throw new Invalid([`That address is ${type || "not an image"}: it must be a JPEG, PNG or WebP image.`]);
  const bytes = await response.arrayBuffer();
  if (bytes.byteLength > MAX_IMAGE_BYTES) throw new Invalid(["The image is larger than 8 MB. Choose a smaller one."]);
  return { bytes, type };
}

const text = (value: unknown, isError = false) => ({
  content: [{ type: "text" as const, text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
  isError,
});

/** A record as agents see it: identity, revision (needed to save changes), author and data. */
const view = (doc: Doc) => ({ kind: doc.kind, id: doc.id, revision: doc.revision, by: doc.createdBy, updatedAt: doc.updatedAt, ...doc.data });

const SAVE_DESCRIPTIONS = {
  piece:
    'Create or update a piece the user owns, mostly to suggest tags for pieces that need review. Tags (attrs) are saved as "suggested"; you can\'t change a tag the user confirmed, rename a piece they named, or change its main photo.',
  outfit:
    'Create or update an outfit from owned pieces. New outfits are "proposed"; only the user changes the stage. In the note, explain the intended effect, the silhouette and texture, and what a collage can\'t show.',
  wish: 'Add or update a shortlist entry: something the user might acquire. In the note, name the problem it solves in terms of what they own, and the pieces it goes with. Status stays "considering": only the user marks it bought or dismissed.',
  review: 'Record a conclusion about what\'s missing: "gaps", "try-combinations" or "nothing-needed", with a short summary. All three are valid results.',
};

export async function handleMcp(request: Request, env: Env, props: Props): Promise<Response> {
  // Agents disconnected (or the account deleted) since this token was issued.
  if (!props.agentsKey || props.agentsKey !== (await agentsKey(env.DB, props.accountId))) {
    return new Response("Disconnected from Putia. Connect again with a new pairing code.\n", {
      status: 401,
      headers: { "WWW-Authenticate": 'Bearer error="invalid_token", error_description="disconnected"' },
    });
  }
  const store = new Store(env.DB, props.accountId);
  const actor = `agent:${props.agentName}`;
  // Store errors become a readable answer instead of a failed call.
  const attempt = async (work: () => Promise<unknown>) => {
    try {
      return text(await work());
    } catch (error) {
      return text(describeError(error).body, true);
    }
  };

  const server = new McpServer({ name: "putia", version: "1.0.0" }, { instructions: INSTRUCTIONS });

  server.registerTool(
    "guidance",
    {
      description: "The full outfit-assessment approach to follow when judging pieces or proposing outfits, with its principles and sources. Read it before your first assessment.",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: true },
    },
    async () => text(STYLING_GUIDANCE),
  );

  server.registerTool(
    "overview",
    {
      description: "Start here: how many pieces, pieces whose tags need review, outfits by stage, the shortlist, and the latest changes (by the user or AI).",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: true },
    },
    async () =>
      attempt(async () => {
        const pieces = await store.list("piece");
        const needsReview = pieces.filter((piece) => {
          const tags = Object.values(piece.data.attrs as Record<string, { state: string }>);
          return tags.length === 0 || tags.some((tag) => tag.state === "suggested");
        });
        const stages: Record<string, number> = { proposed: 0, tried: 0, favourite: 0 };
        for (const outfit of await store.list("outfit")) stages[outfit.data.stage as string] += 1;
        return {
          pieces: pieces.length,
          piecesNeedingReview: needsReview.map((piece) => ({ id: piece.id, name: piece.data.name || "(unnamed)" })),
          outfits: stages,
          inspiration: (await store.list("reference")).length,
          shortlist: (await store.list("wish")).map((wish) => ({ id: wish.id, name: wish.data.name, status: wish.data.status })),
          latestChanges: (await store.history({ limit: 15 })).map((change) => ({ change: change.seq, op: change.op, kind: change.kind, id: change.id, by: change.actor, at: change.at, note: change.note })),
        };
      }),
  );

  server.registerTool(
    "list",
    {
      description: "Records of one kind, most recently changed first. View photos with get_photo.",
      inputSchema: z.object({ kind: z.enum(KINDS), limit: z.number().int().min(1).max(500).optional().describe("Default 100") }),
      annotations: { readOnlyHint: true },
    },
    async ({ kind, limit }) => attempt(async () => (await store.list(kind)).slice(0, limit ?? 100).map(view)),
  );

  server.registerTool(
    "get",
    {
      description: "One record with its comments and photos. For a piece, also the outfits it's in.",
      inputSchema: z.object({ kind: z.enum(KINDS), id: z.string() }),
      annotations: { readOnlyHint: true },
    },
    async ({ kind, id }) =>
      attempt(async () => {
        const doc = await store.get(kind, id);
        if (!doc || doc.deleted) throw new NotFound(`No ${kind} with id ${id}.`);
        const comments = (await store.list("comment")).filter((comment) => comment.data.subjectId === id).map(view);
        const photos = (await store.list("photo")).filter((photo) => photo.data.ownerId === id).map(view);
        if (kind !== "piece") return { ...view(doc), comments, photos };
        const outfits = (await store.list("outfit"))
          .filter((outfit) => (outfit.data.pieceIds as string[]).includes(id))
          .map((outfit) => ({ id: outfit.id, title: outfit.data.title, stage: outfit.data.stage }));
        return { ...view(doc), comments, photos, outfits };
      }),
  );

  server.registerTool(
    "get_photo",
    {
      description: 'See a photo. "thumb" is small (a cut-out for a piece\'s first photo); "full" is the original, for detail.',
      inputSchema: z.object({ photo_id: z.string(), size: z.enum(["thumb", "full"]).optional().describe('Default "thumb"') }),
      annotations: { readOnlyHint: true },
    },
    async ({ photo_id, size }) => {
      const object = await env.PHOTOS.get(photoKey(props.accountId, photo_id, size ?? "thumb"));
      if (!object) return text(`No photo ${photo_id} (${size ?? "thumb"}).`, true);
      const bytes = new Uint8Array(await object.arrayBuffer());
      let binary = "";
      for (let index = 0; index < bytes.length; index += 0x8000) binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
      return { content: [{ type: "image" as const, data: btoa(binary), mimeType: object.httpMetadata?.contentType ?? "image/jpeg" }] };
    },
  );

  server.registerTool(
    "add_photo",
    {
      description:
        "Add a photo to a piece: one of its exact product that you found online, from a shop or the brand. Pass the image file's https address. Choose one with the piece alone on a plain or transparent background: no model, no other items. JPEG, PNG or WebP, up to 8 MB. The user's photos stay as they are; they can make yours the piece's main photo, or delete it.",
      inputSchema: z.object({
        piece_id: z.string(),
        image_url: z.string().url().describe("The image file itself (https)"),
        note: z.string().min(1).max(300).describe("The page you found it on, and how you know it's the same product; shown in the user's history"),
      }),
    },
    async ({ piece_id, image_url, note }) =>
      attempt(async () => {
        const piece = await store.get("piece", piece_id);
        if (!piece || piece.deleted) throw new NotFound(`No piece with id ${piece_id}.`);
        const image = await download(image_url);
        const photoId = crypto.randomUUID();
        // The same image serves as the thumbnail.
        const keys = [photoKey(props.accountId, photoId, "full"), photoKey(props.accountId, photoId, "thumb")];
        for (const key of keys) await env.PHOTOS.put(key, image.bytes, { httpMetadata: { contentType: image.type } });
        try {
          const saved = await store.write({ kind: "photo", id: photoId, actor, baseRevision: 0, data: { ownerKind: "piece", ownerId: piece_id }, note });
          return { saved: view(saved.doc), change: saved.seq };
        } catch (error) {
          await env.PHOTOS.delete(keys);
          throw error;
        }
      }),
  );

  for (const kind of ["piece", "outfit", "wish", "review"] as const) {
    server.registerTool(
      `save_${kind}`,
      {
        description: `${SAVE_DESCRIPTIONS[kind]} Leave out id and revision to create; to update, pass the id and the revision you read.`,
        inputSchema: z.object({
          id: z.string().optional().describe("The record to update; leave out to create"),
          revision: z.number().int().min(0).optional().describe("The revision you read; required to update"),
          note: z.string().max(300).optional().describe("Why, in a sentence; shown in the user's history"),
          data: schemas[kind],
        }),
      },
      async ({ id, revision, note, data }) =>
        attempt(async () => {
          const saved = await store.write({ kind, id: id ?? crypto.randomUUID(), actor, baseRevision: id ? (revision ?? -1) : 0, data, note });
          return { saved: view(saved.doc), change: saved.seq };
        }),
    );
  }

  server.registerTool(
    "comment",
    {
      description: "Comment on a piece, outfit, inspiration image or shortlist entry. For an outfit assessment: the verdict first, the main cause, then ranked changes.",
      inputSchema: z.object({ subject_kind: z.enum(["piece", "outfit", "reference", "wish"]), subject_id: z.string(), text: z.string().min(1).max(2000) }),
    },
    async ({ subject_kind, subject_id, text: body }) =>
      attempt(async () => {
        const data = { subjectKind: subject_kind, subjectId: subject_id, text: body };
        const saved = await store.write({ kind: "comment", id: crypto.randomUUID(), actor, baseRevision: 0, data });
        return { saved: view(saved.doc), change: saved.seq };
      }),
  );

  server.registerTool(
    "delete",
    {
      description: "Delete a record you created (for example a proposal that no longer makes sense). It stays in history and can be undone.",
      inputSchema: z.object({ kind: z.enum(KINDS), id: z.string(), revision: z.number().int().min(1), note: z.string().max(300).optional() }),
      annotations: { destructiveHint: true },
    },
    async ({ kind, id, revision, note }) => attempt(async () => ({ deleted: view((await store.remove(kind, id, actor, revision, note)).doc) })),
  );

  server.registerTool(
    "history",
    {
      description: "Changes newest first, by the user and by AI, with what each changed. Narrow to one record with kind and id; page back with before.",
      inputSchema: z.object({
        kind: z.enum(KINDS).optional(),
        id: z.string().optional(),
        before: z.number().int().optional().describe("Only changes older than this change number"),
        limit: z.number().int().min(1).max(100).optional(),
      }),
      annotations: { readOnlyHint: true },
    },
    async (options) => attempt(async () => store.history(options)),
  );

  server.registerTool(
    "undo",
    {
      description: "Undo one change by its number (from history). You can undo changes made by AI; the user can undo anything in the app.",
      inputSchema: z.object({ change: z.number().int().min(1) }),
    },
    async ({ change }) => attempt(async () => ({ restored: view((await store.undo(change, actor)).doc) })),
  );

  const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  await server.connect(transport);
  return transport.handleRequest(request);
}
