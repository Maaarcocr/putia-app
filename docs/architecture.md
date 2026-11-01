# Architecture

Putia is two parts: an iPhone app and a small server. The server holds the shared records; the app and any AI the person connects both read and write them. There is no AI in either.

```
iPhone app ──HTTPS /v1/accounts/:id/…──▶  Cloudflare Worker  ◀──MCP /mcp (OAuth)── the person's AI
 (SwiftUI)                                 D1: records + change log
                                           R2: photos
                                           KV: OAuth grants
```

## Records

Everything on the bench is a record of one of seven kinds: `piece`, `outfit`, `photo`, `comment`, `reference` (inspiration), `wish` (shortlist entry) and `review` (a conclusion about what's missing). Their shapes are defined once on the server (`server/src/schema.ts`, zod) and mirrored in Swift (`ios/Packages/PutiaKit/Sources/PutiaCore/Records.swift`). Change both together.

The server stores each record as JSON in one generic table, `docs`, with a **revision**. Every write:

1. names the revision it was based on (0 to create). A stale revision is refused with 409 and the current record, so nobody overwrites a change they haven't seen;
2. is validated (shape, and that the records it points at exist);
3. is recorded in `changes` with the state before and after, the author (`human`, or `agent:<name>` for an AI) and an optional note, in the same D1 batch.

The person and an AI can change the same things: the server doesn't check who wrote what.

`changes` is at once the history, the source for undo (put back the `before` state, if the record hasn't changed since) and the app's sync feed (`GET changes?since=N` returns every record touched after change N).

Deleting keeps a tombstone, so a delete can be undone too.

## Server (`server/`)

TypeScript on Cloudflare Workers. No framework.

| File | Does |
| --- | --- |
| `src/index.ts` | Routing: the OAuth provider wraps everything; `/mcp` is the protected API, the rest goes to the default handler |
| `src/app-api.ts` | The app's API under `/v1/accounts/:id/` (bearer secret) |
| `src/mcp.ts` | The MCP tools an AI sees, and their instructions |
| `src/store.ts` | Records, revisions, the change log, undo and the feed |
| `src/schema.ts` | What a record may contain |
| `src/accounts.ts` | Accounts (claimed by the first request with a secret), pairing codes, connected AIs |
| `src/authorize.ts` | The sign-in page an AI opens: asks for the pairing code (English or Italian) |
| `src/guidance.ts` | Generated from `docs/styling/` by `npm run sync-guidance` |

Tests: `test/store.test.ts` and `test/guidance.test.ts` run with vitest on Node's built-in SQLite standing in for D1 (`test/d1.ts`), so the real SQL runs. `test/e2e.mjs` drives a local Worker through the whole loop: the app adds a piece and photo, an AI pairs, signs in, suggests tags and proposes an outfit, the AI adds a photo it found online, the person tries the outfit and comments, the AI records a review, both sides undo, and disconnecting and deleting cut everything off.

## App (`ios/`)

Swift 6, SwiftUI with Observation, iOS 26+, iPhone only. XcodeGen generates the project from `ios/project.yml`.

- **`PutiaCore`** (Foundation only, builds and tests on Linux): the record types, `Library` (every record, as last loaded, with what the screens ask of it) and `Change`.
- **`PutiaImaging`** (Apple platforms): the cut-out (Vision's foreground mask) and thumbnails, on the phone.
- **The app target**: `AppModel` (the one observable model), the server client (`HTTPServer`, and `MemoryServer` for tests and UI tests), the Keychain account, and the screens. App code defaults to the main actor.

**Online first.** The app shows the `Library` it last loaded (cached as JSON on disk, photos too) and refreshes every 15 seconds while open, when it becomes active and on pull to refresh. Every change goes straight to the server; if it can't be saved, an alert says why: no connection, or someone (the AI) changed the record first, in which case the app shows the latest version so the person can redo their change. There is no offline queue.

**The account** is a random id and secret made on the phone and kept in the Keychain (synced by iCloud Keychain). No sign-up. "Delete everything" deletes it on the server with all records and photos, and starts a new one.

**Photos** belong to a piece, outfit or inspiration image through the photo record's `ownerId`; a piece's `mainPhotoId` picks the one it's shown with (the first, without one). **Adding a piece**: pick a photo → save an empty piece → `Imaging.prepare` (cut-out and thumbnail) → upload the photo → save the photo record. Further photos are added the same way, without the cut-out.

**Strings**: every user-facing string is in `Support/L10n.swift`, with English and Italian in `Resources/Localizable.xcstrings`. `scripts/check-strings.py` fails CI on a missing translation, an unused key, or a raw literal in a SwiftUI text API.

**Tests**: `PutiaCoreTests` (decoding the server's JSON, the library, encoding, main photos), `PutiaImagingTests`, `PutiaTests` (the app model against `MemoryServer`: saving, conflicts, undo, offline, deleting) and `PutiaUITests` (the main flow on a sample wardrobe, with screenshots), in English and Italian.

## Deploying

The server runs on the owner's Cloudflare account and uses the `cf` CLI, never `wrangler`. The Worker and its bindings are in `server/cloudflare.config.ts`; `cf` builds it with Vite (`server/vite.config.ts`). The resources already exist: D1 `putia`, R2 `putia-photos` and KV `putia-oauth`. Their IDs are in `cloudflare.config.ts`, and the D1 ID is also in the `db:*` scripts in `package.json`.

The Worker answers at `https://api.putia.app`, a custom domain (`domains` in `cloudflare.config.ts`) in the `putia.app` zone on the same account. The rest of that zone belongs to the Putìa storefront: its records are DNS-only, so the storefront keeps its own servers and certificates. The `workers.dev` address is off (`cf` turns it off when a Worker has a custom domain): Cloudflare's bot checks can refuse AI clients there (error 1010).

After every server change, from `server/` (signed in with `cf auth login`):

```sh
npm run db:remote    # cf d1 migrations apply <id>: applies new files in migrations/
npx cf deploy
```

Locally, `npm run db:local` applies the migrations to the state `cf dev` uses (`server/.cloudflare/state`), and `npx cf dev` serves the Worker on http://localhost:5173.

`.github/workflows/server.yml` deploys on every change to `server/` on `main`, once the repository has the secrets `CLOUDFLARE_API_TOKEN` (Workers Scripts, D1, Workers KV Storage and Workers R2 Storage: Edit) and `CLOUDFLARE_ACCOUNT_ID`.

The app reads the server's host from `PUTIA_SERVER_HOST` in `ios/Config/Putia.xcconfig`.
