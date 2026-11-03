-- Accounts are made by signing in with Apple: apple_user is Apple's stable id for the person in
-- this app ("sub"), and apple_refresh_token is kept so deleting the account can revoke the sign-in,
-- as Apple requires. Accounts made before sign-in have neither and keep working.
ALTER TABLE accounts ADD COLUMN apple_user TEXT;
ALTER TABLE accounts ADD COLUMN apple_refresh_token TEXT;
CREATE UNIQUE INDEX accounts_apple_user ON accounts (apple_user);

-- One secret per signed-in phone, stored only as a SHA-256 hash. The account's one secret moves here.
CREATE TABLE sessions (
  secret_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX sessions_account ON sessions (account_id);
INSERT INTO sessions (secret_hash, account_id, created_at) SELECT secret_hash, id, created_at FROM accounts;
ALTER TABLE accounts DROP COLUMN secret_hash;
