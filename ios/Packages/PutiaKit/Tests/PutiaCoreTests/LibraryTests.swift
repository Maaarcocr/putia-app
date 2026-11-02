import Foundation
import PutiaCore
import Testing

// The JSON below is what the server sends (server/src/store.ts `Doc` and `Change`).

private let jacketId = "00000000-0000-4000-8000-000000000001"
private let trousersId = "00000000-0000-4000-8000-000000000002"
private let outfitId = "00000000-0000-4000-8000-000000000003"

private func doc(_ kind: String, _ id: String, revision: Int = 1, deleted: Bool = false, by: String = "human", at: String = "2026-11-01T10:00:00.000Z", data: String) -> String {
    """
    {"kind":"\(kind)","id":"\(id)","revision":\(revision),"deleted":\(deleted),"data":\(data),
     "createdBy":"\(by)","createdAt":"\(at)","updatedAt":"\(at)"}
    """
}

private func feed(_ cursor: Int, _ docs: [String]) throws -> Feed {
    try JSONDecoder().decode(Feed.self, from: Data("{\"cursor\":\(cursor),\"docs\":[\(docs.joined(separator: ","))]}".utf8))
}

private let jacket = doc("piece", jacketId, data: """
    {"name":"Navy chore jacket",
     "attrs":{"category":{"value":"jacket","state":"confirmed","by":"human"},
              "colour":{"value":"navy","state":"suggested","by":"agent:Claude"}}}
    """)
private let trousers = doc("piece", trousersId, at: "2026-11-01T11:00:00.000Z", data: """
    {"name":"Grey trousers","attrs":{}}
    """)
private let outfit = doc("outfit", outfitId, by: "agent:Claude", data: """
    {"title":"Soft workwear","favourite":false,"pieceIds":["\(jacketId)","\(trousersId)"],"note":"Boxy over straight"}
    """)

@Test func appliesTheServerFeed() throws {
    var library = Library()
    library.apply(try feed(3, [jacket, trousers, outfit]))

    #expect(library.cursor == 3)
    #expect(library.closet.map(\.value.name) == ["Grey trousers", "Navy chore jacket"])
    let piece = try #require(library.pieces[jacketId])
    #expect(piece.value[.category] == Attribute("jacket", state: .confirmed, by: "human"))
    #expect(piece.value[.colour]?.author == .agent("Claude"))
    #expect(piece.value.needsReview)
    #expect(library.outfits(using: trousersId).map(\.id) == [outfitId])
    #expect(library.workbench.first?.author == .agent("Claude"))
}

@Test func favouriteOutfitsComeFirst() throws {
    let outfit = { (id: String, favourite: Bool, at: String) in
        doc("outfit", id, at: at, data: """
            {"title":"\(id)","favourite":\(favourite),"pieceIds":["\(jacketId)"]}
            """)
    }
    let older = "00000000-0000-4000-8000-0000000000c1"
    let newer = "00000000-0000-4000-8000-0000000000c2"
    let favourite = "00000000-0000-4000-8000-0000000000c3"
    var library = Library()
    library.apply(try feed(3, [
        outfit(older, false, "2026-11-01T10:00:00.000Z"),
        outfit(newer, false, "2026-11-01T12:00:00.000Z"),
        outfit(favourite, true, "2026-11-01T09:00:00.000Z"),
    ]))
    #expect(library.workbench.map(\.id) == [favourite, newer, older])
}

@Test func keepsTheNewestRevisionAndDropsDeletedRecords() throws {
    var library = Library()
    library.apply(try feed(3, [jacket, trousers, outfit]))
    let renamed = doc("piece", jacketId, revision: 2, data: """
        {"name":"Chore jacket","attrs":{}}
        """)
    library.apply(try feed(4, [renamed]))
    // An older copy arriving late (a slow save response, say) doesn't win.
    library.apply(try feed(4, [jacket]))
    #expect(library.pieces[jacketId]?.value.name == "Chore jacket")

    let deleted = doc("outfit", outfitId, revision: 2, deleted: true, data: """
        {"title":"Soft workwear","favourite":false,"pieceIds":["\(jacketId)"]}
        """)
    library.apply(try feed(5, [deleted]))
    #expect(library.outfits.isEmpty)
    #expect(library.cursor == 5)
}

@Test func showsAChangeBeforeTheServerHasIt() throws {
    var library = Library()
    library.apply(try feed(3, [jacket]))
    library.show(.piece(Piece(name: "Chore jacket")), id: jacketId)
    #expect(library.pieces[jacketId]?.value.name == "Chore jacket")
    #expect(library.pieces[jacketId]?.revision == 1, "it keeps the revision the change is based on")

    let newId = "00000000-0000-4000-8000-0000000000d1"
    library.show(.piece(Piece(name: "Linen shirt")), id: newId)
    #expect(library.pieces[newId]?.author == .you)
    #expect(library.closet.first?.id == newId, "a new piece shows first")
}

@Test func encodesOnlyWhatTheServerAccepts() throws {
    var piece = Piece(name: "Shirt")
    piece[.material] = Attribute("linen", state: .confirmed, by: "human")
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Doc.Content.piece(piece))) as? [String: Any])
    #expect(json["mainPhotoId"] == nil, "nil optionals are left out")
    #expect(((json["attrs"] as? [String: Any])?["material"] as? [String: Any])?["value"] as? String == "linen")
}

@Test func aPieceIsShownWithItsMainPhotoOrItsFirst() throws {
    let first = "00000000-0000-4000-8000-00000000000d"
    let second = "00000000-0000-4000-8000-00000000000e"
    let photo = { (id: String, at: String) in
        doc("photo", id, at: at, data: """
            {"ownerKind":"piece","ownerId":"\(jacketId)"}
            """)
    }
    var library = Library()
    library.apply(try feed(3, [jacket, photo(first, "2026-11-01T10:00:00.000Z"), photo(second, "2026-11-01T12:00:00.000Z")]))
    #expect(library.photos(of: jacketId).map(\.id) == [first, second])
    #expect(library.mainPhotoId(of: try #require(library.pieces[jacketId])) == first)

    var chosen = try #require(library.pieces[jacketId])
    chosen.value.mainPhotoId = second
    #expect(library.mainPhotoId(of: chosen) == second)
    // A main photo that was deleted falls back to the first.
    chosen.value.mainPhotoId = "00000000-0000-4000-8000-00000000000f"
    #expect(library.mainPhotoId(of: chosen) == first)
}

@Test func photosOfThePersonBelongToTheirAccount() throws {
    let accountId = "00000000-0000-4000-8000-0000000000aa"
    let photoId = "00000000-0000-4000-8000-0000000000ab"
    var library = Library()
    library.apply(try feed(1, [doc("photo", photoId, data: """
        {"ownerKind":"person","ownerId":"\(accountId)"}
        """)]))
    #expect(library.photos(of: accountId).map(\.value) == [Photo(ownerKind: .person, ownerId: accountId)])
}

@Test func shortlistHoldsWhatIsStillBeingConsidered() throws {
    var library = Library()
    let wish = { (id: String, status: String) in
        doc("wish", id, data: """
            {"name":"\(id)","status":"\(status)"}
            """)
    }
    library.apply(try feed(3, [
        wish("00000000-0000-4000-8000-00000000000a", "considering"),
        wish("00000000-0000-4000-8000-00000000000b", "bought"),
    ]))
    #expect(library.shortlist.map(\.value.status) == [.considering])
    #expect(library.decidedWishes.map(\.value.status) == [.bought])
}

@Test func decodesHistoryWithALabel() throws {
    let json = """
        [{"seq":7,"kind":"outfit","id":"\(outfitId)","revision":1,"op":"create","actor":"agent:Claude",
          "before":null,"after":{"deleted":false,"data":{"title":"Soft workwear","favourite":false}},
          "note":"Built around the jacket","undoes":null,"at":"2026-11-01T10:00:00.000Z"}]
        """
    let change = try #require(try JSONDecoder().decode([Change].self, from: Data(json.utf8)).first)
    #expect(change.label == "Soft workwear")
    #expect(change.author == .agent("Claude"))
    #expect(change.op == .create)
    #expect(change.note == "Built around the jacket")
}
