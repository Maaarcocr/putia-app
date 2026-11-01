# The AI connector

Putia has no AI inside. The server (`server/`, a Cloudflare Worker) holds the shared records, and an AI the person chooses connects to it as a remote MCP server at `https://<host>/mcp`. The AI and the person then work on the same bench: everything the AI saves is attributed to it, kept in the history and can be undone in the app.

## Connecting

1. In the app: **Bench → Connect an AI**. The sheet shows the connector address and a one-time pairing code (8 characters, valid for 10 minutes, used once).
2. In the AI app (Claude: *Settings → Connectors → Add custom connector*), add the address.
3. The AI app opens Putia's sign-in page, which asks for the pairing code. Entering it connects that AI to the phone's account; the sheet in the app turns to "connected".

Sign-in is standard OAuth 2.1 with PKCE (`@cloudflare/workers-oauth-provider`), with dynamic client registration and Client ID Metadata Documents. There are no passwords: the pairing code is the only proof, and it can only come from the phone.

**Disconnect all AIs** on the Bench rotates the account's agent key: every token stops working at once, and the grants are revoked. Changes the AIs already made stay.

## What the AI can do

The tools (`server/src/mcp.ts`):

| Tool | Does |
| --- | --- |
| `overview` | Counts, pieces whose tags need review, outfits by stage, the shortlist, the latest changes |
| `guidance` | The whole styling skill from `docs/styling/`: the assessment approach, its principles and its sources |
| `list`, `get` | Records of one kind; one record with its comments (and, for a piece, its photos and outfits) |
| `get_photo` | A photo as an image: the cut-out thumbnail or the full photo |
| `add_product_photo` | A photo of a piece's exact product that the AI found online: it passes the image's address and the page it's on, and the server downloads it |
| `save_piece`, `save_outfit`, `save_reference`, `save_wish`, `save_review` | Create or update, passing the revision it read |
| `comment` | A comment, or an `assessment` of an outfit |
| `delete` | Only records the AI created |
| `history`, `undo` | The change log; undo only changes made by AI |

The server enforces what an AI may change (`server/src/rules.ts`), whatever the tool descriptions say:

- **Tags are suggestions.** Every tag an AI sets is saved as `suggested` and attributed to it. It can't change a value the person confirmed (it can comment instead). It can't change photos, notes, measured colours or a piece's status, and can name only an unnamed piece.
- **The person's photos are theirs.** An AI can't add, change or remove them. It can add a photo of a piece's product that it found online: the server downloads it (JPEG, PNG or WebP, up to 8 MB, from public https addresses only) and saves it as a `flat` photo of that piece with its `source` page. The app shows it under *From the web*, where the person can make it the piece's main photo or delete it. A piece's main photo can't be deleted or undone away until another photo is the main one.
- **Outfits start as proposals.** An AI creates `proposed` outfits; only the person marks them tried or favourite. Days worn and mirror photos are the person's.
- **Inspiration is the person's.** An AI only writes a reference's *translation*: which owned pieces carry the same relationship.
- **Purchases are the person's call.** An AI can add or update shortlist entries, but can't mark one dismissed or bought, nor change it after the person decided.
- **Reviews and comments are never edited**, only added. "Nothing needed" is a valid review.
- **Undo:** an AI undoes only AI changes; the person can undo anything. An undo is refused if the record changed since.

Every write names the revision it was based on. If the person changed the record meanwhile, the AI gets a conflict with the current version and redoes its change on top.

## Styling guidance

The `guidance` tool returns the whole candid menswear assessment skill in `docs/styling/` (judge the whole combination, name the smallest sufficient change, separate observation from preference, no scores or flattery), and the server's instructions tell the AI to read it before its first assessment. `server/src/guidance.ts` is generated from those files: after editing them, run `npm run sync-guidance` in `server/`. A unit test fails when the two drift.

The instructions also ask the AI to get to know each piece: when a label, tag, barcode or product code is visible, or a note names the brand and model, it looks the exact product up online (if it can search the web), adds the listing's clearest photo (the piece alone on a plain or transparent background), suggests tags from it and comments with what it found. A listing shows the product as sold, not the person's piece, so its tags are still suggestions.

## The app's API

The app talks to `/v1/accounts/:id/…` with `Authorization: Bearer <secret>`. The account id and secret are random, made on the phone and kept in the Keychain; the first request claims the account.

| Route | Does |
| --- | --- |
| `GET changes?since=N` | Records changed after change N, and the newest change number |
| `PUT docs/:kind/:id` | `{ baseRevision, data, note? }`: create (revision 0) or update. 409 with `current` on a stale revision |
| `DELETE docs/:kind/:id?base=N` | Delete (undoable) |
| `GET history?before=N` | The change log, newest first |
| `POST undo/:seq` | Revert one change |
| `PUT`/`GET photos/:id/thumb\|full` | Photo bytes (JPEG, PNG or HEIC, up to 8 MB) |
| `POST pairing`, `GET pairing/:code` | A pairing code; whether an AI used it |
| `GET agents`, `DELETE agents` | Connected AIs; disconnect them all |
| `DELETE` (the account) | Delete everything: records, photos, AIs |
