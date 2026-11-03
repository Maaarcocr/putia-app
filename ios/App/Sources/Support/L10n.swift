import Foundation
import PutiaCore

/// Every user-facing string in the app. Keys live in Localizable.xcstrings (English and Italian);
/// `scripts/check-strings.py` fails CI when a key here is missing a translation or unused, or when
/// a view passes a raw string literal instead of going through this file. Only keys go in quotes
/// here: strings built from several parts live in Format.swift.
enum L10n {
    // MARK: Tabs
    static var tabCloset: String { String(localized: "tab.closet") }
    static var tabOutfits: String { String(localized: "tab.outfits") }
    static var tabMissing: String { String(localized: "tab.missing") }
    static var tabBench: String { String(localized: "tab.bench") }

    // MARK: Common
    static var ok: String { String(localized: "common.ok") }
    static var cancel: String { String(localized: "common.cancel") }
    static var save: String { String(localized: "common.save") }
    static var delete: String { String(localized: "common.delete") }
    static var edit: String { String(localized: "common.edit") }
    static var done: String { String(localized: "common.done") }
    static var confirm: String { String(localized: "common.confirm") }
    static var undo: String { String(localized: "common.undo") }
    static var copy: String { String(localized: "common.copy") }
    static var copied: String { String(localized: "common.copied") }
    static var send: String { String(localized: "common.send") }
    static var gone: String { String(localized: "common.gone") }
    static var deleteUndoable: String { String(localized: "common.deleteUndoable") }
    static var preparingPhoto: String { String(localized: "common.preparingPhoto") }

    // MARK: Signing in
    static var signInTitle: String { String(localized: "signIn.title") }
    static var signInMessage: String { String(localized: "signIn.message") }
    static var signInFailed: String { String(localized: "signIn.failed") }

    // MARK: Problems
    static var notSaved: String { String(localized: "problem.title") }
    static func message(_ problem: Problem) -> String {
        switch problem {
        case .conflict: String(localized: "problem.conflict")
        case .offline: String(localized: "problem.offline")
        case .unreadablePhoto: String(localized: "problem.photo")
        case .refused(let reason): String(localized: "problem.refused \(reason)")
        }
    }

    // MARK: Who
    static var you: String { String(localized: "author.you") }
    static var madeByYou: String { String(localized: "author.madeByYou") }
    static func proposedBy(_ name: String) -> String { String(localized: "author.proposedBy \(name)") }
    static var confirmedByYou: String { String(localized: "provenance.confirmedByYou") }
    static func confirmedBy(_ name: String) -> String { String(localized: "provenance.confirmedBy \(name)") }
    static var suggestedByYou: String { String(localized: "provenance.suggestedByYou") }
    static func suggestedBy(_ name: String) -> String { String(localized: "provenance.suggestedBy \(name)") }

    // MARK: Closet
    static var closetEmptyTitle: String { String(localized: "closet.empty.title") }
    static var closetEmptyMessage: String { String(localized: "closet.empty.message") }
    static var addPiece: String { String(localized: "closet.add") }
    static var needsReview: String { String(localized: "closet.needsReview") }

    // MARK: Piece
    static var unnamed: String { String(localized: "piece.unnamed") }
    static var pieceName: String { String(localized: "piece.name") }
    static var tags: String { String(localized: "piece.tags") }
    static var tagsFooter: String { String(localized: "piece.tags.footer") }
    static var tagTitle: String { String(localized: "piece.tag.title") }
    static var notSet: String { String(localized: "piece.tag.notSet") }
    static var confirmAll: String { String(localized: "piece.confirmAll") }
    static var usedIn: String { String(localized: "piece.usedIn") }
    static var deletePieceTitle: String { String(localized: "piece.delete.title") }
    static func attribute(_ key: AttributeKey) -> String {
        switch key {
        case .category: String(localized: "attribute.category")
        case .colour: String(localized: "attribute.colour")
        case .material: String(localized: "attribute.material")
        case .cut: String(localized: "attribute.cut")
        case .pattern: String(localized: "attribute.pattern")
        case .season: String(localized: "attribute.season")
        }
    }

    // MARK: Photos
    static var photos: String { String(localized: "photos.title") }
    static var addPhoto: String { String(localized: "photos.add") }
    static var useAsMainPhoto: String { String(localized: "photos.useAsMain") }
    static var mainPhoto: String { String(localized: "photos.main") }
    static var deletePhotoTitle: String { String(localized: "photos.delete.title") }
    static var photosOfYou: String { String(localized: "photos.you.title") }
    static var photosOfYouFooter: String { String(localized: "photos.you.footer") }

    // MARK: Outfits
    static var favourite: String { String(localized: "outfit.favourite") }
    static var addFavourite: String { String(localized: "outfit.favourite.add") }
    static var removeFavourite: String { String(localized: "outfit.favourite.remove") }
    static var outfitsEmptyTitle: String { String(localized: "outfits.empty.title") }
    static var outfitsEmptyMessage: String { String(localized: "outfits.empty.message") }
    static var newOutfit: String { String(localized: "outfits.new") }
    static var outfitTitle: String { String(localized: "outfits.title") }
    static var choosePieces: String { String(localized: "outfits.choosePieces") }
    static var choosePiecesFooter: String { String(localized: "outfits.choosePieces.footer") }

    // MARK: Outfit
    static var why: String { String(localized: "outfit.why") }
    static var piecesTitle: String { String(localized: "outfit.pieces") }
    static var deleteOutfitTitle: String { String(localized: "outfit.delete.title") }

    // MARK: Comments
    static var comments: String { String(localized: "comments.title") }
    static var addComment: String { String(localized: "comments.add") }

    // MARK: What's missing
    static var missingEmptyTitle: String { String(localized: "missing.empty.title") }
    static var missingEmptyMessage: String { String(localized: "missing.empty.message") }
    static var addWish: String { String(localized: "missing.add") }

    // MARK: Suggestion
    static var wishName: String { String(localized: "wish.name") }
    static var problemHint: String { String(localized: "wish.problem.hint") }
    static var links: String { String(localized: "wish.links") }
    static var linksHint: String { String(localized: "wish.links.hint") }
    static var deleteWishTitle: String { String(localized: "wish.delete.title") }

    // MARK: Bench
    static var benchIntro: String { String(localized: "bench.intro") }
    static var aiHeader: String { String(localized: "bench.ai") }
    static var connectAI: String { String(localized: "bench.connect") }
    static var disconnectAll: String { String(localized: "bench.disconnect") }
    static var disconnectAllTitle: String { String(localized: "bench.disconnect.title") }
    static var disconnectAllMessage: String { String(localized: "bench.disconnect.message") }
    static var history: String { String(localized: "bench.history") }
    static var noHistory: String { String(localized: "bench.noHistory") }
    static var deleteEverything: String { String(localized: "bench.deleteEverything") }
    static var deleteEverythingTitle: String { String(localized: "bench.deleteEverything.title") }
    static var deleteEverythingFooter: String { String(localized: "bench.deleteEverything.footer") }
    static func op(_ op: Change.Op) -> String {
        switch op {
        case .create: String(localized: "op.create")
        case .update: String(localized: "op.update")
        case .delete: String(localized: "op.delete")
        case .undo: String(localized: "op.undo")
        }
    }
    static func kind(_ kind: Kind) -> String {
        switch kind {
        case .piece: String(localized: "kind.piece")
        case .outfit: String(localized: "kind.outfit")
        case .photo: String(localized: "kind.photo")
        case .comment: String(localized: "kind.comment")
        case .wish: String(localized: "kind.wish")
        }
    }

    // MARK: Connect an AI
    static var connectStep1: String { String(localized: "connect.step1") }
    static var connectStep2: String { String(localized: "connect.step2") }
    static var waitingForAI: String { String(localized: "connect.waiting") }
    static func connected(_ agent: String) -> String { String(localized: "connect.connected \(agent)") }
    static var newCode: String { String(localized: "connect.newCode") }
    static var connectFooter: String { String(localized: "connect.footer") }
}
