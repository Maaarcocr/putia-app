import Foundation

/// A saved record: its data, plus what the server keeps about it.
public struct Record<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// Send it back when saving a change; the server refuses a change based on an older revision.
    public var revision: Int
    public var createdBy: String
    public var updatedAt: String
    public var value: Value

    public init(id: String, revision: Int, createdBy: String, updatedAt: String, value: Value) {
        self.id = id
        self.revision = revision
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.value = value
    }

    public var author: Author { Author(createdBy) }
}

/// A record of any kind, as the server sends it.
public struct Doc: Decodable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case piece(Piece)
        case outfit(Outfit)
        case photo(Photo)
        case comment(Comment)
        case reference(Reference)
        case wish(Wish)
        case review(Review)

        public var kind: Kind {
            switch self {
            case .piece: .piece
            case .outfit: .outfit
            case .photo: .photo
            case .comment: .comment
            case .reference: .reference
            case .wish: .wish
            case .review: .review
            }
        }
    }

    public let id: String
    public let revision: Int
    public let deleted: Bool
    public let createdBy: String
    public let updatedAt: String
    public let content: Content

    public var kind: Kind { content.kind }

    public init(id: String, revision: Int, deleted: Bool = false, createdBy: String, updatedAt: String, content: Content) {
        self.id = id
        self.revision = revision
        self.deleted = deleted
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.content = content
    }

    private enum CodingKeys: String, CodingKey { case kind, id, revision, deleted, createdBy, updatedAt, data }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decode(Int.self, forKey: .revision)
        deleted = try container.decode(Bool.self, forKey: .deleted)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .piece: content = .piece(try container.decode(Piece.self, forKey: .data))
        case .outfit: content = .outfit(try container.decode(Outfit.self, forKey: .data))
        case .photo: content = .photo(try container.decode(Photo.self, forKey: .data))
        case .comment: content = .comment(try container.decode(Comment.self, forKey: .data))
        case .reference: content = .reference(try container.decode(Reference.self, forKey: .data))
        case .wish: content = .wish(try container.decode(Wish.self, forKey: .data))
        case .review: content = .review(try container.decode(Review.self, forKey: .data))
        }
    }
}

/// The data alone, which is what the app sends when saving.
extension Doc.Content: Encodable {
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .piece(let value): try value.encode(to: encoder)
        case .outfit(let value): try value.encode(to: encoder)
        case .photo(let value): try value.encode(to: encoder)
        case .comment(let value): try value.encode(to: encoder)
        case .reference(let value): try value.encode(to: encoder)
        case .wish(let value): try value.encode(to: encoder)
        case .review(let value): try value.encode(to: encoder)
        }
    }
}

/// The records changed after a change number, and the newest change number.
public struct Feed: Decodable, Sendable {
    public let cursor: Int
    public let docs: [Doc]

    public init(cursor: Int, docs: [Doc]) {
        self.cursor = cursor
        self.docs = docs
    }
}

/// Everything on the bench, as last loaded from the server. The app keeps a copy on disk so it
/// can show the last state offline; saving always goes through the server.
public struct Library: Codable, Equatable, Sendable {
    /// The newest change applied; the next refresh asks for changes after it.
    public var cursor = 0
    public var pieces: [String: Record<Piece>] = [:]
    public var outfits: [String: Record<Outfit>] = [:]
    public var photos: [String: Record<Photo>] = [:]
    public var comments: [String: Record<Comment>] = [:]
    public var references: [String: Record<Reference>] = [:]
    public var wishes: [String: Record<Wish>] = [:]
    public var reviews: [String: Record<Review>] = [:]

    public init() {}

    public mutating func apply(_ feed: Feed) {
        for doc in feed.docs { apply(doc) }
        cursor = max(cursor, feed.cursor)
    }

    /// A newer revision replaces an older one; a deleted record is removed.
    public mutating func apply(_ doc: Doc) {
        switch doc.content {
        case .piece(let value): Self.put(doc, value, into: &pieces)
        case .outfit(let value): Self.put(doc, value, into: &outfits)
        case .photo(let value): Self.put(doc, value, into: &photos)
        case .comment(let value): Self.put(doc, value, into: &comments)
        case .reference(let value): Self.put(doc, value, into: &references)
        case .wish(let value): Self.put(doc, value, into: &wishes)
        case .review(let value): Self.put(doc, value, into: &reviews)
        }
    }

    private static func put<Value>(_ doc: Doc, _ value: Value, into records: inout [String: Record<Value>]) {
        if let current = records[doc.id], current.revision > doc.revision { return }
        records[doc.id] = doc.deleted
            ? nil
            : Record(id: doc.id, revision: doc.revision, createdBy: doc.createdBy, updatedAt: doc.updatedAt, value: value)
    }

    // MARK: What the screens show

    /// Owned pieces, most recently changed first.
    public var ownedPieces: [Record<Piece>] {
        newestFirst(pieces.values.filter { $0.value.status == .owned })
    }

    public var retiredPieces: [Record<Piece>] {
        newestFirst(pieces.values.filter { $0.value.status == .retired })
    }

    public func outfits(in stage: Outfit.Stage) -> [Record<Outfit>] {
        newestFirst(outfits.values.filter { $0.value.stage == stage })
    }

    public func outfits(using pieceId: String) -> [Record<Outfit>] {
        newestFirst(outfits.values.filter { $0.value.items.contains { $0.pieceId == pieceId } })
    }

    /// Variations made from an outfit, newest first.
    public func variations(of outfitId: String) -> [Record<Outfit>] {
        newestFirst(outfits.values.filter { $0.value.parentId == outfitId })
    }

    /// Comments on a record, oldest first, as a conversation reads.
    public func comments(on subjectId: String) -> [Record<Comment>] {
        comments.values.filter { $0.value.subjectId == subjectId }.sorted { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }
    }

    /// Open shortlist entries, highest priority first.
    public var shortlist: [Record<Wish>] {
        newestFirst(wishes.values.filter { $0.value.isOpen }).sorted { $0.value.priority.rank > $1.value.priority.rank }
    }

    /// Entries the person dismissed or bought.
    public var decidedWishes: [Record<Wish>] {
        newestFirst(wishes.values.filter { !$0.value.isOpen })
    }

    public var inspiration: [Record<Reference>] {
        newestFirst(Array(references.values))
    }

    public var latestReview: Record<Review>? {
        newestFirst(Array(reviews.values)).first
    }

    /// The photo a piece is shown with.
    public func heroPhotoId(of piece: Piece) -> String? {
        piece.heroPhotoId ?? piece.photoIds.first
    }

    /// Photos of a piece's product that an AI found online, newest first.
    public func webPhotos(of pieceId: String) -> [Record<Photo>] {
        newestFirst(photos.values.filter { $0.value.ownerKind == .piece && $0.value.ownerId == pieceId && $0.value.source != nil })
    }

    private func newestFirst<Value>(_ records: [Record<Value>]) -> [Record<Value>] {
        // Ties (same instant) fall back to the id, so the order never jumps between refreshes.
        records.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    }
}

/// One entry in the shared history (server/src/store.ts `Change`).
public struct Change: Decodable, Equatable, Sendable, Identifiable {
    public enum Op: String, Decodable, Sendable { case create, update, delete, undo }

    public let seq: Int
    public let kind: Kind
    public let recordId: String
    public let op: Op
    public let actor: String
    public let note: String?
    /// For an undo: the change it reverted.
    public let undoes: Int?
    public let at: String
    /// The record's name, title or text after the change, when it has one.
    public let label: String?

    public var id: Int { seq }
    public var author: Author { Author(actor) }

    public init(seq: Int, kind: Kind, recordId: String, op: Op, actor: String, note: String? = nil, undoes: Int? = nil, at: String, label: String? = nil) {
        self.seq = seq
        self.kind = kind
        self.recordId = recordId
        self.op = op
        self.actor = actor
        self.note = note
        self.undoes = undoes
        self.at = at
        self.label = label
    }

    private enum CodingKeys: String, CodingKey { case seq, kind, id, op, actor, note, undoes, at, after }
    private struct State: Decodable { let data: Label }
    private struct Label: Decodable {
        let name: String?
        let title: String?
        let text: String?
        let summary: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        kind = try container.decode(Kind.self, forKey: .kind)
        recordId = try container.decode(String.self, forKey: .id)
        op = try container.decode(Op.self, forKey: .op)
        actor = try container.decode(String.self, forKey: .actor)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        undoes = try container.decodeIfPresent(Int.self, forKey: .undoes)
        at = try container.decode(String.self, forKey: .at)
        let data = try container.decode(State.self, forKey: .after).data
        label = [data.title, data.name, data.text, data.summary].compactMap { $0 }.first { !$0.isEmpty }
    }
}
