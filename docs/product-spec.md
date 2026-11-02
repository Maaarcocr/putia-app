# Putia — Product spec

Putia ("workshop" in Sicilian) is a private wardrobe studio: a visual catalogue, an outfit workbench and a considered shopping shortlist. You and an AI work on the same saved pieces and outfits, instead of sending photos back and forth.

**The AI is not in the app.** The app holds the shared records. An AI system you choose (Claude, ChatGPT, anything that supports remote MCP connectors) connects with your permission and works on the same bench: it reads the wardrobe, saves suggestions and comments, and you see them in the app.

Status: first vertical slice. §9 lists what the slice covers. Everything is kept as small as it can be: more comes when it's needed.

## 1. Principles

- **One bench, two people.** Everything the AI does is a saved, attributed change on the same records you see. Nothing lives only in a chat.
- **Honest evidence.** A photo cannot establish exact material, true colour, size or comfort. The AI saves the tags it sets as *suggestions* you confirm or correct.
- **Owned, wanted and inspiring are different things.** Pieces you own, pieces you might buy and inspiration images never mix.
- **Proposed → tried → favourite.** A collage helps explore; wearing it tells whether it works.
- **Valid conclusions include "nothing needed".** Trying a different combination of what you own is a legitimate answer to "what's missing".
- **Reversible.** Every change has a history and can be undone.
- **Plain and quick.** Adding a piece takes seconds. No inventory form.

## 2. Your wardrobe

Add a piece by choosing a photo (camera capture comes later). The phone cuts it out for a clean thumbnail. Nothing else is required: a name is optional.

Each piece has:

- **Photos.** Any number: yours, a photo of its label, or a photo of the product an AI found online. One is the main photo, the one the piece is shown with: the first, until you choose another.
- **Tags:** category, colour, material, cut (the *intended* shape: boxy, tapered, cropped, full…), pattern and season. Each says who set it and whether you confirmed it.
- The outfits it appears in, and comments.

Pieces whose tags are missing or still suggestions are flagged; confirming is one tap, correcting is an edit.

**Getting to know a piece.** Your photo is often a quick snapshot. When a label, tag, barcode or product code is visible (or you name the brand and model in a comment), a connected AI can look the exact product up online, add the listing's clearest photo to the piece, suggest tags and comment with what it found. When it can't tell what a piece is, it asks you for the label, barcode or product code, in the chat or as a comment on the piece: add the photo to the piece, or answer with a comment. A listing shows the product as sold, not your piece, so tags taken from it are still suggestions.

## 3. Outfit workbench

An outfit is a set of owned pieces, shown as a collage made automatically from each piece's main photo. The pieces are listed from head to feet, outer layers first, and the collage lays them out in that order, each over the next: the jacket over the shirt, the shirt over the trousers.

- **Assemble** an outfit from owned pieces, and edit its title and pieces later.
- **Proposals from the AI** ("make three outfits around this jacket using what I own") come with a note: the intended effect, silhouette and textures, and what a collage can't show.
- **Stages:** `proposed`, `tried` and `favourite`.
- **Photos and comments** stay with the outfit: a mirror photo, how it went, the AI's assessment. An AI can add photos too: a collage it made that shows the layering, or a similar look it found online.

The AI follows the assessment approach in `docs/styling/`: it judges the whole combination, names the smallest sufficient change, separates observation from preference, and does not hand out rules, scores or flattery.

## 4. Inspiration

An inspiration image is not an outfit and not a purchase. You save it with a title and a note on what you like about it. The AI can comment on which owned pieces carry the same relationship, and propose an outfit from them.

## 5. What's missing

Never a generic list of essentials. Suggestions come from the actual wardrobe.

A shortlist entry (a *wish*) has a name, a note on the problem it solves in terms of what you own, an optional link, and a status: `considering`, `bought` or `dismissed`. A wish never turns into a piece by itself.

A **review** records a conclusion: `gaps`, `try-combinations` or `nothing-needed`, with a short summary. All three are first-class results.

## 6. Collaboration

- The app and the AI read and write the same server-held records. Offline, the app shows what it last loaded; changes need a connection.
- The AI can change anything you can. Every change is attributed (you, or the AI by connector name), can carry a reason, and is kept in a history.
- Any change can be undone from the app or by the AI, unless the record has changed since; then the conflict is shown instead of overwritten.
- Anyone can comment on a piece, outfit, inspiration image or wish.
- **Connecting an AI:** Bench → Connect an AI shows the connector address and a one-time pairing code. The AI signs in with that code. The Bench lists connected AIs and can disconnect all at once, instantly.

## 7. Privacy

- Photos and records are stored in the studio server (Cloudflare D1 and R2), tied to a random account on your phone. There are no logins, emails, analytics, ads or third-party SDKs.
- The AI sees only what the connector exposes, and only after you pair it.
- Deleting everything removes the server data.
- Cut-outs and thumbnails are made on the phone.

## 8. Not in scope

AI inside the app; marketplace, price tracking or purchasing; body measurements or size inference; scoring or ranking people's bodies; social sharing.

## 9. First slice

Covers the full loop, thinly:

1. Add a piece from a photo (cut out on the phone); add more photos; set or confirm tags.
2. The AI reads the piece and its photos, looks up the product online and adds its photo, suggests tags, and proposes outfits from owned pieces.
3. You change an outfit's stage and pieces, add photos and comment.
4. The AI records a shortlist entry or a "nothing needed" review; you see it in the app.
5. History with undo.
6. The whole app in English and Italian.
7. Builds tested on GitHub's Mac runners and uploaded to TestFlight.

Later, when needed: camera capture, comparing two versions of an outfit, colours measured on the phone, days worn, retiring pieces, priorities on the shortlist.
