-- One row per phone. The app's random secret is stored only as a SHA-256 hash.
-- agents_key is copied into every agent token; replacing it cuts off all agents at once.
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  agents_key TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- Codes the app shows so an AI can connect. Single use; "agent" is set when one signs in.
CREATE TABLE pairings (
  code TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  agent TEXT
);

CREATE TABLE agents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id TEXT NOT NULL,
  name TEXT NOT NULL,
  connected_at TEXT NOT NULL
);
CREATE INDEX agents_account ON agents (account_id);

-- The shared records: pieces, outfits, photos, comments, references, wishes and reviews.
-- "data" is JSON validated per kind (src/schema.ts). Deleting keeps the row (deleted = 1).
CREATE TABLE docs (
  account_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  id TEXT NOT NULL,
  revision INTEGER NOT NULL,
  data TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (account_id, kind, id)
);

-- Every change to every record: who, when, why, and the state before and after.
-- This is the history, the undo source and the feed the app syncs from.
CREATE TABLE changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  id TEXT NOT NULL,
  revision INTEGER NOT NULL,
  op TEXT NOT NULL,
  actor TEXT NOT NULL,
  before_json TEXT,
  after_json TEXT,
  note TEXT,
  undoes INTEGER,
  at TEXT NOT NULL
);
CREATE INDEX changes_account_seq ON changes (account_id, seq);
CREATE INDEX changes_doc ON changes (account_id, kind, id, seq);
