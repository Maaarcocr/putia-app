import { type Data, isKind, type Kind, LIMITS, referencedIds, validate } from "./schema";

// The shared records for one account. Every write is checked (shape and references), compared
// against the revision the writer saw, and recorded in the change log in one transaction.

/** Who made a change: "human" (the app) or "agent:<connector name>". */
export type Actor = string;

export interface State {
  deleted: boolean;
  data: Data;
}

export interface Doc extends State {
  kind: Kind;
  id: string;
  revision: number;
  createdBy: Actor;
  createdAt: string;
  updatedAt: string;
}

export interface Change {
  seq: number;
  kind: Kind;
  id: string;
  /** The record's revision after this change. */
  revision: number;
  op: "create" | "update" | "delete" | "undo";
  actor: Actor;
  before: State | null;
  after: State;
  note: string | null;
  /** For an undo: the change it reverted. */
  undoes: number | null;
  at: string;
}

/** The record changed since the writer read it. `current` is what to rebase on (null: it doesn't exist). */
export class Conflict extends Error {
  constructor(
    readonly current: Doc | null,
    message = "The record changed since you read it. Read it again and redo the change on top of the current version.",
  ) {
    super(message);
  }
}

/** The write doesn't pass validation. */
export class Invalid extends Error {
  constructor(readonly problems: string[]) {
    super(problems.join("; "));
  }
}

export class NotFound extends Error {}

interface DocRow {
  kind: string;
  id: string;
  revision: number;
  data: string;
  deleted: number;
  created_by: string;
  created_at: string;
  updated_at: string;
}

interface ChangeRow {
  seq: number;
  kind: string;
  id: string;
  revision: number;
  op: string;
  actor: string;
  before_json: string | null;
  after_json: string;
  note: string | null;
  undoes: number | null;
  at: string;
}

const toDoc = (row: DocRow): Doc => ({
  kind: row.kind as Kind,
  id: row.id,
  revision: row.revision,
  deleted: row.deleted === 1,
  data: JSON.parse(row.data) as Data,
  createdBy: row.created_by,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const toChange = (row: ChangeRow): Change => ({
  seq: row.seq,
  kind: row.kind as Kind,
  id: row.id,
  revision: row.revision,
  op: row.op as Change["op"],
  actor: row.actor,
  before: row.before_json ? (JSON.parse(row.before_json) as State) : null,
  after: JSON.parse(row.after_json) as State,
  note: row.note,
  undoes: row.undoes,
  at: row.at,
});

export interface WriteInput {
  kind: Kind;
  id: string;
  actor: Actor;
  /** The revision the writer read; 0 to create. */
  baseRevision: number;
  /** The full data for the record. */
  data: unknown;
  note?: string;
}

export class Store {
  constructor(
    private readonly db: D1Database,
    readonly accountId: string,
    private readonly now: () => Date = () => new Date(),
    private readonly limits: Record<Kind, number> = LIMITS,
  ) {}

  async get(kind: Kind, id: string): Promise<Doc | null> {
    const row = await this.db
      .prepare("SELECT * FROM docs WHERE account_id = ? AND kind = ? AND id = ?")
      .bind(this.accountId, kind, id)
      .first<DocRow>();
    return row ? toDoc(row) : null;
  }

  /** Records of a kind, newest change first. Deleted ones are left out unless asked for. */
  async list(kind: Kind, options: { includeDeleted?: boolean } = {}): Promise<Doc[]> {
    const { results } = await this.db
      .prepare(`SELECT * FROM docs WHERE account_id = ? AND kind = ? ${options.includeDeleted ? "" : "AND deleted = 0"} ORDER BY updated_at DESC, id`)
      .bind(this.accountId, kind)
      .all<DocRow>();
    return results.map(toDoc);
  }

  async write(input: WriteInput): Promise<{ doc: Doc; seq: number }> {
    const current = await this.get(input.kind, input.id);
    if (input.baseRevision !== (current?.revision ?? 0)) throw new Conflict(current);
    if (current?.deleted) throw new Invalid(["This record was deleted. Undo the delete to bring it back."]);

    const checked = validate(input.kind, input.data);
    if (!checked.ok) throw new Invalid(checked.problems);
    await this.checkReferences(input.kind, checked.data);

    const before: State | null = current ? { deleted: false, data: current.data } : null;
    const after: State = { deleted: false, data: checked.data };
    return this.commit({
      kind: input.kind,
      id: input.id,
      actor: input.actor,
      base: input.baseRevision,
      op: current ? "update" : "create",
      before,
      after,
      note: input.note ?? null,
      undoes: null,
      createdBy: current?.createdBy ?? input.actor,
      createdAt: current?.createdAt,
    });
  }

  /** Deletes keep the record and its history; Undo brings it back. */
  async remove(kind: Kind, id: string, actor: Actor, baseRevision: number, note?: string): Promise<{ doc: Doc; seq: number }> {
    const current = await this.get(kind, id);
    if (!current || current.deleted) throw new NotFound(`No ${kind} with id ${id}.`);
    if (baseRevision !== current.revision) throw new Conflict(current);
    return this.commit({
      kind,
      id,
      actor,
      base: baseRevision,
      op: "delete",
      before: { deleted: false, data: current.data },
      after: { deleted: true, data: current.data },
      note: note ?? null,
      undoes: null,
      createdBy: current.createdBy,
      createdAt: current.createdAt,
    });
  }

  /** Reverts one change, if the record hasn't changed since. */
  async undo(seq: number, actor: Actor): Promise<{ doc: Doc; seq: number }> {
    const change = await this.change(seq);
    if (!change) throw new NotFound(`No change #${seq}.`);
    const current = await this.get(change.kind, change.id);
    if (!current || current.revision !== change.revision) {
      throw new Conflict(current, `Change #${seq} can't be undone: the record changed after it.`);
    }
    // Undoing a create hides the record; undoing anything else restores the earlier state.
    const target: State = change.before ?? { deleted: true, data: change.after.data };
    return this.commit({
      kind: change.kind,
      id: change.id,
      actor,
      base: current.revision,
      op: "undo",
      before: { deleted: current.deleted, data: current.data },
      after: target,
      note: `Undid change #${seq}`,
      undoes: seq,
      createdBy: current.createdBy,
      createdAt: current.createdAt,
    });
  }

  async change(seq: number): Promise<Change | null> {
    const row = await this.db
      .prepare("SELECT * FROM changes WHERE account_id = ? AND seq = ?")
      .bind(this.accountId, seq)
      .first<ChangeRow>();
    return row ? toChange(row) : null;
  }

  /** Newest first. `before` pages backwards; `kind` and `id` narrow to one record. */
  async history(options: { kind?: Kind; id?: string; before?: number; limit?: number } = {}): Promise<Change[]> {
    const clauses = ["account_id = ?"];
    const values: (string | number)[] = [this.accountId];
    if (options.kind) (clauses.push("kind = ?"), values.push(options.kind));
    if (options.id) (clauses.push("id = ?"), values.push(options.id));
    if (options.before) (clauses.push("seq < ?"), values.push(options.before));
    values.push(Math.min(options.limit ?? 50, 200));
    const { results } = await this.db
      .prepare(`SELECT * FROM changes WHERE ${clauses.join(" AND ")} ORDER BY seq DESC LIMIT ?`)
      .bind(...values)
      .all<ChangeRow>();
    return results.map(toChange);
  }

  /** The latest change number, 0 when there are none. */
  async cursor(): Promise<number> {
    const row = await this.db
      .prepare("SELECT COALESCE(MAX(seq), 0) AS cursor FROM changes WHERE account_id = ?")
      .bind(this.accountId)
      .first<{ cursor: number }>();
    return row?.cursor ?? 0;
  }

  /** Every record touched after `since`, in its current state (deleted ones included). */
  async feed(since: number): Promise<{ cursor: number; docs: Doc[] }> {
    const cursor = await this.cursor();
    if (cursor === since) return { cursor, docs: [] };
    const { results } = await this.db
      .prepare(
        `SELECT * FROM docs WHERE account_id = ? AND (kind, id) IN
           (SELECT kind, id FROM changes WHERE account_id = ? AND seq > ? AND seq <= ?)
         ORDER BY updated_at, id`,
      )
      .bind(this.accountId, this.accountId, since, cursor)
      .all<DocRow>();
    return { cursor, docs: results.map(toDoc) };
  }

  async wipe(): Promise<void> {
    await this.db.batch(
      ["docs", "changes", "agents", "pairings"].map((table) => this.db.prepare(`DELETE FROM ${table} WHERE account_id = ?`).bind(this.accountId)),
    );
  }

  /** The records this one points at must exist: all looked up in one query. */
  private async checkReferences(kind: Kind, data: Data): Promise<void> {
    const references = referencedIds(kind, data);
    if (references.length === 0) return;
    const { results } = await this.db
      .prepare(`SELECT kind, id FROM docs WHERE account_id = ? AND deleted = 0 AND (kind, id) IN (VALUES ${references.map(() => "(?, ?)").join(", ")})`)
      .bind(this.accountId, ...references.flat())
      .all<{ kind: string; id: string }>();
    const found = new Set(results.map((row) => `${row.kind} ${row.id}`));
    const missing = references
      .filter(([target, targetId]) => !found.has(`${target} ${targetId}`))
      .map(([target, targetId]) => `${target} ${targetId} doesn't exist`);
    if (missing.length > 0) throw new Invalid(missing);
  }

  private async commit(args: {
    kind: Kind;
    id: string;
    actor: Actor;
    base: number;
    op: Change["op"];
    before: State | null;
    after: State;
    note: string | null;
    undoes: number | null;
    createdBy: Actor;
    createdAt?: string;
  }): Promise<{ doc: Doc; seq: number }> {
    const at = this.now().toISOString();
    const { kind, id, base } = args;
    // Both statements are guarded by the revision the writer saw, so a write that raced another one
    // changes nothing and is reported as a conflict. A new record (base 0) also needs room under its
    // kind's limit, checked in the same transaction so racing writes can't pass it together.
    const room = "(? > 0 OR (SELECT COUNT(*) FROM docs WHERE account_id = ? AND kind = ?) < ?)";
    const roomValues = [base, this.accountId, kind, this.limits[kind]];
    const results = await this.db.batch([
      this.db
        .prepare(
          `INSERT INTO changes (account_id, kind, id, revision, op, actor, before_json, after_json, note, undoes, at)
           SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
           WHERE COALESCE((SELECT revision FROM docs WHERE account_id = ? AND kind = ? AND id = ?), 0) = ? AND ${room}`,
        )
        .bind(
          this.accountId, kind, id, base + 1, args.op, args.actor,
          args.before ? JSON.stringify(args.before) : null, JSON.stringify(args.after), args.note, args.undoes, at,
          this.accountId, kind, id, base, ...roomValues,
        ),
      this.db
        .prepare(
          `INSERT INTO docs (account_id, kind, id, revision, data, deleted, created_by, created_at, updated_at)
           SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?
           WHERE ${room}
           ON CONFLICT (account_id, kind, id) DO UPDATE SET
             revision = excluded.revision, data = excluded.data, deleted = excluded.deleted, updated_at = excluded.updated_at
           WHERE docs.revision = ?`,
        )
        .bind(
          this.accountId, kind, id, base + 1, JSON.stringify(args.after.data), args.after.deleted ? 1 : 0,
          args.createdBy, args.createdAt ?? at, at,
          ...roomValues, base,
        ),
    ]);
    if (results[0].meta.changes !== 1) {
      const current = await this.get(kind, id);
      if (base === 0 && !current) {
        throw new Invalid([`This account holds the most ${kind} records it can (${this.limits[kind]}, deleted ones included).`]);
      }
      throw new Conflict(current);
    }
    // The record as just written, without reading it back.
    const doc: Doc = { kind, id, revision: base + 1, ...args.after, createdBy: args.createdBy, createdAt: args.createdAt ?? at, updatedAt: at };
    return { doc, seq: results[0].meta.last_row_id };
  }
}

export { isKind };
