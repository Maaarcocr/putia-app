import { beforeEach, describe, expect, it } from "vitest";
import { Conflict, Invalid, Store } from "../src/store";
import { testDatabase } from "./d1";

const ACCOUNT = "00000000-0000-4000-8000-000000000001";
const AI = "agent:Claude";
let store: Store;
let ids = 0;
const newId = () => `00000000-0000-4000-8000-${String(++ids).padStart(12, "0")}`;

const piece = (overrides: Record<string, unknown> = {}) => ({ name: "Navy chore jacket", attrs: {}, ...overrides });

const outfit = (pieceIds: string[], overrides: Record<string, unknown> = {}) => ({ title: "Soft workwear", stage: "proposed", pieceIds, ...overrides });

async function create(kind: "piece" | "outfit" | "reference" | "wish" | "review" | "comment", data: unknown, actor = "human") {
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

describe("an AI", () => {
  it("changes the person's records like the person can, attributed to it", async () => {
    const jacket = await create("piece", piece({ name: "Blue jacket", attrs: { material: { value: "wool", state: "confirmed", by: "human" } } }));
    const renamed = await store.write({ kind: "piece", id: jacket.id, actor: AI, baseRevision: 1, data: piece({ name: "Arpenteur Travail jacket" }) });
    expect(renamed.doc.data).toEqual(piece({ name: "Arpenteur Travail jacket" }));

    const look = await create("outfit", outfit([jacket.id]));
    const tried = await store.write({ kind: "outfit", id: look.id, actor: AI, baseRevision: 1, data: outfit([jacket.id], { stage: "tried" }) });
    expect(tried.doc.data.stage).toBe("tried");

    const wish = await create("wish", { name: "Straight grey trousers", status: "considering" });
    const bought = await store.write({ kind: "wish", id: wish.id, actor: AI, baseRevision: 1, data: { name: "Straight grey trousers", status: "bought" } });
    expect(bought.doc.data.status).toBe("bought");

    expect((await store.remove("piece", jacket.id, AI, 2)).doc.deleted).toBe(true);
    const changes = await store.history();
    expect(changes.filter((change) => change.op !== "create").map((change) => change.actor)).toEqual([AI, AI, AI, AI]);
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

  it("lets an AI undo the person's change", async () => {
    const jacket = await create("piece", piece());
    const renamed = await store.write({ kind: "piece", id: jacket.id, actor: "human", baseRevision: 1, data: piece({ name: "Mine" }) });
    const undone = await store.undo(renamed.seq, AI);
    expect(undone.doc.data.name).toBe("Navy chore jacket");
    expect((await store.change(undone.seq))?.actor).toBe(AI);
  });

  it("feeds the app every record changed since its cursor", async () => {
    const jacket = await create("piece", piece());
    const { cursor } = await store.feed(0);
    expect(cursor).toBe(1);
    expect((await store.feed(cursor)).docs).toEqual([]);
    await create("comment", { subjectKind: "piece", subjectId: jacket.id, text: "Too warm for June." });
    const next = await store.feed(cursor);
    expect(next.docs.map((doc) => doc.kind)).toEqual(["comment"]);
    expect(next.docs[0].createdBy).toBe("human");
  });
});
