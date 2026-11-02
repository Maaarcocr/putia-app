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
        case wish(Wish)

        public var kind: Kind {
            switch self {
            case .piece: .piece
            case .outfit: .outfit
            case .photo: .photo
            case .comment: .comment
            case .wish: .wish
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
        case .wish: content = .wish(try container.decode(Wish.self, forKey: .data))
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
        case .wish(let value): try value.encode(to: encoder)
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
    public var wishes: [String: Record<Wish>] = [:]

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
        case .wish(let value): Self.put(doc, value, into: &wishes)
        }
    }

    private static func put<Value>(_ doc: Doc, _ value: Value, into records: inout [String: Record<Value>]) {
        if let current = records[doc.id], current.revision > doc.revision { return }
        records[doc.id] = doc.deleted
            ? nil
            : Record(id: doc.id, revision: doc.revision, createdBy: doc.createdBy, updatedAt: doc.updatedAt, value: value)
    }

    /// Shows a change the person made that the server hasn't confirmed yet: over the record, which
    /// keeps its revision, or as a new record of theirs.
    public mutating func show(_ content: Doc.Content, id: String, at date: Date = .now) {
        let at = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        switch content {
        case .piece(let value): Self.show(value, id: id, at: at, in: &pieces)
        case .outfit(let value): Self.show(value, id: id, at: at, in: &outfits)
        case .photo(let value): Self.show(value, id: id, at: at, in: &photos)
        case .comment(let value): Self.show(value, id: id, at: at, in: &comments)
        case .wish(let value): Self.show(value, id: id, at: at, in: &wishes)
        }
    }

    private static func show<Value>(_ value: Value, id: String, at: String, in records: inout [String: Record<Value>]) {
        var record = records[id] ?? Record(id: id, revision: 0, createdBy: Author.you.raw, updatedAt: at, value: value)
        record.value = value
        record.updatedAt = at
        records[id] = record
    }

    // MARK: What the screens show

    /// The pieces, most recently changed first.
    public var closet: [Record<Piece>] {
        newestFirst(Array(pieces.values))
    }

    /// The outfits: favourites first, then the rest, each most recently changed first.
    public var workbench: [Record<Outfit>] {
        let outfits = newestFirst(Array(outfits.values))
        return outfits.filter(\.value.favourite) + outfits.filter { !$0.value.favourite }
    }

    public func outfits(using pieceId: String) -> [Record<Outfit>] {
        newestFirst(outfits.values.filter { $0.value.pieceIds.contains(pieceId) })
    }

    /// Comments on a record, oldest first, as a conversation reads.
    public func comments(on subjectId: String) -> [Record<Comment>] {
        oldestFirst(comments.values.filter { $0.value.subjectId == subjectId })
    }

    /// A piece's, outfit's or suggestion's photos, oldest first.
    public func photos(of ownerId: String) -> [Record<Photo>] {
        oldestFirst(photos.values.filter { $0.value.ownerId == ownerId })
    }

    /// The photo a piece is shown with: the one the person chose, or its first.
    public func mainPhotoId(of piece: Record<Piece>) -> String? {
        let ids = photos(of: piece.id).map(\.id)
        return ids.first { $0 == piece.value.mainPhotoId } ?? ids.first
    }

    /// What's missing: the suggestions, most recently changed first.
    public var missing: [Record<Wish>] {
        newestFirst(Array(wishes.values))
    }

    // Ties (same instant) fall back to the id, so the order never jumps between refreshes.
    private func newestFirst<Value>(_ records: [Record<Value>]) -> [Record<Value>] {
        records.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    }

    private func oldestFirst<Value>(_ records: [Record<Value>]) -> [Record<Value>] {
        records.sorted { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }
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
        label = [data.title, data.name, data.text].compactMap { $0 }.first { !$0.isEmpty }
    }
}
