import Foundation
import PutiaCore

/// Strings put together from several translated parts.
extension L10n {
    /// Who wrote something: "You" or the AI's name.
    static func author(_ raw: String) -> String {
        switch Author(raw) {
        case .you: you
        case .agent(let name): name
        }
    }

    static func madeBy(_ author: Author) -> String {
        author == .you ? madeByYou : proposedBy(L10n.author(author.raw))
    }

    /// Who set a tag, and whether the person confirmed it.
    static func provenance(_ attribute: Attribute) -> String {
        switch (attribute.state, attribute.author) {
        case (.confirmed, .you): confirmedByYou
        case (.confirmed, let author): confirmedBy(L10n.author(author.raw))
        case (.suggested, .you): suggestedByYou
        case (.suggested, let author): suggestedBy(L10n.author(author.raw))
        }
    }

    static func name(of piece: Piece) -> String {
        piece.name.isEmpty ? unnamed : piece.name
    }

    /// "Claude · Created · Outfit · 5 minutes ago"
    static func changeLine(_ change: Change) -> String {
        var parts = [author(change.actor), op(change.op), kind(change.kind)]
        if let date = try? Date(change.at, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}
