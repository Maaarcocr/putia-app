# Architecture

Putia is two parts: an iPhone app and a small server. The server holds the shared records; the app and any AI the person connects both read and write them. There is no AI in either.

```
iPhone app ──HTTPS /v1/accounts/:id/…──▶  Cloudflare Worker  ◀──MCP /mcp (OAuth)── the person's AI
 (SwiftUI)                                 D1: accounts, sessions, records + change log
     │                                     R2: photos (the server's own copies)
     └─ Sign in with Apple ─ code ──▶      Images: decodes and re-encodes every photo
                                           KV: OAuth grants
```

## Records

Everything on the bench is a record of one of five kinds: `piece`, `outfit`, `photo`, `comment` and `wish` (a suggestion on What's missing). Their shapes are defined once on the server (`server/src/schema.ts`, zod) and mirrored in Swift (`ios/Packages/PutiaKit/Sources/PutiaCore/Records.swift`). Change both together.

The server stores each record as JSON in one generic table, `docs`, with a **revision**. Every write:

1. names the revision it was based on (0 to create). A stale revision is refused with 409 and the current record, so nobody overwrites a change they haven't seen;
2. is validated (shape, and that the records it points at exist). A new record also needs room under its kind's limit (`LIMITS` in `schema.ts`: 3,000 photos, 1,000 pieces, …), counted with deleted ones, since they can be undone; the count is part of the same transaction, so racing writes can't pass it together;
3. is recorded in `changes` with the state before and after, the author (`human`, or `agent:<name>` for an AI) and an optional note, in the same D1 batch.

D1 sits in one place and every query is a round trip to it, so a write keeps them few: the account check, reading the current record, one query for the records it points at (if any) and the batch.

The person and an AI can change the same things: the server doesn't check who wrote what.

`changes` is at once the history, the source for undo (put back the `before` state, if the record hasn't changed since) and the app's sync feed (`GET changes?since=N` returns every record touched after change N).

Deleting keeps a tombstone, so a delete can be undone too.

## Server (`server/`)

TypeScript on Cloudflare Workers. No framework.

| File | Does |
| --- | --- |
| `src/index.ts` | Routing: the OAuth provider wraps everything; `/mcp` is the protected API, the rest goes to the default handler |
| `src/app-api.ts` | The app's API: `/v1/sign-in`, and the rest under `/v1/accounts/:id/` (bearer secret) |
| `src/mcp.ts` | The MCP tools an AI sees, and their instructions |
| `src/store.ts` | Records, revisions, the change log, undo and the feed |
| `src/schema.ts` | What a record may contain |
| `src/accounts.ts` | Accounts (made by the first Sign in with Apple), sessions (one secret per signed-in phone), pairing codes, connected AIs |
| `src/apple.ts` | Sign in with Apple: trades the app's one-time code with Apple for the person's id, and revokes it when the account is deleted |
| `src/photos.ts` | Saves a photo record with its images, for the app and for AI: the server decodes each image with Cloudflare Images and keeps only its own WebP copy, at most 2000 (full) and 600 (thumb) pixels on the long side |
| `src/authorize.ts` | The sign-in page an AI opens: asks for the pairing code (English or Italian) |
| `src/guidance.ts` | Generated from `docs/styling/` by `npm run sync-guidance` |

Tests: `test/store.test.ts` and `test/guidance.test.ts` run with vitest on Node's built-in SQLite standing in for D1 (`test/d1.ts`), so the real SQL runs. `test/accounts.test.ts` covers sign-in and sessions against a stand-in for Apple. `test/e2e.mjs` drives a local Worker through the whole loop: the person signs in (with a test code that only `cf dev` accepts), the app adds a piece and photo, an AI pairs, signs in, suggests tags and proposes an outfit, the AI adds a photo it found online, the person tries the outfit and comments, the AI suggests something missing with a link and a photo, both sides undo, and disconnecting and deleting cut everything off.

## App (`ios/`)

Swift 6, SwiftUI with Observation, iOS 26+, iPhone only. XcodeGen generates the project from `ios/project.yml`.

- **`PutiaCore`** (Foundation only, builds and tests on Linux): the record types, `Library` (every record, as last loaded, with what the screens ask of it) and `Change`.
- **`PutiaImaging`** (Apple platforms): the cut-out (Vision's foreground mask) and thumbnails, on the phone.
- **The app target**: `AppModel` (the one observable model), the server client (`HTTPServer`, and `MemoryServer` for tests and UI tests), the Keychain account, and the screens. App code defaults to the main actor.

**Online first.** The app shows the `Library` it last loaded (cached as JSON on disk, photos too) and refreshes every 15 seconds while open, when it becomes active and on pull to refresh. Every change shows at once and goes straight to the server. Changes to one record are sent one after another, each based on the revision the one before produced, so quick taps (confirming two tags) don't trip over each other. If a change can't be saved, the record goes back to the server's version and an alert says why: no connection, or someone (the AI) changed the record first, in which case the app shows the latest version so the person can redo their change. There is no offline queue.

**The account**: the first screen is Sign in with Apple, asking for no name and no email. The app sends the one-time code Apple gives it to the server, which answers with the account id and a secret for this phone, kept in the Keychain (synced by iCloud Keychain). A 401 from the server (the account was deleted elsewhere) goes back to signing in. "Delete everything" deletes the account on the server with all records and photos, ends the Sign in with Apple, and signs out. Accounts made before sign-in existed keep working with their secret.

**Photos** belong to a piece, outfit or suggestion through the photo record's `ownerId`; a piece's `mainPhotoId` picks the one it's shown with (the first, without one). **Adding a piece**: pick a photo → save an empty piece → `Imaging.prepare` (cut-out and thumbnail) → save the photo record with both images in one request. Further photos are added the same way, without the cut-out.

**Strings**: every user-facing string is in `Support/L10n.swift`, with English and Italian in `Resources/Localizable.xcstrings`. `scripts/check-strings.py` fails CI on a missing translation, an unused key, or a raw literal in a SwiftUI text API.

**Tests**: `PutiaCoreTests` (decoding the server's JSON, the library, encoding, main photos), `PutiaImagingTests`, `PutiaTests` (the app model against `MemoryServer`: saving, conflicts, undo, offline, deleting) and `PutiaUITests` (the main flow on a sample wardrobe, with screenshots), in English and Italian.

## Deploying

The server runs on the owner's Cloudflare account and uses the `cf` CLI, never `wrangler`. The Worker and its bindings are in `server/cloudflare.config.ts`; `cf` builds it with Vite (`server/vite.config.ts`). The resources already exist: D1 `putia`, R2 `putia-photos` and KV `putia-oauth`. Their IDs are in `cloudflare.config.ts`, and the D1 ID is also in the `db:*` scripts in `package.json`. Photos also use the Images binding (Cloudflare Images transformations, billed per transformation beyond the free allowance; each photo is two).

Sign in with Apple needs the team's Sign in with Apple key (docs/testflight.md) as two Worker secrets, set once from `server/`:

```sh
npx cf workers secrets update APPLE_KEY_ID        # the key's 10-character ID
npx cf workers secrets update APPLE_PRIVATE_KEY   # the .p8 file's contents
```

The bundle ID and team are plain values in `cloudflare.config.ts`. Under `cf dev` (mode `development`) the Worker also gets `TEST_SIGN_IN`, so the code `test:<anything>` signs in without Apple for local tests; a deployed Worker never has it.

The Worker answers at `https://api.putia.app`, a custom domain (`domains` in `cloudflare.config.ts`) in the `putia.app` zone on the same account. The rest of that zone belongs to the Putìa storefront: its records are DNS-only, so the storefront keeps its own servers and certificates. The `workers.dev` address is off (`cf` turns it off when a Worker has a custom domain): Cloudflare's bot checks can refuse AI clients there (error 1010).

After every server change, from `server/` (signed in with `cf auth login`):

```sh
npm run db:remote    # cf d1 migrations apply <id>: applies new files in migrations/
npx cf deploy
```

Locally, `npm run db:local` applies the migrations to the state `cf dev` uses (`server/.cloudflare/state`), and `npx cf dev` serves the Worker on http://localhost:5173.

`.github/workflows/server.yml` deploys on every change to `server/` on `main`, once the repository has the secrets `CLOUDFLARE_API_TOKEN` (Workers Scripts, D1, Workers KV Storage and Workers R2 Storage: Edit) and `CLOUDFLARE_ACCOUNT_ID`.

The app reads the server's host from `PUTIA_SERVER_HOST` in `ios/Config/Putia.xcconfig`.
