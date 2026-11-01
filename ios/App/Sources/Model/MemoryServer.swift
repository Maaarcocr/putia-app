import Foundation
import PutiaCore

/// A server kept in memory, for unit and UI tests. It checks revisions like the real one, but
/// not the rules about what an AI may do (server/test covers those). A pairing code counts as
/// used after a few status checks, so UI tests see the code and then "connected".
final class MemoryServer: Server {
    var connectorURL: URL { URL(string: "https://putia.example/mcp")! }
    var failing = false
    private(set) var agentNames: [String] = []
    private var docs: [String: Doc] = [:]
    private var log: [(change: Change, before: Doc?)] = []
    private var photos: [String: Data] = [:]
    private var statusChecks = 0
    private let checksBeforeSignIn: Int
    private var clock = 0

    init(checksBeforeSignIn: Int = 2) {
        self.checksBeforeSignIn = checksBeforeSignIn
    }

    private func check() throws {
        if failing { throw ServerError.unavailable }
    }

    /// Writes as `actor`, as the real server does for the app ("human") and for AI ("agent:<name>").
    @discardableResult
    func write(_ content: Doc.Content, id: String, baseRevision: Int, actor: String, deleted: Bool = false, op: Change.Op? = nil, note: String? = nil, undoes: Int? = nil) throws -> Doc {
        let key = "\(content.kind.rawValue)/\(id)"
        let current = docs[key]
        guard (current?.revision ?? 0) == baseRevision else { throw ServerError.conflict(current: current) }
        clock += 1
        let at = Date(timeIntervalSince1970: 1_793_520_000 + Double(clock)).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let doc = Doc(id: id, revision: baseRevision + 1, deleted: deleted, createdBy: current?.createdBy ?? actor, updatedAt: at, content: content)
        docs[key] = doc
        let change = Change(
            seq: log.count + 1, kind: content.kind, recordId: id, op: op ?? (current == nil ? .create : .update),
            actor: actor, note: note, undoes: undoes, at: at, label: Self.label(content)
        )
        log.append((change, current))
        return doc
    }

    func changes(since cursor: Int, account: Account) async throws -> Feed {
        try check()
        let touched = Set(log.filter { $0.change.seq > cursor }.map { "\($0.change.kind.rawValue)/\($0.change.recordId)" })
        return Feed(cursor: log.count, docs: touched.compactMap { docs[$0] })
    }

    func save(_ content: Doc.Content, id: String, baseRevision: Int, note: String?, account: Account) async throws -> Doc {
        try check()
        return try write(content, id: id, baseRevision: baseRevision, actor: Author.you.raw, note: note)
    }

    func delete(_ kind: Kind, id: String, baseRevision: Int, account: Account) async throws -> Doc {
        try check()
        guard let current = docs["\(kind.rawValue)/\(id)"] else { throw ServerError.refused("not found") }
        return try write(current.content, id: id, baseRevision: baseRevision, actor: Author.you.raw, deleted: true, op: .delete)
    }

    func history(account: Account) async throws -> [Change] {
        try check()
        return log.map(\.change).reversed()
    }

    func undo(_ seq: Int, account: Account) async throws -> Doc {
        try check()
        guard let entry = log.first(where: { $0.change.seq == seq }),
              let current = docs["\(entry.change.kind.rawValue)/\(entry.change.recordId)"]
        else { throw ServerError.refused("not found") }
        // Undoing a create deletes the record; anything else puts back what was there before.
        let restored = entry.before ?? current
        return try write(
            restored.content, id: current.id, baseRevision: current.revision, actor: Author.you.raw,
            deleted: entry.before?.deleted ?? true, op: .undo, undoes: seq
        )
    }

    func putPhoto(_ data: Data, type: String, id: String, size: PhotoSize, account: Account) async throws {
        try check()
        photos["\(id)/\(size.rawValue)"] = data
    }

    func photo(_ id: String, size: PhotoSize, account: Account) async throws -> Data {
        try check()
        guard let data = photos["\(id)/\(size.rawValue)"] else { throw ServerError.refused("not found") }
        return data
    }

    func pairingCode(account: Account) async throws -> Pairing {
        try check()
        statusChecks = 0
        return Pairing(code: "K7M2QX9P", expiresAt: .now.addingTimeInterval(600))
    }

    func pairingStatus(_ code: String, account: Account) async throws -> PairingStatus {
        try check()
        statusChecks += 1
        guard statusChecks >= checksBeforeSignIn else { return .waiting }
        if !agentNames.contains("Claude") { agentNames.append("Claude") }
        return .connected(agent: "Claude")
    }

    func agents(account: Account) async throws -> [String] {
        try check()
        return agentNames
    }

    func disconnectAgents(account: Account) async throws {
        try check()
        agentNames = []
    }

    func deleteAccount(_ account: Account) async throws {
        try check()
        docs = [:]
        log = []
        photos = [:]
        agentNames = []
    }

    private static func label(_ content: Doc.Content) -> String? {
        switch content {
        case .piece(let piece): piece.name
        case .outfit(let outfit): outfit.title
        case .comment(let comment): comment.text
        case .reference(let reference): reference.title
        case .wish(let wish): wish.name
        case .review(let review): review.summary
        case .photo: nil
        }
    }

    /// A small wardrobe an AI has already worked on, for UI tests and screenshots.
    static func sample() -> MemoryServer {
        let server = MemoryServer(checksBeforeSignIn: 3)
        let claude = Author.agent("Claude").raw
        let you = Author.you.raw
        let jacket = "00000000-0000-4000-8000-000000000001"
        let shirt = "00000000-0000-4000-8000-000000000002"
        let trousers = "00000000-0000-4000-8000-000000000003"
        let boots = "00000000-0000-4000-8000-000000000004"
        let knit = "00000000-0000-4000-8000-000000000005"
        let outfit = "00000000-0000-4000-8000-000000000010"
        let confirmed = { (value: String) in Attribute([value], state: .confirmed, by: you) }
        let suggested = { (value: String) in Attribute([value], state: .suggested, by: claude) }
        let pieces: [(String, String, String, [String: Attribute])] = [
            (jacket, "Navy chore jacket", "#1f2a44", ["category": confirmed("jacket"), "material": suggested("cotton canvas"), "cut": suggested("boxy")]),
            (shirt, "White oxford shirt", "#eeece4", ["category": confirmed("shirt"), "material": confirmed("cotton oxford")]),
            (trousers, "Grey flannel trousers", "#6b6e72", ["category": confirmed("trousers"), "material": confirmed("wool flannel")]),
            (boots, "Brown suede boots", "#6e4a2f", ["category": confirmed("boots")]),
            (knit, "Ecru cable knit", "#e6dcc6", ["category": confirmed("knitwear"), "material": suggested("wool")]),
        ]
        for (id, name, hex, attrs) in pieces {
            try? server.write(.piece(Piece(name: name, attrs: attrs, swatches: [Swatch(hex: hex)])), id: id, baseRevision: 0, actor: you)
        }
        try? server.write(
            .outfit(Outfit(
                title: "Soft workwear",
                items: [
                    Outfit.Item(pieceId: jacket, role: .outerwear), Outfit.Item(pieceId: shirt, role: .top),
                    Outfit.Item(pieceId: trousers, role: .trousers), Outfit.Item(pieceId: boots, role: .shoes),
                ],
                intent: "Relaxed and textured, for a weekend in town.",
                rationale: Outfit.Rationale(
                    silhouette: "A boxy jacket over a straight, full leg keeps the outline even.",
                    texture: "Canvas, flannel and suede are all matte, so nothing looks dressier than the rest.",
                    effect: "Easy, practical, a little rugged."
                ),
                uncertainty: "How the flannel drapes over the boots can't be judged from flat photos."
            )),
            id: outfit, baseRevision: 0, actor: claude, note: "Built around the jacket"
        )
        try? server.write(
            .comment(Comment(
                subjectKind: .outfit, subjectId: outfit, kind: .assessment,
                text: "Coherent as it is. If it feels flat, swap the shirt for the cable knit before buying anything.", by: claude
            )),
            id: "00000000-0000-4000-8000-000000000020", baseRevision: 0, actor: claude
        )
        try? server.write(
            .wish(Wish(
                name: "Ecru knit polo", priority: .medium,
                problem: "The jacket has no lighter layer for spring that still looks considered.",
                complementsPieceIds: [jacket, trousers], alternativesOwnedIds: [shirt, knit], outfitsToTryIds: [outfit]
            )),
            id: "00000000-0000-4000-8000-000000000030", baseRevision: 0, actor: claude
        )
        try? server.write(
            .review(Review(conclusion: .tryCombinations, summary: "Try the cable knit under the chore jacket first; nothing needs buying yet.")),
            id: "00000000-0000-4000-8000-000000000040", baseRevision: 0, actor: claude
        )
        return server
    }
}
