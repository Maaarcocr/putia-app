import { McpServer, WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/server";
import * as z from "zod";
import { agentsKey } from "./accounts";
import { photoKey } from "./app-api";
import type { Env, Props } from "./env";
import { describeError } from "./errors";
import { STYLING_GUIDANCE } from "./guidance";
import { type Kind, KINDS, schemas } from "./schema";
import { type Doc, Store } from "./store";

// The tools an AI sees. It works on the same records as the app: everything it saves is
// attributed to it, kept in the history and can be undone.

const INSTRUCTIONS = `Putia is the user's wardrobe studio. You and the user work on the same saved records: the pieces they own, outfits (proposed → tried → favourite), inspiration images, a shortlist of possible additions, and reviews. Start with "overview". Everything you save is attributed to you, kept in history, and can be undone.
- Look at the photos ("get_photo") before judging a piece or outfit. A photo can't establish material, true colour, size or comfort: tags you set on pieces are saved as suggestions for the user to confirm.
- Propose outfits only from owned pieces, with the intended effect, silhouette and texture, and what a collage can't show. Only the user marks an outfit tried or favourite; their reactions and worn photos tell you what works.
- Before suggesting a purchase, look for combinations of what they own. "Nothing needed" and "try a different combination" are valid conclusions: record them with "save_review". A shortlist entry names the problem it solves, the pieces it complements and the owned alternatives.
- Judge whole combinations, name the smallest sufficient change, separate observation from preference. No scores, flattery or universal rules. Call "guidance" for the full assessment approach.
- If a save reports a conflict, the user changed the record meanwhile: read it again and redo your change on top.`;

const text = (value: unknown, isError = false) => ({
  content: [{ type: "text" as const, text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
  isError,
});

/** A record as agents see it: identity, revision (needed to save changes) and data. */
const view = (doc: Doc) => ({ kind: doc.kind, id: doc.id, revision: doc.revision, by: doc.createdBy, updatedAt: doc.updatedAt, ...doc.data });

const SAVE_DESCRIPTIONS: Partial<Record<Kind, string>> = {
  piece:
    'Create or update a piece the user owns. Tags (attrs) are saved as suggestions with state "suggested"; you can\'t change values the user confirmed, nor photos, notes, colours measured on the phone or status. Use it mostly to suggest tags for pieces that need review.',
  outfit:
    'Create or update an outfit from owned pieces. New outfits are "proposed"; only the user changes the stage. Explain the intended effect and the silhouette and texture. For a controlled comparison, set parentId to the outfit you varied and "changed" to the one thing you changed.',
  reference: "Add or update the translation of an inspiration image the user saved: which owned pieces carry the same relationship, and outfits built from them. Only the translation is saved.",
  wish:
    'Add or update a shortlist entry: something the user might acquire. Name the problem it solves in terms of their outfits, the pieces it complements and the owned alternatives. Status is "considering" or "trying-first"; only the user dismisses or marks bought.',
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
    { description: "The full outfit-assessment approach to follow when judging or proposing outfits.", inputSchema: z.object({}), annotations: { readOnlyHint: true } },
    async () => text(STYLING_GUIDANCE),
  );

  server.registerTool(
    "overview",
    {
      description: "Start here: how many pieces, outfits by stage, pieces whose tags need review, the shortlist, and the latest changes (by the user or AI).",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: true },
    },
    async () =>
      attempt(async () => {
        const pieces = await store.list("piece");
        const outfits = await store.list("outfit");
        const needsReview = pieces.filter((piece) =>
          Object.values((piece.data.attrs ?? {}) as Record<string, { state: string }>).some((attr) => attr.state !== "confirmed") ||
          Object.keys((piece.data.attrs ?? {}) as object).length === 0,
        );
        const stages = { proposed: 0, tried: 0, favourite: 0 } as Record<string, number>;
        for (const outfit of outfits) stages[outfit.data.stage as string] += 1;
        const latest = await store.history({ limit: 15 });
        return {
          pieces: { owned: pieces.filter((piece) => piece.data.status === "owned").length, retired: pieces.filter((piece) => piece.data.status === "retired").length },
          piecesNeedingReview: needsReview.map((piece) => ({ id: piece.id, name: piece.data.name || "(unnamed)" })),
          outfits: stages,
          references: (await store.list("reference")).length,
          shortlist: (await store.list("wish")).map((wish) => ({ id: wish.id, name: wish.data.name, status: wish.data.status, priority: wish.data.priority })),
          latestChanges: latest.map((change) => ({ change: change.seq, op: change.op, kind: change.kind, id: change.id, by: change.actor, at: change.at, note: change.note })),
          cursor: await store.cursor(),
        };
      }),
  );

  server.registerTool(
    "list",
    {
      description: "Records of one kind, most recently changed first. Photos are listed by id; view them with get_photo.",
      inputSchema: z.object({
        kind: z.enum(KINDS),
        limit: z.number().int().min(1).max(500).optional().describe("Default 100"),
      }),
      annotations: { readOnlyHint: true },
    },
    async ({ kind, limit }) => attempt(async () => (await store.list(kind)).slice(0, limit ?? 100).map(view)),
  );

  server.registerTool(
    "get",
    {
      description: "One record with its comments and photo ids. For a piece, also the outfits it appears in.",
      inputSchema: z.object({ kind: z.enum(KINDS), id: z.string() }),
      annotations: { readOnlyHint: true },
    },
    async ({ kind, id }) =>
      attempt(async () => {
        const doc = await store.get(kind, id);
        if (!doc || doc.deleted) return `No ${kind} with id ${id}.`;
        const comments = (await store.list("comment")).filter((comment) => comment.data.subjectId === id).map(view);
        const outfits =
          kind === "piece"
            ? (await store.list("outfit"))
                .filter((outfit) => (outfit.data.items as { pieceId: string }[]).some((item) => item.pieceId === id))
                .map((outfit) => ({ id: outfit.id, title: outfit.data.title, stage: outfit.data.stage }))
            : undefined;
        return { ...view(doc), comments, outfits };
      }),
  );

  server.registerTool(
    "get_photo",
    {
      description: 'See a photo. "thumb" is the small cut-out (pieces) or preview; "full" is the original, for detail.',
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

  for (const kind of ["piece", "outfit", "reference", "wish", "review"] as const) {
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
      description: 'Comment on a piece, outfit, inspiration or shortlist entry. Use kind "assessment" for an outfit verdict (verdict first, the main cause, then ranked changes).',
      inputSchema: z.object({
        subject_kind: z.enum(["piece", "outfit", "reference", "wish"]),
        subject_id: z.string(),
        text: z.string().min(1).max(2000),
        kind: z.enum(["comment", "assessment"]).optional(),
      }),
    },
    async ({ subject_kind, subject_id, text: body, kind }) =>
      attempt(async () => {
        const data = { subjectKind: subject_kind, subjectId: subject_id, kind: kind ?? "comment", text: body, by: actor };
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
