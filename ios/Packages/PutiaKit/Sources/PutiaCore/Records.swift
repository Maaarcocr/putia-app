import Foundation

// The shared records, mirroring server/src/schema.ts. The server validates every write, from the
// app and from AI alike; keep these shapes in step with it. Optional fields that are nil are left
// out of the JSON, which is what the server expects.

public enum Kind: String, Codable, Sendable, CaseIterable {
    case piece, outfit, photo, comment, reference, wish, review
}

/// Who wrote something. Stored as "human", "device" (measured on the phone) or "agent:<name>".
public enum Author: Equatable, Sendable {
    case you
    case device
    case agent(String)

    public init(_ raw: String) {
        switch raw {
        case "human": self = .you
        case "device": self = .device
        default: self = .agent(raw.hasPrefix("agent:") ? String(raw.dropFirst(6)) : raw)
        }
    }

    public var raw: String {
        switch self {
        case .you: "human"
        case .device: "device"
        case .agent(let name): "agent:\(name)"
        }
    }
}

/// A tag with provenance. Anything set by an AI or measured on the phone is a suggestion until
/// the person confirms it: material and cut in particular can't be established from a photo.
public struct Attribute: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case suggested, confirmed }

    /// One value or several (two colours, say). The server accepts a string or a list.
    public var values: [String]
    public var state: State
    public var by: String

    public init(_ values: [String], state: State, by: String) {
        self.values = values
        self.state = state
        self.by = by
    }

    public var text: String { values.joined(separator: ", ") }
    public var author: Author { Author(by) }

    private enum CodingKeys: String, CodingKey { case value, state, by }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let one = try? container.decode(String.self, forKey: .value) {
            values = [one]
        } else {
            values = try container.decode([String].self, forKey: .value)
        }
        state = try container.decode(State.self, forKey: .state)
        by = try container.decode(String.self, forKey: .by)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if values.count == 1 {
            try container.encode(values[0], forKey: .value)
        } else {
            try container.encode(values, forKey: .value)
        }
        try container.encode(state, forKey: .state)
        try container.encode(by, forKey: .by)
    }
}

/// The tags a piece can carry, in display order.
public enum AttributeKey: String, Sendable, CaseIterable {
    case category, colour, material, cut, pattern, season
}

/// A colour measured on the phone from the cut-out. It describes the photo, not the fabric.
public struct Swatch: Codable, Equatable, Sendable {
    public var hex: String
    public var name: String?

    public init(hex: String, name: String? = nil) {
        self.hex = hex
        self.name = name
    }
}

public struct Note: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var by: String
    public var at: String

    public init(id: String, text: String, by: String, at: String) {
        self.id = id
        self.text = text
        self.by = by
        self.at = at
    }
}

public struct Piece: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case owned, retired }

    /// Empty until the person (or an AI) names it.
    public var name: String
    public var status: Status
    /// Keyed by `AttributeKey` raw values.
    public var attrs: [String: Attribute]
    public var swatches: [Swatch]
    public var notes: [Note]
    public var photoIds: [String]
    public var heroPhotoId: String?

    public init(
        name: String = "", status: Status = .owned, attrs: [String: Attribute] = [:], swatches: [Swatch] = [],
        notes: [Note] = [], photoIds: [String] = [], heroPhotoId: String? = nil
    ) {
        self.name = name
        self.status = status
        self.attrs = attrs
        self.swatches = swatches
        self.notes = notes
        self.photoIds = photoIds
        self.heroPhotoId = heroPhotoId
    }

    public subscript(key: AttributeKey) -> Attribute? {
        get { attrs[key.rawValue] }
        set { attrs[key.rawValue] = newValue }
    }

    /// Whether any tag is missing or still a suggestion.
    public var needsReview: Bool {
        attrs.isEmpty || attrs.values.contains { $0.state == .suggested }
    }
}

public struct Outfit: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable, CaseIterable { case proposed, tried, favourite }
    public enum Role: String, Codable, Sendable { case top, layer, outerwear, trousers, shoes, accessory, other }

    public struct Item: Codable, Equatable, Sendable {
        public var pieceId: String
        public var role: Role

        public init(pieceId: String, role: Role = .other) {
            self.pieceId = pieceId
            self.role = role
        }
    }

    /// Why the pieces work together, or what they test.
    public struct Rationale: Codable, Equatable, Sendable {
        public var silhouette: String?
        public var texture: String?
        public var effect: String?

        public init(silhouette: String? = nil, texture: String? = nil, effect: String? = nil) {
            self.silhouette = silhouette
            self.texture = texture
            self.effect = effect
        }
    }

    public var title: String
    public var stage: Stage
    public var items: [Item]
    /// The intended effect, in ordinary language.
    public var intent: String?
    public var rationale: Rationale?
    /// What a collage or photo can't establish (drape, scale, true colour, comfort).
    public var uncertainty: String?
    public var occasion: String?
    /// A controlled comparison: the outfit this was varied from, and the one thing that changed.
    public var parentId: String?
    public var changed: String?
    /// The inspiration this outfit translates, if any.
    public var referenceId: String?
    public var photoIds: [String]
    /// Days worn, as YYYY-MM-DD.
    public var wornOn: [String]

    public init(
        title: String, stage: Stage = .proposed, items: [Item], intent: String? = nil, rationale: Rationale? = nil,
        uncertainty: String? = nil, occasion: String? = nil, parentId: String? = nil, changed: String? = nil,
        referenceId: String? = nil, photoIds: [String] = [], wornOn: [String] = []
    ) {
        self.title = title
        self.stage = stage
        self.items = items
        self.intent = intent
        self.rationale = rationale
        self.uncertainty = uncertainty
        self.occasion = occasion
        self.parentId = parentId
        self.changed = changed
        self.referenceId = referenceId
        self.photoIds = photoIds
        self.wornOn = wornOn
    }

    /// A copy with one piece swapped, recorded as a variation of `parentId`.
    public func swapping(_ oldPieceId: String, for newPieceId: String, parentId: String, changed: String) -> Outfit {
        var variation = Outfit(title: title, items: items, intent: intent, occasion: occasion, parentId: parentId, changed: changed)
        variation.items = items.map { $0.pieceId == oldPieceId ? Item(pieceId: newPieceId, role: $0.role) : $0 }
        return variation
    }
}

public struct Photo: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case flat, worn, mirror, detail, inspiration }

    /// The piece, outfit or reference the photo belongs to.
    public var ownerKind: Kind
    public var ownerId: String
    public var role: Role
    /// Whether the thumbnail is a cut-out on a transparent background.
    public var hasCutout: Bool
    public var width: Int?
    public var height: Int?
    /// Where an AI found this photo of the piece's product online. Nil for the person's own photos.
    public var source: String?

    public init(ownerKind: Kind, ownerId: String, role: Role, hasCutout: Bool, width: Int? = nil, height: Int? = nil, source: String? = nil) {
        self.ownerKind = ownerKind
        self.ownerId = ownerId
        self.role = role
        self.hasCutout = hasCutout
        self.width = width
        self.height = height
        self.source = source
    }
}

public struct Comment: Codable, Equatable, Sendable {
    /// A plain comment, a reaction after trying an outfit, or an AI's assessment.
    public enum Form: String, Codable, Sendable { case comment, reaction, assessment }
    public enum Feeling: String, Codable, Sendable, CaseIterable {
        case loved, fine, meh
        case didntWork = "didnt-work"
    }

    public var subjectKind: Kind
    public var subjectId: String
    public var kind: Form
    public var text: String
    public var feeling: Feeling?
    public var by: String

    public init(subjectKind: Kind, subjectId: String, kind: Form = .comment, text: String, feeling: Feeling? = nil, by: String = Author.you.raw) {
        self.subjectKind = subjectKind
        self.subjectId = subjectId
        self.kind = kind
        self.text = text
        self.feeling = feeling
        self.by = by
    }
}

/// An inspiration image. It never becomes a piece: it shows a relationship the person likes.
public struct Reference: Codable, Equatable, Sendable {
    public enum Attraction: String, Codable, Sendable, CaseIterable { case outline, volume, pattern, texture, colour, mood }

    /// How owned pieces could carry the same relationship.
    public struct Translation: Codable, Equatable, Sendable {
        public var text: String
        public var pieceIds: [String]
        public var outfitIds: [String]

        public init(text: String, pieceIds: [String] = [], outfitIds: [String] = []) {
            self.text = text
            self.pieceIds = pieceIds
            self.outfitIds = outfitIds
        }
    }

    public var title: String
    public var photoIds: [String]
    public var attraction: [Attraction]
    public var note: String?
    public var translation: Translation?

    public init(title: String, photoIds: [String] = [], attraction: [Attraction] = [], note: String? = nil, translation: Translation? = nil) {
        self.title = title
        self.photoIds = photoIds
        self.attraction = attraction
        self.note = note
        self.translation = translation
    }
}

/// A shortlist entry: something the person might acquire, and why.
public struct Wish: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case considering
        case tryingFirst = "trying-first"
        case dismissed, bought
    }

    public enum Priority: String, Codable, Sendable, CaseIterable {
        case low, medium, high

        var rank: Int { Priority.allCases.firstIndex(of: self) ?? 0 }
    }

    public var name: String
    public var description: String?
    public var status: Status
    public var priority: Priority
    /// The problem it solves, in terms of existing outfits.
    public var problem: String?
    public var complementsPieceIds: [String]
    /// Pieces already owned that might do the same job.
    public var alternativesOwnedIds: [String]
    public var outfitsToTryIds: [String]
    public var link: String?

    public init(
        name: String, description: String? = nil, status: Status = .considering, priority: Priority = .medium, problem: String? = nil,
        complementsPieceIds: [String] = [], alternativesOwnedIds: [String] = [], outfitsToTryIds: [String] = [], link: String? = nil
    ) {
        self.name = name
        self.description = description
        self.status = status
        self.priority = priority
        self.problem = problem
        self.complementsPieceIds = complementsPieceIds
        self.alternativesOwnedIds = alternativesOwnedIds
        self.outfitsToTryIds = outfitsToTryIds
        self.link = link
    }

    /// Still being weighed, rather than decided.
    public var isOpen: Bool { status == .considering || status == .tryingFirst }
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
    public var scope: String?

    public init(conclusion: Conclusion, summary: String, scope: String? = nil) {
        self.conclusion = conclusion
        self.summary = summary
        self.scope = scope
    }
}
