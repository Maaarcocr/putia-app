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
| `list`, `get` | Records of one kind; one record with its comments and photos (and, for a piece, its outfits) |
| `get_photo` | A photo as an image: the cut-out thumbnail or the full photo |
| `add_photo` | A photo for a piece, outfit or inspiration image: a piece's product found online, or for an outfit a collage the AI made or a similar look it found. It passes an https address (the server downloads it) or the image itself as a data: URL, and a note on where it comes from |
| `save_piece`, `save_outfit`, `save_reference`, `save_wish`, `save_review` | Create or update, passing the revision it read |
| `comment` | A comment on a piece, outfit, inspiration image or shortlist entry |
| `delete` | Any record (undoable) |
| `history`, `undo` | The change log; undo any change |

An AI can change anything the person can: the server doesn't check who wrote what. Every change is attributed to it, kept in the history and can be undone. Its instructions ask it to save the tags it sets as `suggested`, for the person to confirm, and to propose outfits as `proposed`.

`add_photo` takes JPEG, PNG or WebP, up to 8 MB. The instructions ask the AI to list an outfit's pieces from head to feet, outer layers first, since the app's collage follows that order, and to add a collage of its own showing the layering when it can make images.

Every write names the revision it was based on. If the person changed the record meanwhile, the AI gets a conflict with the current version and redoes its change on top. An undo is refused if the record changed since.

## Styling guidance

The `guidance` tool returns the whole candid menswear assessment skill in `docs/styling/` (judge the whole combination, name the smallest sufficient change, separate observation from preference, no scores or flattery), and the server's instructions tell the AI to read it before its first assessment. `server/src/guidance.ts` is generated from those files: after editing them, run `npm run sync-guidance` in `server/`. A unit test fails when the two drift.

The instructions also ask the AI to get to know each piece: when a label, tag, barcode or product code is visible, or a comment names the brand and model, it looks the exact product up online (if it can search the web), adds the listing's clearest photo (the piece alone on a plain or transparent background), suggests tags from it and comments with what it found and the link. A listing shows the product as sold, not the person's piece, so its tags are still suggestions. When the AI can't tell what a piece is, it asks the person for a photo of the label, care tag or barcode, or the brand and product name or code, in the chat or as a comment on the piece, a few pieces at a time.

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
