import { readdirSync, readFileSync } from "node:fs";

// A small stand-in for Cloudflare D1 over Node's built-in SQLite, so the store's real SQL runs in
// unit tests. Only what src/ uses: prepare/bind/first/all/run and batch (in one transaction).

declare const process: { getBuiltinModule(name: string): any };
const { DatabaseSync } = process.getBuiltinModule("node:sqlite");

class Statement {
  constructor(
    private readonly db: any,
    readonly sql: string,
    readonly values: unknown[] = [],
  ) {}

  bind(...values: unknown[]) {
    return new Statement(this.db, this.sql, values);
  }

  async first<T>(): Promise<T | null> {
    return (this.db.prepare(this.sql).get(...this.values) as T | undefined) ?? null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    return { results: this.db.prepare(this.sql).all(...this.values) as T[] };
  }

  async run() {
    return this.exec();
  }

  exec() {
    const result = this.db.prepare(this.sql).run(...this.values);
    return { success: true, meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) } };
  }
}

export function testDatabase(): D1Database {
  const db = new DatabaseSync(":memory:");
  const migrations = new URL("../migrations/", import.meta.url);
  for (const file of readdirSync(migrations).sort()) db.exec(readFileSync(new URL(file, migrations), "utf8"));
  return {
    prepare: (sql: string) => new Statement(db, sql),
    async batch(statements: Statement[]) {
      db.exec("BEGIN");
      try {
        const results = statements.map((statement) => statement.exec());
        db.exec("COMMIT");
        return results;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
  } as unknown as D1Database;
}
