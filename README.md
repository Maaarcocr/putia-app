<h1 align="center">Putia</h1>

<p align="center">
  A private wardrobe studio for iPhone, where you and your AI work on the same bench.<br>
  English · Italiano
</p>

---

Putia ("workshop" in Sicilian) is a visual catalogue of the clothes you own, an outfit workbench and a short list of what, if anything, is missing.

**There is no AI in the app.** Putia keeps the shared records; you connect the AI you already use (Claude, or anything that supports remote MCP connectors) and it works on the same pieces and outfits you see. Everything it changes is attributed to it, kept in the history and can be undone.

## What it does

- **Wardrobe.** Add a piece from a photo: the phone cuts it out. A piece can have more photos, such as its label, or the product photo an AI found online. Every tag says who set it and whether you confirmed it; material and fit are never presented as facts read from a photo.
- **Outfit workbench.** Large cards, favourites first. AI proposals explain the intended effect, silhouette and texture, and what a photo can't show. Photos and comments stay with the outfit.
- **What's missing.** Suggestions of things to get, from you or the AI. Each names the problem it solves in terms of what you own, with links and the product's photos.
- **Collaboration.** Shared records, comments, revisions, history and undo, from the app and from the AI.

The full behaviour is in **[docs/product-spec.md](docs/product-spec.md)**.

## How it's built

- iPhone app: Swift 6, SwiftUI, iOS 26+, XcodeGen, a local Swift package (`PutiaCore`, `PutiaImaging`). English and Italian.
- Server: a Cloudflare Worker with D1 (records and their history), R2 (photos) and an MCP endpoint with OAuth sign-in by pairing code.
- CI and TestFlight on GitHub's Mac runners: no Mac needed.

Details: **[docs/architecture.md](docs/architecture.md)**, **[docs/connector.md](docs/connector.md)**, **[docs/testflight.md](docs/testflight.md)**.

## Repository layout

```
ios/
  project.yml          XcodeGen spec (the .xcodeproj is generated, never committed)
  App/                 SwiftUI app: screens, app model, string catalogs, assets
  Packages/PutiaKit/   PutiaCore (records, library; Linux-testable) and PutiaImaging
  Tests/               App unit tests and UI tests
server/                Cloudflare Worker: records, photos, history, the MCP connector
docs/                  Product spec, architecture, connector, TestFlight, styling guidance
scripts/               String check, iOS tests, TestFlight pipeline and its offline tests
```

## Privacy

Photos and records live on Putia's server under a random account made on your phone: no sign-up, email, analytics, ads or third-party SDKs. An AI sees your wardrobe only after you pair it, and you can disconnect it at any time. "Delete everything" removes it all from the server.
