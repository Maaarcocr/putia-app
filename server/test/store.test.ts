import { beforeEach, describe, expect, it } from "vitest";
import { RuleError } from "../src/rules";
import { Conflict, Invalid, Store } from "../src/store";
import { testDatabase } from "./d1";

const ACCOUNT = "00000000-0000-4000-8000-000000000001";
const AI = "agent:Claude";
let store: Store;
let ids = 0;
const newId = () => `00000000-0000-4000-8000-${String(++ids).padStart(12, "0")}`;

const piece = (overrides: Record<string, unknown> = {}) => ({
  name: "Navy chore jacket",
  status: "owned",
  attrs: {},
  swatches: [{ hex: "#1f2a44" }],
  notes: [],
  photoIds: [],
  ...overrides,
});

const outfit = (pieceIds: string[], overrides: Record<string, unknown> = {}) => ({
  title: "Soft workwear",
  stage: "proposed",
  items: pieceIds.map((pieceId) => ({ pieceId, role: "other" })),
  photoIds: [],
  wornOn: [],
  ...overrides,
});

async function create(kind: "piece" | "outfit" | "wish" | "review" | "comment", data: unknown, actor = "human") {
  const id = newId();
  return (await store.write({ kind, id, actor, baseRevision: 0, data })).doc;
}

beforeEach(() => {
  store = new Store(testDatabase(), ACCOUNT);
});

describe("revisions and conflicts", () => {
  it("creates at revision 1 and updates on top of the revision read", async () => {
    const jacket = await create("piece", piece());
    expect(jacket.revision).toBe(1);
    const renamed = await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ name: "Chore jacket" }) });
    expect(renamed.doc.revision).toBe(2);
    expect(renamed.doc.data.name).toBe("Chore jacket");
  });

  it("refuses a write based on a stale revision and returns the current record", async () => {
    const jacket = await create("piece", piece());
    await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ name: "A" }) });
    const stale = store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ name: "B" }) });
    await expect(stale).rejects.toBeInstanceOf(Conflict);
    await stale.catch((error: Conflict) => expect(error.current?.data.name).toBe("A"));
  });

  it("validates shapes and references", async () => {
    await expect(create("piece", { name: "x" })).rejects.toBeInstanceOf(Invalid);
    await expect(create("outfit", outfit([newId()]))).rejects.toThrow(/doesn't exist/);
  });
});

describe("what the AI may do", () => {
  it("saves the AI's tags as suggestions and keeps the person's photos, notes and colours", async () => {
    const jacket = await create("piece", piece());
    const saved = await store.write({
      kind: "piece",
      id: jacket.id,
      actor: AI,
      baseRevision: 1,
      data: piece({ swatches: [], attrs: { material: { value: "cotton canvas", state: "confirmed", by: "x" } } }),
    });
    expect(saved.doc.data.attrs).toEqual({ material: { value: "cotton canvas", state: "suggested", by: AI } });
    expect(saved.doc.data.swatches).toEqual([{ hex: "#1f2a44" }]);
  });

  it("can't change a value the person confirmed", async () => {
    const jacket = await create("piece", piece({ attrs: { material: { value: "wool", state: "confirmed", by: "human" } } }));
    const change = store.write({
      kind: "piece",
      id: jacket.id,
      actor: AI,
      baseRevision: 1,
      data: piece({ attrs: { material: { value: "cotton", state: "suggested", by: AI } } }),
    });
    await expect(change).rejects.toBeInstanceOf(RuleError);
  });

  it("proposes outfits but can't mark them tried", async () => {
    const jacket = await create("piece", piece());
    await expect(create("outfit", outfit([jacket.id], { stage: "tried" }), AI)).rejects.toBeInstanceOf(RuleError);
    const proposal = await create("outfit", outfit([jacket.id]), AI);
    const tried = store.write({ kind: "outfit", id: proposal.id, actor: AI, baseRevision: 1, data: outfit([jacket.id], { stage: "tried" }) });
    await expect(tried).rejects.toBeInstanceOf(RuleError);
    const byPerson = await store.write({ kind: "outfit", id: proposal.id, actor: "human", baseRevision: 1, data: outfit([jacket.id], { stage: "tried" }) });
    expect(byPerson.doc.data.stage).toBe("tried");
  });

  it("records a nothing-needed review and can't mark a wish bought", async () => {
    const review = await create("review", { conclusion: "nothing-needed", summary: "The trousers you own already do this." }, AI);
    expect(review.data.conclusion).toBe("nothing-needed");
    const wish = { name: "Straight grey trousers", status: "bought", priority: "medium", complementsPieceIds: [], alternativesOwnedIds: [], outfitsToTryIds: [] };
    await expect(create("wish", wish, AI)).rejects.toBeInstanceOf(RuleError);
  });

  it("adds a product photo it found online to a piece, but none of the person's own photos", async () => {
    const jacket = await create("piece", piece());
    const photo = { ownerKind: "piece", ownerId: jacket.id, role: "flat", hasCutout: true, source: "https://shop.example/chore-jacket" };
    const found = await store.write({ kind: "photo", id: newId(), actor: AI, baseRevision: 0, data: photo });
    expect(found.doc.data).toEqual({ ...photo, hasCutout: false });
    expect(found.doc.createdBy).toBe(AI);
    await expect(store.write({ kind: "photo", id: found.doc.id, actor: AI, baseRevision: 1, data: photo })).rejects.toBeInstanceOf(RuleError);
    const { source: _, ...ownPhoto } = photo;
    await expect(store.write({ kind: "photo", id: newId(), actor: AI, baseRevision: 0, data: ownPhoto })).rejects.toThrow(/Only the person adds their own photos/);
    await expect(store.write({ kind: "photo", id: newId(), actor: AI, baseRevision: 0, data: { ...photo, role: "worn" } })).rejects.toBeInstanceOf(RuleError);
    // The person can make it the piece's main photo; the AI can't.
    const main = await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ heroPhotoId: found.doc.id }) });
    expect(main.doc.data.heroPhotoId).toBe(found.doc.id);
    const moved = await store.write({ kind: "piece", id: jacket.id, actor: AI, baseRevision: 2, data: piece() });
    expect(moved.doc.data.heroPhotoId).toBe(found.doc.id);
    // While it's the main photo, it can't be deleted or undone away.
    await expect(store.remove("photo", found.doc.id, AI, 1)).rejects.toThrow(/main photo/);
    await expect(store.undo(found.seq, AI)).rejects.toThrow(/main photo/);
  });

  it("deletes only its own records", async () => {
    const jacket = await create("piece", piece());
    await expect(store.remove("piece", jacket.id, AI, 1)).rejects.toBeInstanceOf(RuleError);
    const proposal = await create("outfit", outfit([jacket.id]), AI);
    expect((await store.remove("outfit", proposal.id, AI, 1)).doc.deleted).toBe(true);
  });
});

describe("history and undo", () => {
  it("undoes an update, a create and a delete", async () => {
    const jacket = await create("piece", piece());
    const renamed = await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ name: "Renamed" }) });
    const undone = await store.undo(renamed.seq, "human");
    expect(undone.doc.data.name).toBe("Navy chore jacket");
    expect(undone.doc.revision).toBe(3);

    const proposal = await store.write({ kind: "outfit", id: newId(), actor: AI, baseRevision: 0, data: outfit([jacket.id]) });
    expect((await store.undo(proposal.seq, "human")).doc.deleted).toBe(true);

    const removed = await store.remove("piece", jacket.id, "human", 3);
    const restored = await store.undo(removed.seq, "human");
    expect(restored.doc.deleted).toBe(false);
  });

  it("won't undo a change the record has moved past", async () => {
    const jacket = await create("piece", piece());
    const first = await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ name: "A" }) });
    await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 2, data: piece({ name: "B" }) });
    await expect(store.undo(first.seq, "human")).rejects.toBeInstanceOf(Conflict);
  });

  it("lets the AI undo only AI changes", async () => {
    const jacket = await create("piece", piece());
    const renamed = await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ name: "Mine" }) });
    await expect(store.undo(renamed.seq, AI)).rejects.toBeInstanceOf(RuleError);
  });

  it("feeds the app every record changed since its cursor", async () => {
    const jacket = await create("piece", piece());
    const { cursor } = await store.feed(0);
    expect(cursor).toBe(1);
    expect((await store.feed(cursor)).docs).toEqual([]);
    await create("comment", { subjectKind: "piece", subjectId: jacket.id, kind: "comment", text: "Too warm for June.", by: "x" });
    const next = await store.feed(cursor);
    expect(next.docs.map((doc) => doc.kind)).toEqual(["comment"]);
    expect(next.docs[0].data.by).toBe("human");
  });
});
