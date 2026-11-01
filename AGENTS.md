# AGENTS.md

## Project summary

Putia is a private wardrobe studio for iPhone (Swift 6, SwiftUI, iOS 26+) with a small server (`server/`, a Cloudflare Worker with D1 and R2). The AI is **not** in the app: the person connects their own AI to the server over MCP, and both work on the same records.

Status: first vertical slice (0.1). See `docs/product-spec.md` §9.

## Source-of-truth documents

- `docs/product-spec.md`: what the app does. Read it before any product, UX, copy or flow change, and update it in the same change when behaviour changes on purpose.
- `docs/architecture.md`: how it is built, and how to deploy the server.
- `docs/connector.md`: the AI connector: pairing, tools, what an AI may change, the app's API.
- `docs/testflight.md`: the release pipeline and Apple/GitHub setup.
- `docs/styling/`: the outfit-assessment approach the AI follows. `server/src/guidance.ts` is generated from it (`npm run sync-guidance`).
- `AGENTS.md` (this file): how to work here.

## Keep it simple

The owner's most important rule: plain, standard, boring code, with the fewest moving parts. A clever construct needs a reason a reviewer would accept.

- Use stock SwiftUI controls and semantic styles; there is no design system.
- "Are you sure?" confirmations use `.alert` with a destructive button and Cancel, attached to the button that opens it. Not `confirmationDialog`: on iOS 26 it is a popover.
- One presentation per view: attach each sheet or alert to the control that opens it, never two on the same view.
- No offline write queue, sync engine or local database: the server holds the records, the app shows what it last loaded.
- One generic save path for every kind of record, on the server and in the app.

## Non-negotiable rules

- **English and Italian.** Every user-facing string goes through `ios/App/Sources/Support/L10n.swift` with English and Italian in `Localizable.xcstrings`: UI text, accessibility labels, errors, and the server's sign-in page (`server/src/authorize.ts`). Use `FormatStyle` for dates and numbers. `scripts/check-strings.py` enforces the app side.
- **The AI is outside the app.** Never add an AI model, API key or chat to the app.
- **Honest evidence.** Any tag an AI sets is a suggestion until the person confirms it. Material and fit are never shown as facts from a photo. The server enforces what an AI may change (`server/src/rules.ts`); keep the tool descriptions in `server/src/mcp.ts` truthful about it.
- **Only the person** marks outfits tried or favourite, marks a shortlist entry bought or dismissed, picks a piece's main photo and deletes what they made. An AI may add a photo to a piece (of its product, found online).
- **Everything is attributed and undoable**, through the change log.
- **Privacy.** No sign-up, analytics, crash reporting, ads or third-party SDKs. The privacy manifest declares exactly photos and user content, unlinked, for app functionality; `scripts/verify-ios-bundle.py` checks the built app.

## Commands

```sh
# Any OS with Python 3
python3 scripts/check-strings.py
python3 -m unittest discover -s scripts -p 'test_testflight_ci.py' -v
bash -n scripts/*.sh

# Any OS with Node 24 (the server)
(cd server && npm ci && npm run check && npm test)
(cd server && npm run db:local && npx cf dev)   # then, in another shell:
node server/test/e2e.mjs http://localhost:5173

# Any OS with Swift 6.2 (Linux runs PutiaCore; macOS also PutiaImaging)
swift test --package-path ios/Packages/PutiaKit

# macOS, Xcode 26.6+, xcodegen
(cd ios && xcodegen generate)
./scripts/test-ios.sh
xcodebuild build -project ios/Putia.xcodeproj -scheme Putia -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath ios/DerivedData-Release CODE_SIGNING_ALLOWED=NO
python3 scripts/verify-ios-bundle.py ios/DerivedData-Release/Build/Products/Release-iphoneos/Putia.app
```

## Testing expectations

- Change a record shape: update `server/src/schema.ts` and `PutiaCore/Records.swift` together, with tests on both sides.
- Change who may do what: `server/test/store.test.ts`, and `server/test/e2e.mjs` for anything an AI does through MCP.
- New user-facing actions get a UI test that reaches them in CI; UI tests find elements by accessibility identifier and pass in both languages.
- Keep `scripts/test_testflight_ci.py` passing when changing release scripts. It must never call real Apple tools or use real credentials.

## Git

- Never commit signing material (`*.p12`, `*.p8`, `*.mobileprovision`, `*.key.pem`, `*.certSigningRequest`), `ios/Config/Signing.local.xcconfig`, the generated `ios/Putia.xcodeproj`, build products, `server/.cloudflare/` or `server/.dev.vars`.
- Use the `cf` CLI for everything Cloudflare (develop, migrate, deploy). Never `wrangler`, the old CLI.
- Never pass signing settings to `xcodebuild` on the command line: they would also reach the Swift package targets. App signing goes through `ios/Config/Putia.xcconfig`.
