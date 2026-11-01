# Putia — Product spec

Putia ("workshop" in Sicilian) is a private wardrobe studio: a visual catalogue, an outfit workbench and a considered shopping shortlist. You and an AI work on the same saved pieces and outfits, instead of sending photos back and forth.

**The AI is not in the app.** The app holds the shared records. An AI system you choose (Claude, ChatGPT, anything that supports remote MCP connectors) connects with your permission and works on the same bench: it reads the wardrobe, saves suggestions and comments, and you see them in the app.

Status: first vertical slice. §9 lists what the slice covers.

## 1. Principles

- **One bench, two people.** Everything the AI does is a saved, attributed change on the same records you see. Nothing lives only in a chat.
- **Honest evidence.** A photo cannot establish exact material, true colour, size or comfort. Anything the AI infers from a photo is a *suggestion* you confirm or correct. Material and cut are never shown as facts unless you confirmed them.
- **Owned, wanted and inspiring are different things.** Pieces you own, pieces you might buy and inspiration images never mix.
- **Proposed → tried → favourite.** A collage helps explore; a worn photo and your reaction tell us whether it works. Only you can say an outfit was tried or is a favourite.
- **Valid conclusions include "nothing needed".** Rearranging what you own, or trying a different combination, is a legitimate answer to "what's missing".
- **Reversible.** Every change has a history and can be undone.
- **Plain and quick.** Adding a piece takes seconds. No inventory form.

## 2. Your wardrobe

Add a piece by choosing a photo (camera capture comes later). On the device, the app prepares a clean cut-out thumbnail, measures the dominant colours and suggests a category and a colour name. Nothing else is required: a name is optional.

Each piece has:

- Photos, including how it looks worn.
- Category, colour, material, cut (the *intended* shape: boxy, tapered, cropped, full…) and season. Each value records who set it (you, the AI, the device) and whether it is confirmed or still a suggestion.
- Your notes: comfortable, too warm, awkward with certain shoes, needs alteration.
- The outfits it appears in.
- A status: **owned** or **retired** (kept for history, not offered in new outfits).

Tag review: pieces with unconfirmed suggestions are flagged; confirming is one tap, correcting is an edit. The AI can read photos of pieces that still need tags and suggest them.

**Photos from the web.** Your photo is often a quick snapshot. When a label, tag, barcode or product code is visible (or you name the brand and model in a note), a connected AI can look the exact product up online and add the listing's clearest photo: the piece alone on a plain background. It appears under *From the web* with the page it came from. You can make it the piece's main photo, so outfits show the clean image, or delete it. It shows the product as sold, not your piece, so tags taken from the listing are still suggestions.

## 3. Outfit workbench

An outfit is a set of pieces, each in a role (top, layer, trousers, shoes, accessory…), shown as large visual cards.

- **Assemble** an outfit from owned pieces. In an outfit, swap any piece for another owned one.
- **Compare two versions** side by side. A swap makes a variant that records which outfit it came from and which one variable changed, so a comparison tests one thing; the original stays as it was.
- **Proposals from the AI** ("make three outfits around this jacket using what I own") are saved with a short explanation: the intended effect, silhouette and textures. They can also state what a photo or collage cannot show.
- **Stages:** `proposed` (anyone can create), `tried` and `favourite` (only you). Moving to tried asks for nothing more; attaching a worn photo is encouraged, not required.
- **Reactions** ("loved it", "fine", "didn't work", plus a note about comfort or fit) and comments stay attached to the outfit. So do mirror photos.

The AI follows the assessment approach in `docs/styling/`: it judges the whole combination, names the smallest sufficient change, separates observation from preference, and does not hand out rules, scores or flattery.

## 4. Inspiration

An inspiration image is not an outfit and not a purchase. You save it with what attracts you to it (outline, volume, pattern, texture, colour areas, mood). The AI can add a *translation*: which owned pieces carry that same relationship, and a proposed outfit built from them. An image stays separate from outfits you have actually tried.

## 5. What's missing

Never a generic list of essentials. Suggestions come from the actual wardrobe, references, climate and occasions.

A shortlist entry (a *wish*) shows:

- the problem it solves, in terms of existing outfits ("two jackets lack a convincing trouser");
- the owned pieces it would complement;
- alternatives already owned, and outfits to try first;
- a priority (`low`, `medium`, `high`) and a status (`considering`, `trying-first`, `dismissed`, `bought`).

A wish does not turn into a piece unless you say you bought it. A **review** records a conclusion of its own: `gaps` (there are real gaps), `try-combinations` or `nothing-needed`, with a short summary. All three are first-class results.

## 6. Collaboration

- The app and the AI read and write the same server-held records. Offline, the app shows what it last loaded; changes need a connection. (Keep it simple: no offline write queue until it's clearly needed.)
- Every change is attributed (you, or the AI by connector name), carries an optional reason, and is kept in a history.
- Any change can be undone from the app or by the AI, unless the record has changed since; then the conflict is shown instead of overwritten.
- Comments are separate from edits: anyone can comment on a piece, outfit, inspiration or wish.
- **Connecting an AI:** Bench → Connect an AI shows the connector address and a one-time pairing code. The AI signs in with that code. The Bench lists connected AIs and can disconnect all at once, instantly.

## 7. Privacy

- Photos and records are stored in the studio server you deploy (Cloudflare D1 and R2), tied to a random account on your phone. There are no logins, emails, analytics, ads or third-party SDKs.
- The AI sees only what the connector exposes, and only after you pair it.
- Turning the connection off and deleting the account removes the server data.
- Colour extraction, cut-outs and thumbnails are made on the device.

## 8. Not in scope

AI inside the app; marketplace, price tracking or purchasing; body measurements or size inference; scoring or ranking people's bodies; social sharing.

## 9. First slice

Covers the full loop, thinly:

1. Add a piece from a photo (cut-out and colours on device); correct or confirm tags.
2. The AI reads the piece and its photo, looks up the product online and adds its photo, suggests tags, and proposes outfits built from owned pieces.
3. You swap a piece, change the stage, react, comment and compare two versions.
4. The AI records a shortlist entry or a "nothing needed" review; you see it in the app.
5. History with undo.
6. The whole app in English and Italian.
7. Builds tested on GitHub's Mac runners and uploaded to TestFlight.

Later: camera capture, worn-photo flow polish, editing a reference's translation in the app, widgets.
