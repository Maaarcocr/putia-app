import PutiaCore
import UIKit

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
        let confirmed = { (value: String) in Attribute(value, state: .confirmed, by: you) }
        let suggested = { (value: String) in Attribute(value, state: .suggested, by: claude) }
        func photo(_ id: String, of owner: Photo.Owner, _ ownerId: String, _ image: Data, by actor: String, note: String? = nil) {
            try? server.write(.photo(Photo(ownerKind: owner, ownerId: ownerId)), id: id, baseRevision: 0, actor: actor, note: note)
            server.photos["\(id)/\(PhotoSize.thumb.rawValue)"] = image
            server.photos["\(id)/\(PhotoSize.full.rawValue)"] = image
        }
        let ecru = UIColor(red: 0.91, green: 0.87, blue: 0.79, alpha: 1)
        let pieces: [(String, String, [String: Attribute], Data)] = [
            (jacket, "Navy chore jacket", ["category": confirmed("jacket"), "material": suggested("cotton canvas"), "cut": suggested("boxy")],
             drawn(symbol("jacket.fill"), UIColor(red: 0.17, green: 0.23, blue: 0.36, alpha: 1))),
            (shirt, "White oxford shirt", ["category": confirmed("shirt"), "material": confirmed("cotton oxford")],
             drawn(symbol("tshirt.fill"), UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))),
            (trousers, "Grey flannel trousers", ["category": confirmed("trousers"), "material": confirmed("wool flannel")],
             drawn(trouserShape(), UIColor(red: 0.52, green: 0.54, blue: 0.56, alpha: 1))),
            (boots, "Brown suede boots", ["category": confirmed("boots")],
             drawn(symbol("shoe.fill"), UIColor(red: 0.48, green: 0.32, blue: 0.19, alpha: 1))),
            (knit, "Ecru cable knit", ["category": confirmed("knitwear"), "colour": suggested("ecru"), "material": suggested("wool"), "pattern": suggested("cable")], Data()),
        ]
        for (index, (id, name, attrs, image)) in pieces.enumerated() {
            try? server.write(.piece(Piece(name: name, attrs: attrs)), id: id, baseRevision: 0, actor: you)
            if !image.isEmpty {
                photo("00000000-0000-4000-8000-00000000006\(index)", of: .piece, id, image, by: you)
            }
        }
        // The person's snapshot of the knit, and a photo of the same product an AI found online.
        photo("00000000-0000-4000-8000-000000000050", of: .piece, knit, drawn(symbol("tshirt.fill"), ecru, on: UIColor(red: 0.45, green: 0.38, blue: 0.33, alpha: 1)), by: you)
        photo(
            "00000000-0000-4000-8000-000000000051", of: .piece, knit, drawn(symbol("tshirt.fill"), ecru), by: claude,
            note: "Found on shop.example: same style number as on the label"
        )
        try? server.write(
            .outfit(Outfit(
                title: "Soft workwear", pieceIds: [jacket, shirt, trousers, boots],
                note: "Relaxed and textured, for a weekend in town. A boxy jacket over a straight leg; canvas, flannel and suede are all matte. "
                    + "How the flannel drapes over the boots can't be judged from flat photos."
            )),
            id: outfit, baseRevision: 0, actor: claude, note: "Built around the jacket"
        )
        try? server.write(
            .comment(Comment(subjectKind: .outfit, subjectId: outfit, text: "Coherent as it is. If it feels flat, swap the shirt for the cable knit before buying anything.")),
            id: "00000000-0000-4000-8000-000000000020", baseRevision: 0, actor: claude
        )
        try? server.write(
            .wish(Wish(name: "Ecru knit polo", note: "The jacket has no lighter layer for spring that still looks considered. Goes with the jacket and the flannels.")),
            id: "00000000-0000-4000-8000-000000000030", baseRevision: 0, actor: claude
        )
        try? server.write(
            .review(Review(conclusion: .tryCombinations, summary: "Try the cable knit under the chore jacket first; nothing needs buying yet.")),
            id: "00000000-0000-4000-8000-000000000040", baseRevision: 0, actor: claude
        )
        let reference = "00000000-0000-4000-8000-000000000070"
        try? server.write(.reference(Reference(title: "Relaxed tailoring")), id: reference, baseRevision: 0, actor: you)
        photo(
            "00000000-0000-4000-8000-000000000071", of: .reference, reference,
            drawn(symbol("figure.walk"), ecru, on: UIColor(red: 0.33, green: 0.40, blue: 0.35, alpha: 1)), by: you
        )
        return server
    }

    /// A sample photo: a garment in a colour, on a backdrop like a snapshot, or on nothing like a
    /// cut-out.
    private static func drawn(_ garment: UIImage, _ colour: UIColor, on backdrop: UIColor? = nil) -> Data {
        let size = CGSize(width: 480, height: 600)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            if let backdrop {
                backdrop.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            let scale = min(400 / garment.size.width, 500 / garment.size.height)
            let width = garment.size.width * scale
            let height = garment.size.height * scale
            garment.withTintColor(colour).draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height))
        }
    }

    private static func symbol(_ name: String) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 300)
        return UIImage(systemName: name, withConfiguration: configuration) ?? UIImage(systemName: "tshirt.fill", withConfiguration: configuration)!
    }

    /// SF Symbols has no trousers.
    private static func trouserShape() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 320)).image { _ in
            let legs = UIBezierPath()
            legs.move(to: CGPoint(x: 30, y: 0))
            legs.addLine(to: CGPoint(x: 170, y: 0))
            legs.addLine(to: CGPoint(x: 190, y: 320))
            legs.addLine(to: CGPoint(x: 112, y: 320))
            legs.addLine(to: CGPoint(x: 100, y: 80))
            legs.addLine(to: CGPoint(x: 88, y: 320))
            legs.addLine(to: CGPoint(x: 10, y: 320))
            legs.close()
            UIColor.black.setFill()
            legs.fill()
        }
        .withRenderingMode(.alwaysTemplate)
    }
}
