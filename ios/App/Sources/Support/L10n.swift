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
    static var phone: String { String(localized: "author.phone") }
    static var madeByYou: String { String(localized: "author.madeByYou") }
    static func proposedBy(_ name: String) -> String { String(localized: "author.proposedBy \(name)") }
    static var confirmedByYou: String { String(localized: "provenance.confirmedByYou") }
    static func confirmedBy(_ name: String) -> String { String(localized: "provenance.confirmedBy \(name)") }
    static var suggestedByYou: String { String(localized: "provenance.suggestedByYou") }
    static var suggestedByPhone: String { String(localized: "provenance.suggestedByPhone") }
    static func suggestedBy(_ name: String) -> String { String(localized: "provenance.suggestedBy \(name)") }

    // MARK: Closet
    static var closetEmptyTitle: String { String(localized: "closet.empty.title") }
    static var closetEmptyMessage: String { String(localized: "closet.empty.message") }
    static var addPiece: String { String(localized: "closet.add") }
    static var retired: String { String(localized: "closet.retired") }
    static var needsReview: String { String(localized: "closet.needsReview") }

    // MARK: Piece
    static var unnamed: String { String(localized: "piece.unnamed") }
    static var pieceName: String { String(localized: "piece.name") }
    static var tags: String { String(localized: "piece.tags") }
    static var tagsFooter: String { String(localized: "piece.tags.footer") }
    static var tagTitle: String { String(localized: "piece.tag.title") }
    static var notSet: String { String(localized: "piece.tag.notSet") }
    static var colours: String { String(localized: "piece.colours") }
    static var coloursFooter: String { String(localized: "piece.colours.footer") }
    static var notes: String { String(localized: "piece.notes") }
    static var addNote: String { String(localized: "piece.addNote") }
    static var note: String { String(localized: "piece.note") }
    static var usedIn: String { String(localized: "piece.usedIn") }
    static var retire: String { String(localized: "piece.retire") }
    static var bringBack: String { String(localized: "piece.bringBack") }
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

    static func category(_ category: ClothingCategory) -> String {
        switch category {
        case .jacket: String(localized: "category.jacket")
        case .coat: String(localized: "category.coat")
        case .suit: String(localized: "category.suit")
        case .shirt: String(localized: "category.shirt")
        case .tshirt: String(localized: "category.tshirt")
        case .knitwear: String(localized: "category.knitwear")
        case .sweatshirt: String(localized: "category.sweatshirt")
        case .jeans: String(localized: "category.jeans")
        case .trousers: String(localized: "category.trousers")
        case .shorts: String(localized: "category.shorts")
        case .shoes: String(localized: "category.shoes")
        case .boots: String(localized: "category.boots")
        case .hat: String(localized: "category.hat")
        case .scarf: String(localized: "category.scarf")
        case .accessory: String(localized: "category.accessory")
        case .bag: String(localized: "category.bag")
        }
    }

    static func colourName(_ name: ColourName) -> String {
        switch name {
        case .black: String(localized: "colour.black")
        case .charcoal: String(localized: "colour.charcoal")
        case .grey: String(localized: "colour.grey")
        case .white: String(localized: "colour.white")
        case .cream: String(localized: "colour.cream")
        case .beige: String(localized: "colour.beige")
        case .camel: String(localized: "colour.camel")
        case .brown: String(localized: "colour.brown")
        case .navy: String(localized: "colour.navy")
        case .blue: String(localized: "colour.blue")
        case .lightBlue: String(localized: "colour.lightBlue")
        case .green: String(localized: "colour.green")
        case .olive: String(localized: "colour.olive")
        case .red: String(localized: "colour.red")
        case .burgundy: String(localized: "colour.burgundy")
        case .pink: String(localized: "colour.pink")
        case .orange: String(localized: "colour.orange")
        case .yellow: String(localized: "colour.yellow")
        case .purple: String(localized: "colour.purple")
        }
    }

    // MARK: Outfits
    static var stageLabel: String { String(localized: "outfits.stage") }
    static func stage(_ stage: Outfit.Stage) -> String {
        switch stage {
        case .proposed: String(localized: "stage.proposed")
        case .tried: String(localized: "stage.tried")
        case .favourite: String(localized: "stage.favourite")
        }
    }
    static var outfitsEmptyTitle: String { String(localized: "outfits.empty.title") }
    static var outfitsEmptyMessage: String { String(localized: "outfits.empty.message") }
    static var newOutfit: String { String(localized: "outfits.new") }
    static var outfitTitle: String { String(localized: "outfits.title") }
    static var choosePieces: String { String(localized: "outfits.choosePieces") }

    // MARK: Outfit
    static var woreToday: String { String(localized: "outfit.woreToday") }
    static var worn: String { String(localized: "outfit.worn") }
    static var why: String { String(localized: "outfit.why") }
    static var intent: String { String(localized: "outfit.intent") }
    static var silhouette: String { String(localized: "outfit.silhouette") }
    static var texture: String { String(localized: "outfit.texture") }
    static var effect: String { String(localized: "outfit.effect") }
    static var occasion: String { String(localized: "outfit.occasion") }
    static var uncertainty: String { String(localized: "outfit.uncertainty") }
    static func variationOf(_ title: String) -> String { String(localized: "outfit.variationOf \(title)") }
    static var piecesTitle: String { String(localized: "outfit.pieces") }
    static var swap: String { String(localized: "outfit.swap") }
    static var swapFooter: String { String(localized: "outfit.swap.footer") }
    static func swapped(_ old: String, _ new: String) -> String { String(localized: "outfit.swapped \(old) \(new)") }
    static var variations: String { String(localized: "outfit.variations") }
    static var compare: String { String(localized: "outfit.compare") }
    static var howItWent: String { String(localized: "outfit.howItWent") }
    static var addMirrorPhoto: String { String(localized: "outfit.addMirrorPhoto") }
    static var deleteOutfitTitle: String { String(localized: "outfit.delete.title") }
    static func feeling(_ feeling: Comment.Feeling) -> String {
        switch feeling {
        case .loved: String(localized: "feeling.loved")
        case .fine: String(localized: "feeling.fine")
        case .meh: String(localized: "feeling.meh")
        case .didntWork: String(localized: "feeling.didntWork")
        }
    }

    // MARK: Comments
    static var comments: String { String(localized: "comments.title") }
    static var addComment: String { String(localized: "comments.add") }
    static var reaction: String { String(localized: "comments.reaction") }
    static var assessment: String { String(localized: "comments.assessment") }

    // MARK: What's missing
    static var latestConclusion: String { String(localized: "missing.latestConclusion") }
    static var noConclusion: String { String(localized: "missing.noConclusion") }
    static func conclusion(_ conclusion: Review.Conclusion) -> String {
        switch conclusion {
        case .gaps: String(localized: "conclusion.gaps")
        case .tryCombinations: String(localized: "conclusion.tryCombinations")
        case .nothingNeeded: String(localized: "conclusion.nothingNeeded")
        }
    }
    static var shortlist: String { String(localized: "missing.shortlist") }
    static var shortlistFooter: String { String(localized: "missing.shortlist.footer") }
    static var addWish: String { String(localized: "missing.addWish") }
    static var decided: String { String(localized: "missing.decided") }
    static var inspiration: String { String(localized: "missing.inspiration") }
    static var addInspiration: String { String(localized: "missing.addInspiration") }
    static var untitledInspiration: String { String(localized: "missing.untitledInspiration") }

    // MARK: Shortlist entry
    static var wishName: String { String(localized: "wish.name") }
    static var problem: String { String(localized: "wish.problem") }
    static var problemHint: String { String(localized: "wish.problem.hint") }
    static var priorityLabel: String { String(localized: "wish.priority") }
    static var statusLabel: String { String(localized: "wish.status") }
    static var complements: String { String(localized: "wish.complements") }
    static var ownedAlternatives: String { String(localized: "wish.ownedAlternatives") }
    static var tryFirst: String { String(localized: "wish.tryFirst") }
    static var openLink: String { String(localized: "wish.openLink") }
    static var deleteWishTitle: String { String(localized: "wish.delete.title") }
    static func priority(_ priority: Wish.Priority) -> String {
        switch priority {
        case .low: String(localized: "priority.low")
        case .medium: String(localized: "priority.medium")
        case .high: String(localized: "priority.high")
        }
    }
    static func status(_ status: Wish.Status) -> String {
        switch status {
        case .considering: String(localized: "wishStatus.considering")
        case .tryingFirst: String(localized: "wishStatus.tryingFirst")
        case .dismissed: String(localized: "wishStatus.dismissed")
        case .bought: String(localized: "wishStatus.bought")
        }
    }

    // MARK: Inspiration
    static var referenceTitle: String { String(localized: "reference.title") }
    static var whatDrawsYou: String { String(localized: "reference.attraction") }
    static var attractionFooter: String { String(localized: "reference.attraction.footer") }
    static var noteHint: String { String(localized: "reference.note.hint") }
    static var translation: String { String(localized: "reference.translation") }
    static var noTranslation: String { String(localized: "reference.noTranslation") }
    static var deleteInspirationTitle: String { String(localized: "reference.delete.title") }
    static func attraction(_ attraction: Reference.Attraction) -> String {
        switch attraction {
        case .outline: String(localized: "attraction.outline")
        case .volume: String(localized: "attraction.volume")
        case .pattern: String(localized: "attraction.pattern")
        case .texture: String(localized: "attraction.texture")
        case .colour: String(localized: "attraction.colour")
        case .mood: String(localized: "attraction.mood")
        }
    }

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
        case .reference: String(localized: "kind.reference")
        case .wish: String(localized: "kind.wish")
        case .review: String(localized: "kind.review")
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
