import Foundation

// The shared records, mirroring server/src/schema.ts. The server validates every write, from the
// app and from AI alike; keep these shapes in step with it. Optional fields that are nil are left
// out of the JSON, which is what the server expects. Who made a record is kept beside its data
// (`Record.createdBy`), not in it.

public enum Kind: String, Codable, Sendable, CaseIterable {
    case piece, outfit, photo, comment, reference, wish, review
}

/// Who wrote something. Stored as "human" or "agent:<name>".
public enum Author: Equatable, Sendable {
    case you
    case agent(String)

    public init(_ raw: String) {
        self = raw == "human" ? .you : .agent(raw.hasPrefix("agent:") ? String(raw.dropFirst(6)) : raw)
    }

    public var raw: String {
        switch self {
        case .you: "human"
        case .agent(let name): "agent:\(name)"
        }
    }
}

/// A tag and who set it. Anything an AI sets is a suggestion until the person confirms it:
/// material and cut in particular can't be established from a photo.
public struct Attribute: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case suggested, confirmed }

    public var value: String
    public var state: State
    public var by: String

    public init(_ value: String, state: State, by: String) {
        self.value = value
        self.state = state
        self.by = by
    }

    public var author: Author { Author(by) }
}

/// The tags a piece can carry, in display order.
public enum AttributeKey: String, Sendable, CaseIterable {
    case category, colour, material, cut, pattern, season
}

/// A piece the person owns. Its photos are the photo records it owns.
public struct Piece: Codable, Equatable, Sendable {
    /// Empty until the person (or an AI) names it.
    public var name: String
    /// Keyed by `AttributeKey` raw values.
    public var attrs: [String: Attribute]
    /// The photo it's shown with; without one, its first photo.
    public var mainPhotoId: String?

    public init(name: String = "", attrs: [String: Attribute] = [:], mainPhotoId: String? = nil) {
        self.name = name
        self.attrs = attrs
        self.mainPhotoId = mainPhotoId
    }

    public subscript(key: AttributeKey) -> Attribute? {
        get { attrs[key.rawValue] }
        set { attrs[key.rawValue] = newValue }
    }

    /// Whether it has no tags yet, or any is still a suggestion.
    public var needsReview: Bool {
        attrs.isEmpty || attrs.values.contains { $0.state == .suggested }
    }
}

public struct Outfit: Codable, Equatable, Sendable {
    public var title: String
    /// Favourites come first in the list.
    public var favourite: Bool
    public var pieceIds: [String]
    /// Why it should work, and what a collage can't show.
    public var note: String?

    public init(title: String, favourite: Bool = false, pieceIds: [String], note: String? = nil) {
        self.title = title
        self.favourite = favourite
        self.pieceIds = pieceIds
        self.note = note
    }
}

/// A photo of a piece, of an outfit, an inspiration image, or of the person for virtual try-ons
/// (owner `.person`, owner id their account id).
public struct Photo: Codable, Equatable, Sendable {
    public enum Owner: String, Codable, Sendable { case piece, outfit, reference, person }

    public var ownerKind: Owner
    public var ownerId: String

    public init(ownerKind: Owner, ownerId: String) {
        self.ownerKind = ownerKind
        self.ownerId = ownerId
    }
}

public struct Comment: Codable, Equatable, Sendable {
    public var subjectKind: Kind
    public var subjectId: String
    public var text: String

    public init(subjectKind: Kind, subjectId: String, text: String) {
        self.subjectKind = subjectKind
        self.subjectId = subjectId
        self.text = text
    }
}

/// An inspiration image (its photo) and what the person likes about it. It never becomes a piece.
public struct Reference: Codable, Equatable, Sendable {
    public var title: String
    public var note: String?

    public init(title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }
}

/// A shortlist entry: something the person might acquire, and why.
public struct Wish: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable { case considering, bought, dismissed }

    public var name: String
    /// The problem it solves, in terms of what the person owns.
    public var note: String?
    public var link: String?
    public var status: Status

    public init(name: String, note: String? = nil, link: String? = nil, status: Status = .considering) {
        self.name = name
        self.note = note
        self.link = link
        self.status = status
    }
}

/// A conclusion about what's missing. "Nothing needed" is as valid as finding gaps.
public struct Review: Codable, Equatable, Sendable {
    public enum Conclusion: String, Codable, Sendable {
        case gaps
        case tryCombinations = "try-combinations"
        case nothingNeeded = "nothing-needed"
    }

    public var conclusion: Conclusion
    public var summary: String

    public init(conclusion: Conclusion, summary: String) {
        self.conclusion = conclusion
        self.summary = summary
    }
}
