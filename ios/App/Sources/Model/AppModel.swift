import Foundation
import Observation
import PutiaCore
import PutiaImaging
import UIKit

/// Why something wasn't saved, for the alert.
nonisolated enum Problem: Equatable, Sendable {
    /// Someone (the AI, or another device) changed the record first.
    case conflict
    case offline
    case unreadablePhoto
    /// The server refused, with its explanation.
    case refused(String)
}

/// The bench as the app sees it. Records live on the server; the app shows the copy it last
/// loaded (also kept on disk) and sends every change to the server, which checks it against the
/// revision the app saw. There is no offline queue: a change either saves or says why not.
@Observable
final class AppModel {
    private(set) var library: Library
    /// The shared history, newest first, as last loaded.
    private(set) var history: [Change] = []
    /// The names of the connected AIs.
    private(set) var agents: [String] = []
    var problem: Problem?
    /// Preparing a photo (cut-out, colours) takes a moment.
    private(set) var working = false

    let server: any Server
    private(set) var account: Account
    private let accounts: any AccountStore
    private let cacheDirectory: URL?
    @ObservationIgnored private var thumbnails: [String: UIImage] = [:]

    /// - Parameter cacheDirectory: where to keep the last loaded records and photos; nil keeps nothing.
    init(server: any Server, accounts: any AccountStore, cacheDirectory: URL?) {
        self.server = server
        self.accounts = accounts
        self.cacheDirectory = cacheDirectory
        let account = accounts.load() ?? {
            let new = Account.make()
            accounts.save(new)
            return new
        }()
        self.account = account
        library = cacheDirectory
            .flatMap { try? Data(contentsOf: $0.appending(path: "library.json")) }
            .flatMap { try? JSONDecoder().decode(Library.self, from: $0) } ?? Library()
        if let cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheDirectory.appending(path: "photos"), withIntermediateDirectories: true)
        }
    }

    static func newId() -> String {
        UUID().uuidString.lowercased()
    }

    /// Today as the server stores days worn.
    static func today() -> String {
        Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    // MARK: Records

    /// Loads what changed on the bench since the last refresh, whoever changed it.
    func refresh() async {
        guard let feed = try? await server.changes(since: library.cursor, account: account),
              feed.cursor != library.cursor || !feed.docs.isEmpty
        else { return }
        library.apply(feed)
        saveCache()
    }

    /// Saves a record on top of `revision` (0 creates it). Returns the saved version, or nil
    /// when it wasn't saved; `problem` then says why.
    @discardableResult
    func save(_ content: Doc.Content, id: String, revision: Int, note: String? = nil) async -> Doc? {
        do {
            let doc = try await server.save(content, id: id, baseRevision: revision, note: note, account: account)
            library.apply(doc)
            saveCache()
            return doc
        } catch {
            report(error)
            return nil
        }
    }

    /// Creates a record. Returns its id.
    @discardableResult
    func create(_ content: Doc.Content) async -> String? {
        await save(content, id: Self.newId(), revision: 0)?.id
    }

    /// Deletes a record. It stays in the history and can be undone.
    func delete(_ kind: Kind, id: String, revision: Int) async -> Bool {
        do {
            library.apply(try await server.delete(kind, id: id, baseRevision: revision, account: account))
            saveCache()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func loadHistory() async {
        if let history = try? await server.history(account: account) {
            self.history = history
        }
    }

    func undo(_ change: Change) async {
        do {
            library.apply(try await server.undo(change.seq, account: account))
            saveCache()
        } catch {
            report(error)
        }
        await loadHistory()
    }

    private func report(_ error: any Error) {
        guard let error = error as? ServerError else {
            problem = .offline
            return
        }
        switch error {
        case .conflict(let current):
            // Show the latest version, so the person can redo their change on top of it.
            if let current { library.apply(current) }
            problem = .conflict
        case .refused(let message):
            problem = .refused(message)
        case .unavailable:
            problem = .offline
        }
    }

    private func saveCache() {
        guard let cacheDirectory, let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: cacheDirectory.appending(path: "library.json"), options: .atomic)
    }

    // MARK: Photos

    /// Adds a piece from a photo: cut out, measured and saved in a few seconds. Returns its id.
    func addPiece(from data: Data) async -> String? {
        working = true
        defer { working = false }
        guard let prepared = try? await Imaging.prepare(data, cutOut: true) else {
            problem = .unreadablePhoto
            return nil
        }
        // Suggestions from the phone, in the person's language. Material and cut are never guessed.
        var piece = Piece(swatches: prepared.swatches)
        if let category = prepared.category {
            piece[.category] = Attribute([L10n.category(category)], state: .suggested, by: Author.device.raw)
        }
        if let hex = prepared.swatches.first?.hex, let name = Swatches.nearestName(hex: hex) {
            piece[.colour] = Attribute([L10n.colourName(name)], state: .suggested, by: Author.device.raw)
        }
        // The piece, then its photo (which points at the piece), then the piece pointing at the photo.
        let pieceId = Self.newId()
        guard let created = await save(.piece(piece), id: pieceId, revision: 0),
              let photoId = await addPhoto(prepared, owner: .piece, ownerId: pieceId, role: .flat)
        else { return nil }
        piece.photoIds = [photoId]
        piece.heroPhotoId = photoId
        await save(.piece(piece), id: pieceId, revision: created.revision)
        return pieceId
    }

    /// Adds a photo of the person wearing an outfit.
    func addMirrorPhoto(_ data: Data, toOutfit outfitId: String) async {
        working = true
        defer { working = false }
        guard let prepared = try? await Imaging.prepare(data, cutOut: false) else {
            problem = .unreadablePhoto
            return
        }
        guard let photoId = await addPhoto(prepared, owner: .outfit, ownerId: outfitId, role: .mirror),
              let outfit = library.outfits[outfitId]
        else { return }
        var value = outfit.value
        value.photoIds.append(photoId)
        await save(.outfit(value), id: outfitId, revision: outfit.revision)
    }

    /// Adds an inspiration image. Returns the new reference's id.
    func addInspiration(_ data: Data) async -> String? {
        working = true
        defer { working = false }
        guard let prepared = try? await Imaging.prepare(data, cutOut: false) else {
            problem = .unreadablePhoto
            return nil
        }
        let referenceId = Self.newId()
        var reference = Reference(title: L10n.untitledInspiration)
        guard let created = await save(.reference(reference), id: referenceId, revision: 0),
              let photoId = await addPhoto(prepared, owner: .reference, ownerId: referenceId, role: .inspiration)
        else { return nil }
        reference.photoIds = [photoId]
        await save(.reference(reference), id: referenceId, revision: created.revision)
        return referenceId
    }

    private func addPhoto(_ prepared: PreparedPhoto, owner: Kind, ownerId: String, role: Photo.Role) async -> String? {
        let photoId = Self.newId()
        do {
            try await server.putPhoto(prepared.thumb, type: prepared.thumbType, id: photoId, size: .thumb, account: account)
            try await server.putPhoto(prepared.full, type: "image/jpeg", id: photoId, size: .full, account: account)
        } catch {
            report(error)
            return nil
        }
        keep(prepared.thumb, photoId, .thumb)
        keep(prepared.full, photoId, .full)
        let photo = Photo(ownerKind: owner, ownerId: ownerId, role: role, hasCutout: prepared.hasCutout, width: prepared.width, height: prepared.height)
        return await save(.photo(photo), id: photoId, revision: 0)?.id
    }

    /// A photo, from memory, the disk cache or the server.
    func image(_ photoId: String, size: PhotoSize) async -> UIImage? {
        let key = "\(photoId)-\(size.rawValue)"
        if let image = thumbnails[key] { return image }
        if let file = cacheFile(key), let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            if size == .thumb { thumbnails[key] = image }
            return image
        }
        guard let data = try? await server.photo(photoId, size: size, account: account) else { return nil }
        keep(data, photoId, size)
        return UIImage(data: data)
    }

    private func keep(_ data: Data, _ photoId: String, _ size: PhotoSize) {
        let key = "\(photoId)-\(size.rawValue)"
        // Only thumbnails stay in memory; full photos are large.
        if size == .thumb { thumbnails[key] = UIImage(data: data) }
        if let file = cacheFile(key) { try? data.write(to: file) }
    }

    private func cacheFile(_ key: String) -> URL? {
        cacheDirectory?.appending(path: "photos/\(key)")
    }

    // MARK: AI

    func pairingCode() async -> Pairing? {
        do {
            return try await server.pairingCode(account: account)
        } catch {
            report(error)
            return nil
        }
    }

    func pairingStatus(_ code: String) async -> PairingStatus? {
        try? await server.pairingStatus(code, account: account)
    }

    func loadAgents() async {
        if let agents = try? await server.agents(account: account) {
            self.agents = agents
        }
    }

    /// Cuts every AI off at once. Their changes stay.
    func disconnectAgents() async {
        do {
            try await server.disconnectAgents(account: account)
            agents = []
        } catch {
            report(error)
        }
    }

    /// Deletes the account on the server with every record and photo, and starts a new one.
    func deleteEverything() async {
        do {
            try await server.deleteAccount(account)
        } catch {
            report(error)
            return
        }
        accounts.delete()
        account = Account.make()
        accounts.save(account)
        library = Library()
        history = []
        agents = []
        thumbnails = [:]
        if let cacheDirectory {
            try? FileManager.default.removeItem(at: cacheDirectory)
            try? FileManager.default.createDirectory(at: cacheDirectory.appending(path: "photos"), withIntermediateDirectories: true)
        }
    }
}
