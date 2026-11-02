import Foundation
import PutiaCore
import Testing
@testable import Putia

private func makeModel(_ server: MemoryServer = MemoryServer()) -> AppModel {
    AppModel(server: server, accounts: MemoryAccountStore(), cacheDirectory: nil)
}

@Test func savesAndLoadsRecords() async throws {
    let server = MemoryServer()
    let model = makeModel(server)
    let id = try #require(await model.create(.piece(Piece(name: "Navy chore jacket"))))
    #expect(model.library.pieces[id]?.value.name == "Navy chore jacket")

    // Another model on the same account sees it after a refresh.
    let other = makeModel(server)
    await other.refresh()
    #expect(other.library.pieces[id]?.revision == 1)
}

@Test func aStaleSaveShowsTheLatestVersionAndSaysWhy() async throws {
    let server = MemoryServer()
    let model = makeModel(server)
    let id = try #require(await model.create(.piece(Piece(name: "Jacket"))))
    // An AI renames it meanwhile.
    try server.write(.piece(Piece(name: "Chore jacket")), id: id, baseRevision: 1, actor: "agent:Claude")

    let saved = await model.save(.piece(Piece(name: "My jacket")), id: id, revision: 1)
    #expect(!saved)
    #expect(model.problem == .conflict)
    #expect(model.library.pieces[id]?.value.name == "Chore jacket")
    #expect(model.library.pieces[id]?.author == .you, "the creator stays the person")
}

@Test func quickChangesToOneRecordGoOnTopOfEachOther() async throws {
    let server = MemoryServer()
    let model = makeModel(server)
    var piece = Piece(name: "Jacket")
    piece[.material] = Attribute("wool", state: .suggested, by: "agent:Claude")
    piece[.cut] = Attribute("boxy", state: .suggested, by: "agent:Claude")
    let id = try #require(await model.create(.piece(piece)))

    // Two confirms tapped before the first is saved: both read revision 1.
    piece[.material]?.state = .confirmed
    let first = Task { await model.save(.piece(piece), id: id, revision: 1) }
    piece[.cut]?.state = .confirmed
    let second = Task { await model.save(.piece(piece), id: id, revision: 1) }
    #expect(await first.value)
    #expect(await second.value)
    #expect(model.problem == nil)

    let other = makeModel(server)
    await other.refresh()
    #expect(other.library.pieces[id]?.value.needsReview == false, "both confirms reached the server")
}

@Test func aChangeThatIsNotSavedGoesBack() async throws {
    let server = MemoryServer()
    let model = makeModel(server)
    let id = try #require(await model.create(.piece(Piece(name: "Jacket"))))
    server.failing = true
    #expect(await model.save(.piece(Piece(name: "Renamed")), id: id, revision: 1) == false)
    #expect(model.problem == .offline)
    #expect(model.library.pieces[id]?.value.name == "Jacket")
}

@Test func undoesAChange() async throws {
    let server = MemoryServer()
    let model = makeModel(server)
    let id = try #require(await model.create(.piece(Piece(name: "Jacket"))))
    await model.save(.piece(Piece(name: "Renamed")), id: id, revision: 1)
    await model.loadHistory()
    let rename = try #require(model.history.first)
    #expect(rename.op == .update)

    await model.undo(rename)
    #expect(model.library.pieces[id]?.value.name == "Jacket")
    #expect(model.history.first?.op == .undo)
}

@Test func offlineSavesSayWhy() async {
    let server = MemoryServer()
    server.failing = true
    let model = makeModel(server)
    #expect(await model.create(.piece(Piece(name: "Jacket"))) == nil)
    #expect(model.problem == .offline)
}

@Test func deletingEverythingStartsAFreshAccount() async throws {
    let server = MemoryServer()
    let model = makeModel(server)
    let before = model.account
    _ = try #require(await model.create(.piece(Piece(name: "Jacket"))))
    await model.deleteEverything()
    #expect(model.library.pieces.isEmpty)
    #expect(model.account != before)
}

@Test func anyPhotoOfAPieceCanBeItsMainOne() async throws {
    let server = MemoryServer()
    let model = makeModel(server)
    let pieceId = AppModel.newId(), ownId = AppModel.newId(), foundId = AppModel.newId()
    try server.write(.piece(Piece(name: "Jacket")), id: pieceId, baseRevision: 0, actor: "human")
    try server.write(.photo(Photo(ownerKind: .piece, ownerId: pieceId)), id: ownId, baseRevision: 0, actor: "human")
    try server.write(.photo(Photo(ownerKind: .piece, ownerId: pieceId)), id: foundId, baseRevision: 0, actor: "agent:Claude")
    await model.refresh()
    var piece = try #require(model.library.pieces[pieceId])
    #expect(model.library.mainPhotoId(of: piece) == ownId, "the first photo until the person picks one")

    await model.setMainPhoto(foundId, of: pieceId)
    piece = try #require(model.library.pieces[pieceId])
    #expect(model.library.mainPhotoId(of: piece) == foundId)
    // Deleting it puts the first photo back.
    #expect(await model.delete(.photo, id: foundId, revision: 1))
    #expect(model.library.mainPhotoId(of: piece) == ownId)
}

@Test func describesProvenanceAndHistory() {
    #expect(L10n.provenance(Attribute("wool", state: .suggested, by: "agent:Claude")).contains("Claude"))
    #expect(L10n.author("human") == L10n.you)
    #expect(L10n.madeBy(.agent("Claude")).contains("Claude"))
    let change = Change(seq: 1, kind: .outfit, recordId: "x", op: .create, actor: "agent:Claude", at: "2026-11-01T10:00:00.000Z")
    #expect(L10n.changeLine(change).hasPrefix("Claude"))
}
