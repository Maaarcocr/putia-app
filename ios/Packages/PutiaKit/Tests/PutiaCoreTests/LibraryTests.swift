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
    {"name":"Navy chore jacket","status":"owned","swatches":[{"hex":"#1f2a44"}],"notes":[],"photoIds":[],
     "attrs":{"category":{"value":"jacket","state":"confirmed","by":"human"},
              "colour":{"value":["navy","black"],"state":"suggested","by":"agent:Claude"}}}
    """)
private let trousers = doc("piece", trousersId, at: "2026-11-01T11:00:00.000Z", data: """
    {"name":"Grey trousers","status":"owned","attrs":{},"swatches":[],"notes":[],"photoIds":[]}
    """)
private let outfit = doc("outfit", outfitId, by: "agent:Claude", data: """
    {"title":"Soft workwear","stage":"proposed","photoIds":[],"wornOn":[],
     "items":[{"pieceId":"\(jacketId)","role":"outerwear"},{"pieceId":"\(trousersId)","role":"trousers"}],
     "rationale":{"silhouette":"Boxy over straight"}}
    """)

@Test func appliesTheServerFeed() throws {
    var library = Library()
    library.apply(try feed(3, [jacket, trousers, outfit]))

    #expect(library.cursor == 3)
    #expect(library.ownedPieces.map(\.value.name) == ["Grey trousers", "Navy chore jacket"])
    let piece = try #require(library.pieces[jacketId])
    #expect(piece.value[.category] == Attribute(["jacket"], state: .confirmed, by: "human"))
    #expect(piece.value[.colour]?.text == "navy, black")
    #expect(piece.value[.colour]?.author == .agent("Claude"))
    #expect(piece.value.needsReview)
    #expect(library.outfits(using: trousersId).map(\.id) == [outfitId])
    #expect(library.outfits(in: .proposed).first?.author == .agent("Claude"))
}

@Test func keepsTheNewestRevisionAndDropsDeletedRecords() throws {
    var library = Library()
    library.apply(try feed(3, [jacket, trousers, outfit]))
    let renamed = doc("piece", jacketId, revision: 2, data: """
        {"name":"Chore jacket","status":"owned","attrs":{},"swatches":[],"notes":[],"photoIds":[]}
        """)
    library.apply(try feed(4, [renamed]))
    // An older copy arriving late (a slow save response, say) doesn't win.
    library.apply(try feed(4, [jacket]))
    #expect(library.pieces[jacketId]?.value.name == "Chore jacket")

    let deleted = doc("outfit", outfitId, revision: 2, deleted: true, data: """
        {"title":"Soft workwear","stage":"proposed","photoIds":[],"wornOn":[],"items":[{"pieceId":"\(jacketId)","role":"other"}]}
        """)
    library.apply(try feed(5, [deleted]))
    #expect(library.outfits.isEmpty)
    #expect(library.cursor == 5)
}

@Test func encodesOnlyWhatTheServerAccepts() throws {
    var piece = Piece(name: "Shirt")
    piece[.material] = Attribute(["linen"], state: .confirmed, by: "human")
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Doc.Content.piece(piece))) as? [String: Any])
    #expect(json["heroPhotoId"] == nil, "nil optionals are left out")
    let material = try #require((json["attrs"] as? [String: Any])?["material"] as? [String: Any])
    #expect(material["value"] as? String == "linen", "a single value is sent as a string")

    let wish = Wish(name: "Knit polo", status: .tryingFirst)
    let wishJSON = String(decoding: try JSONEncoder().encode(wish), as: UTF8.self)
    #expect(wishJSON.contains("\"trying-first\""))
    let reaction = Comment(subjectKind: .outfit, subjectId: outfitId, kind: .reaction, text: "Too stiff", feeling: .didntWork)
    #expect(String(decoding: try JSONEncoder().encode(reaction), as: UTF8.self).contains("\"didnt-work\""))
}

@Test func swappingAPieceMakesAVariation() {
    let original = Outfit(title: "Soft workwear", stage: .favourite, items: [Outfit.Item(pieceId: jacketId, role: .outerwear)], wornOn: ["2026-10-30"])
    let variation = original.swapping(jacketId, for: trousersId, parentId: outfitId, changed: "Jacket → trousers")
    #expect(variation.items == [Outfit.Item(pieceId: trousersId, role: .outerwear)])
    #expect(variation.stage == .proposed)
    #expect(variation.parentId == outfitId)
    #expect(variation.wornOn.isEmpty)
}

@Test func shortlistPutsOpenEntriesByPriority() throws {
    var library = Library()
    let wish = { (id: String, status: String, priority: String) in
        doc("wish", id, data: """
            {"name":"\(id)","status":"\(status)","priority":"\(priority)","complementsPieceIds":[],"alternativesOwnedIds":[],"outfitsToTryIds":[]}
            """)
    }
    library.apply(try feed(3, [
        wish("00000000-0000-4000-8000-00000000000a", "considering", "low"),
        wish("00000000-0000-4000-8000-00000000000b", "trying-first", "high"),
        wish("00000000-0000-4000-8000-00000000000c", "bought", "high"),
    ]))
    #expect(library.shortlist.map(\.value.priority) == [.high, .low])
    #expect(library.decidedWishes.map(\.value.status) == [.bought])
}

@Test func findsPhotosAnAIFoundOnline() throws {
    let webId = "00000000-0000-4000-8000-00000000000d"
    let found = doc("photo", webId, by: "agent:Claude", data: """
        {"ownerKind":"piece","ownerId":"\(jacketId)","role":"flat","hasCutout":false,"source":"https://shop.example/chore-jacket"}
        """)
    let own = doc("photo", "00000000-0000-4000-8000-00000000000e", data: """
        {"ownerKind":"piece","ownerId":"\(jacketId)","role":"flat","hasCutout":true}
        """)
    var library = Library()
    library.apply(try feed(3, [jacket, found, own]))
    #expect(library.webPhotos(of: jacketId).map(\.id) == [webId], "the person's own photo isn't from the web")
    #expect(library.webPhotos(of: jacketId).first?.value.source == "https://shop.example/chore-jacket")
    #expect(library.webPhotos(of: trousersId).isEmpty)
}

@Test func decodesHistoryWithALabel() throws {
    let json = """
        [{"seq":7,"kind":"outfit","id":"\(outfitId)","revision":1,"op":"create","actor":"agent:Claude",
          "before":null,"after":{"deleted":false,"data":{"title":"Soft workwear","stage":"proposed"}},
          "note":"Built around the jacket","undoes":null,"at":"2026-11-01T10:00:00.000Z"}]
        """
    let change = try #require(try JSONDecoder().decode([Change].self, from: Data(json.utf8)).first)
    #expect(change.label == "Soft workwear")
    #expect(change.author == .agent("Claude"))
    #expect(change.op == .create)
    #expect(change.note == "Built around the jacket")
}

@Test func measuresDominantColoursOfTheCutOut() {
    let navy: [UInt8] = [31, 42, 68, 255]
    let cream: [UInt8] = [236, 226, 200, 255]
    let background: [UInt8] = [255, 0, 0, 0]
    let pixels = Array([[UInt8]](repeating: navy, count: 70).joined())
        + Array([[UInt8]](repeating: cream, count: 25).joined())
        + Array([[UInt8]](repeating: background, count: 400).joined())
    let swatches = Swatches.dominant(rgba: pixels)
    #expect(swatches.map(\.hex) == ["#1f2a44", "#ece2c8"], "transparent background is ignored")
    #expect(Swatches.nearestName(hex: "#1f2a44") == .navy)
    #expect(Swatches.nearestName(hex: "#f0f0f0") == .white)
    #expect(Swatches.nearestName(hex: "nonsense") == nil)
}
