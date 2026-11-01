import * as z from "zod";

// The shared records. Each kind's `data` is validated here, on the server, for both the app and
// agents. The app mirrors these shapes in PutiaCore (ios/Packages/PutiaKit); keep them in sync
// and update docs/architecture.md when a shape changes.

export const KINDS = ["piece", "outfit", "photo", "comment", "reference", "wish", "review"] as const;
export type Kind = (typeof KINDS)[number];
export const isKind = (value: string): value is Kind => (KINDS as readonly string[]).includes(value);

const id = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, "must be a lowercase UUID");
const short = (max: number) => z.string().trim().min(1).max(max);
const optionalText = (max: number) => z.string().trim().max(max).optional();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "must be YYYY-MM-DD");

/** Who set a value: "human", "device" (computed on the phone) or "agent:<name>". */
const by = z.string().min(1).max(80);

/**
 * A tag with provenance. Anything an agent sets is a suggestion until the person confirms it:
 * material and cut in particular can't be established reliably from a photo.
 */
export const Attribute = z
  .object({
    value: z.union([short(80), z.array(short(40)).min(1).max(8)]),
    state: z.enum(["suggested", "confirmed"]),
    by,
  })
  .strict();
export type Attribute = z.infer<typeof Attribute>;

export const ATTRIBUTE_KEYS = ["category", "colour", "material", "cut", "pattern", "season"] as const;
const attrs = z.object(Object.fromEntries(ATTRIBUTE_KEYS.map((key) => [key, Attribute.optional()])) as Record<(typeof ATTRIBUTE_KEYS)[number], z.ZodOptional<typeof Attribute>>).strict();

const note = z.object({ id, text: short(1000), by, at: z.string().max(40) }).strict();

const swatch = z.object({ hex: z.string().regex(/^#[0-9a-f]{6}$/), name: optionalText(40) }).strict();

export const PieceData = z
  .object({
    name: z.string().trim().max(120),
    status: z.enum(["owned", "retired"]),
    attrs,
    /** Dominant colours measured on the phone from the cut-out. Not a claim about true colour. */
    swatches: z.array(swatch).max(4),
    notes: z.array(note).max(50),
    photoIds: z.array(id).max(12),
    heroPhotoId: id.optional(),
  })
  .strict();

export const ROLES = ["top", "layer", "outerwear", "trousers", "shoes", "accessory", "other"] as const;
export const OutfitData = z
  .object({
    title: short(120),
    stage: z.enum(["proposed", "tried", "favourite"]),
    items: z.array(z.object({ pieceId: id, role: z.enum(ROLES) }).strict()).min(1).max(12),
    /** The intended effect, in ordinary language. */
    intent: optionalText(500),
    /** A short explanation of why the pieces work together (or what they test). */
    rationale: z.object({ silhouette: optionalText(400), texture: optionalText(400), effect: optionalText(400) }).strict().optional(),
    /** What a collage or photo can't establish (drape, scale, true colour, comfort). */
    uncertainty: optionalText(300),
    occasion: optionalText(120),
    /** A controlled comparison: the outfit this was varied from, and the one thing that changed. */
    parentId: id.optional(),
    changed: optionalText(200),
    /** The inspiration this outfit translates, if any. */
    referenceId: id.optional(),
    photoIds: z.array(id).max(12),
    wornOn: z.array(day).max(60),
  })
  .strict();

export const PhotoData = z
  .object({
    ownerKind: z.enum(["piece", "outfit", "reference"]),
    ownerId: id,
    role: z.enum(["flat", "worn", "mirror", "detail", "inspiration"]),
    hasCutout: z.boolean(),
    width: z.number().int().min(1).max(10000).optional(),
    height: z.number().int().min(1).max(10000).optional(),
    /**
     * Where an AI found this photo of the piece's product online (the shop or brand page). The
     * person's own photos have none. Kept as a field on "flat" photos so older apps still read it.
     */
    source: z.string().url().max(500).optional(),
  })
  .strict();

export const FEELINGS = ["loved", "fine", "meh", "didnt-work"] as const;
export const CommentData = z
  .object({
    subjectKind: z.enum(["piece", "outfit", "reference", "wish"]),
    subjectId: id,
    kind: z.enum(["comment", "reaction", "assessment"]),
    text: short(2000),
    feeling: z.enum(FEELINGS).optional(),
    by,
  })
  .strict();

export const ATTRACTIONS = ["outline", "volume", "pattern", "texture", "colour", "mood"] as const;
export const ReferenceData = z
  .object({
    title: short(120),
    photoIds: z.array(id).max(6),
    /** What draws the person to the image; different attractions need different translations. */
    attraction: z.array(z.enum(ATTRACTIONS)).max(6),
    note: optionalText(1000),
    /** How owned pieces could carry the same relationship. Written by the AI or the person. */
    translation: z.object({ text: short(1000), pieceIds: z.array(id).max(12), outfitIds: z.array(id).max(12) }).strict().optional(),
  })
  .strict();

export const WishData = z
  .object({
    name: short(120),
    description: optionalText(600),
    status: z.enum(["considering", "trying-first", "dismissed", "bought"]),
    priority: z.enum(["low", "medium", "high"]),
    /** The problem it solves, in terms of existing outfits. */
    problem: optionalText(800),
    complementsPieceIds: z.array(id).max(20),
    /** Pieces already owned that might do the same job. */
    alternativesOwnedIds: z.array(id).max(20),
    outfitsToTryIds: z.array(id).max(20),
    link: z.string().url().max(500).optional(),
  })
  .strict();

export const ReviewData = z
  .object({
    conclusion: z.enum(["gaps", "try-combinations", "nothing-needed"]),
    summary: short(1500),
    scope: optionalText(200),
  })
  .strict();

export const schemas = {
  piece: PieceData,
  outfit: OutfitData,
  photo: PhotoData,
  comment: CommentData,
  reference: ReferenceData,
  wish: WishData,
  review: ReviewData,
} as const satisfies Record<Kind, z.ZodType>;

export type Data = Record<string, unknown>;

/** The records a record points at, as [kind, id] pairs, so writes can check they exist. */
export function referencedIds(kind: Kind, data: Data): [Kind, string][] {
  // Called after validation, so the shapes are known.
  const d = data as Record<string, any>;
  const refs = (target: Kind, ids: (string | undefined)[] = []): [Kind, string][] =>
    ids.filter((id): id is string => id !== undefined).map((id) => [target, id]);
  switch (kind) {
    case "piece":
      return [...refs("photo", d.photoIds), ...refs("photo", [d.heroPhotoId])];
    case "outfit":
      return [
        ...refs("piece", d.items.map((item: { pieceId: string }) => item.pieceId)),
        ...refs("photo", d.photoIds),
        ...refs("outfit", [d.parentId]),
        ...refs("reference", [d.referenceId]),
      ];
    case "reference":
      return [...refs("photo", d.photoIds), ...refs("piece", d.translation?.pieceIds), ...refs("outfit", d.translation?.outfitIds)];
    case "wish":
      return [...refs("piece", d.complementsPieceIds), ...refs("piece", d.alternativesOwnedIds), ...refs("outfit", d.outfitsToTryIds)];
    case "photo":
      return refs(d.ownerKind, [d.ownerId]);
    case "comment":
      return refs(d.subjectKind, [d.subjectId]);
    case "review":
      return [];
  }
}

export function validate(kind: Kind, data: unknown): { ok: true; data: Data } | { ok: false; problems: string[] } {
  const result = schemas[kind].safeParse(data);
  if (result.success) return { ok: true, data: result.data as Data };
  return { ok: false, problems: result.error.issues.map((issue) => `${issue.path.join(".") || "(record)"}: ${issue.message}`) };
}
