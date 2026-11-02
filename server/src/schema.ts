import * as z from "zod";

// The shared records. Each kind's `data` is validated here, on the server, for both the app and
// agents. The app mirrors these shapes in PutiaCore (ios/Packages/PutiaKit); keep them in sync.
// Who made a record and when is kept beside its data (createdBy, updatedAt), not in it.

export const KINDS = ["piece", "outfit", "photo", "comment", "reference", "wish", "review"] as const;
export type Kind = (typeof KINDS)[number];
export const isKind = (value: string): value is Kind => (KINDS as readonly string[]).includes(value);

const id = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, "must be a lowercase UUID");
const text = (max: number) => z.string().trim().min(1).max(max);
const note = z.string().trim().max(1000).optional();

/**
 * A tag and who set it. Anything an AI sets is a suggestion until the person confirms it:
 * material and cut in particular can't be established reliably from a photo.
 */
const Attribute = z.object({ value: text(80), state: z.enum(["suggested", "confirmed"]), by: z.string().min(1).max(80) }).strict();

export const ATTRIBUTE_KEYS = ["category", "colour", "material", "cut", "pattern", "season"] as const;
const attrs = z.object(Object.fromEntries(ATTRIBUTE_KEYS.map((key) => [key, Attribute.optional()])) as Record<(typeof ATTRIBUTE_KEYS)[number], z.ZodOptional<typeof Attribute>>).strict();

export const schemas = {
  /** A piece's photos are the photo records it owns; mainPhotoId picks the one it's shown with. */
  piece: z.object({ name: z.string().trim().max(120), attrs, mainPhotoId: id.optional() }).strict(),
  /** `note`: why it should work, and what a collage can't show. */
  outfit: z.object({ title: text(120), stage: z.enum(["proposed", "tried", "favourite"]), pieceIds: z.array(id).min(1).max(12), note }).strict(),
  /** A photo of a record, or of the person (ownerKind "person", ownerId their account id), for try-ons. */
  photo: z.object({ ownerKind: z.enum(["piece", "outfit", "reference", "person"]), ownerId: id }).strict(),
  comment: z.object({ subjectKind: z.enum(["piece", "outfit", "reference", "wish"]), subjectId: id, text: text(2000) }).strict(),
  /** An inspiration image (its photo) and what the person likes about it. */
  reference: z.object({ title: text(120), note }).strict(),
  /** Something the person might acquire. `note`: the problem it solves in terms of what they own. */
  wish: z.object({ name: text(120), note, link: z.string().url().max(500).optional(), status: z.enum(["considering", "bought", "dismissed"]) }).strict(),
  /** A conclusion about what's missing. "Nothing needed" is as valid as finding gaps. */
  review: z.object({ conclusion: z.enum(["gaps", "try-combinations", "nothing-needed"]), summary: text(1500) }).strict(),
} as const satisfies Record<Kind, z.ZodType>;

export type Data = Record<string, unknown>;

/** The records a record points at, as [kind, id] pairs, so writes can check they exist. */
export function referencedIds(kind: Kind, data: Data): [Kind, string][] {
  // Called after validation, so the shapes are known.
  const d = data as Record<string, any>;
  switch (kind) {
    case "outfit":
      return d.pieceIds.map((pieceId: string) => ["piece", pieceId]);
    case "photo":
      return d.ownerKind === "person" ? [] : [[d.ownerKind, d.ownerId]];
    case "comment":
      return [[d.subjectKind, d.subjectId]];
    default:
      return [];
  }
}

export function validate(kind: Kind, data: unknown): { ok: true; data: Data } | { ok: false; problems: string[] } {
  const result = schemas[kind].safeParse(data);
  if (result.success) return { ok: true, data: result.data as Data };
  return { ok: false, problems: result.error.issues.map((issue) => `${issue.path.join(".") || "(record)"}: ${issue.message}`) };
}
