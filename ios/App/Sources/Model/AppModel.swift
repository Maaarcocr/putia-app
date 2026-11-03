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
/// revision the app saw. A change shows at once, while it's on its way. There is no offline queue:
/// a change either saves, or goes away and says why not.
@Observable
final class AppModel {
    /// What the screens show: the records as the server last sent them, with the person's changes
    /// that are still on their way on top.
    private(set) var library: Library
    /// The shared history, newest first, as last loaded.
    private(set) var history: [Change] = []
    /// The names of the connected AIs.
    private(set) var agents: [String] = []
    var problem: Problem?
    /// Preparing a photo (cut-out, colours) takes a moment.
    private(set) var working = false

    let server: any Server
    /// Nil until the person signs in with Apple; the screens ask them to.
    private(set) var account: Account?
    private let accounts: any AccountStore
    private let cacheDirectory: URL?
    @ObservationIgnored private var thumbnails: [String: UIImage] = [:]
    /// The records as the server last sent them.
    @ObservationIgnored private var saved: Library
    /// Each record's newest change that the server hasn't confirmed yet.
    @ObservationIgnored private var unsaved: [String: Unsaved] = [:]
    /// The records whose changes are being sent.
    @ObservationIgnored private var sending: [String: Task<Bool, Never>] = [:]

    private struct Unsaved: Equatable {
        var content: Doc.Content
        /// The revision it's based on.
        var base: Int
        var note: String?
    }

    /// - Parameter cacheDirectory: where to keep the last loaded records and photos; nil keeps nothing.
    init(server: any Server, accounts: any AccountStore, cacheDirectory: URL?) {
        self.server = server
        self.accounts = accounts
        self.cacheDirectory = cacheDirectory
        account = accounts.load()
        saved = cacheDirectory
            .flatMap { try? Data(contentsOf: $0.appending(path: "library.json")) }
            .flatMap { try? JSONDecoder().decode(Library.self, from: $0) } ?? Library()
        library = saved
        if let cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheDirectory.appending(path: "photos"), withIntermediateDirectories: true)
        }
    }

    static func newId() -> String {
        UUID().uuidString.lowercased()
    }

    // MARK: Signing in

    /// Signs in with the one-time code Sign in with Apple gave the app. Returns whether it worked.
    func signIn(code: String) async -> Bool {
        guard let account = try? await server.signIn(code: code) else { return false }
        accounts.save(account)
        self.account = account
        await refresh()
        return true
    }

    /// Forgets the account on this phone, and everything shown from it: back to signing in.
    private func forget() {
        accounts.delete()
        account = nil
        saved = Library()
        unsaved = [:]
        library = Library()
        history = []
        agents = []
        thumbnails = [:]
        if let cacheDirectory {
            try? FileManager.default.removeItem(at: cacheDirectory)
            try? FileManager.default.createDirectory(at: cacheDirectory.appending(path: "photos"), withIntermediateDirectories: true)
        }
    }

    // MARK: Records

    /// Loads what changed on the bench since the last refresh, whoever changed it.
    func refresh() async {
        guard let account else { return }
        let feed: Feed
        do {
            feed = try await server.changes(since: saved.cursor, account: account)
        } catch ServerError.signedOut {
            forget()
            return
        } catch {
            return
        }
        guard feed.cursor != saved.cursor || !feed.docs.isEmpty else { return }
        saved.apply(feed)
        show()
        saveCache()
    }

    /// Saves a record on top of `revision` (0 creates it). The change shows at once. Changes to one
    /// record are sent one after another: one made while the previous is on its way goes on top of
    /// it. Returns whether it was saved; if not, the record goes back to the server's version and
    /// `problem` says why.
    @discardableResult
    func save(_ content: Doc.Content, id: String, revision: Int, note: String? = nil) async -> Bool {
        unsaved[id] = Unsaved(content: content, base: revision, note: note)
        show()
        if let running = sending[id] { return await running.value }
        let task = Task { await send(id) }
        sending[id] = task
        return await task.value
    }

    /// Sends the record's newest change until the server has it.
    private func send(_ id: String) async -> Bool {
        defer { sending[id] = nil }
        guard let account else {
            unsaved[id] = nil
            show()
            return false
        }
        while let change = unsaved[id] {
            do {
                let doc = try await server.save(change.content, id: id, baseRevision: change.base, note: change.note, account: account)
                saved.apply(doc)
                if unsaved[id] == change {
                    unsaved[id] = nil
                } else {
                    unsaved[id]?.base = doc.revision
                }
                show()
                saveCache()
            } catch {
                // The record goes back to the server's version, without newer changes: they were
                // made on top of this one.
                unsaved[id] = nil
                report(error)
                show()
                return false
            }
        }
        return true
    }

    /// The records as the server last sent them, with the changes on their way on top.
    private func show() {
        var shown = saved
        for (id, change) in unsaved {
            shown.show(change.content, id: id)
        }
        library = shown
    }

    /// Creates a record. Returns its id.
    @discardableResult
    func create(_ content: Doc.Content) async -> String? {
        let id = Self.newId()
        return await save(content, id: id, revision: 0) ? id : nil
    }

    /// Deletes a record. It stays in the history and can be undone.
    @discardableResult
    func delete(_ kind: Kind, id: String, revision: Int) async -> Bool {
        guard let account else { return false }
        do {
            saved.apply(try await server.delete(kind, id: id, baseRevision: revision, account: account))
            unsaved[id] = nil
            show()
            saveCache()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func loadHistory() async {
        if let account, let history = try? await server.history(account: account) {
            self.history = history
        }
    }

    func undo(_ change: Change) async {
        guard let account else { return }
        do {
            saved.apply(try await server.undo(change.seq, account: account))
            show()
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
            if let current {
                saved.apply(current)
                show()
            }
            problem = .conflict
        case .refused(let message):
            problem = .refused(message)
        case .signedOut:
            forget()
        case .unavailable:
            problem = .offline
        }
    }

    private func saveCache() {
        guard let cacheDirectory, let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: cacheDirectory.appending(path: "library.json"), options: .atomic)
    }

    // MARK: Photos

    /// Adds a piece from a photo, cut out on the phone. Returns its id.
    func addPiece(from data: Data) async -> String? {
        guard let pieceId = await create(.piece(Piece())),
              await addPhoto(data, to: .piece, ownerId: pieceId, cutOut: true)
        else { return nil }
        return pieceId
    }

    /// Adds a photo to a piece, an outfit, a suggestion or the person. Returns whether it was saved.
    @discardableResult
    func addPhoto(_ data: Data, to owner: Photo.Owner, ownerId: String, cutOut: Bool = false) async -> Bool {
        guard let account else { return false }
        working = true
        defer { working = false }
        guard let prepared = try? await Imaging.prepare(data, cutOut: cutOut) else {
            problem = .unreadablePhoto
            return false
        }
        let photoId = Self.newId()
        do {
            // The record and its images are saved together.
            let doc = try await server.addPhoto(
                Photo(ownerKind: owner, ownerId: ownerId), id: photoId,
                full: prepared.full, thumb: prepared.thumb, thumbType: prepared.thumbType, account: account
            )
            keep(prepared.thumb, photoId, .thumb)
            keep(prepared.full, photoId, .full)
            saved.apply(doc)
            show()
            saveCache()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Makes a photo the piece's main one.
    func setMainPhoto(_ photoId: String, of pieceId: String) async {
        guard let piece = library.pieces[pieceId] else { return }
        var value = piece.value
        value.mainPhotoId = photoId
        await save(.piece(value), id: pieceId, revision: piece.revision)
    }

    /// A photo, from memory, the disk cache or the server.
    func image(_ photoId: String, size: PhotoSize) async -> UIImage? {
        let key = "\(photoId)-\(size.rawValue)"
        if let image = thumbnails[key] { return image }
        if let file = cacheFile(key), let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            if size == .thumb { thumbnails[key] = image }
            return image
        }
        guard let account, let data = try? await server.photo(photoId, size: size, account: account) else { return nil }
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
        guard let account else { return nil }
        do {
            return try await server.pairingCode(account: account)
        } catch {
            report(error)
            return nil
        }
    }

    func pairingStatus(_ code: String) async -> PairingStatus? {
        guard let account else { return nil }
        return try? await server.pairingStatus(code, account: account)
    }

    func loadAgents() async {
        if let account, let agents = try? await server.agents(account: account) {
            self.agents = agents
        }
    }

    /// Cuts every AI off at once. Their changes stay.
    func disconnectAgents() async {
        guard let account else { return }
        do {
            try await server.disconnectAgents(account: account)
            agents = []
        } catch {
            report(error)
        }
    }

    /// Deletes the account on the server with every record and photo, and signs out.
    func deleteEverything() async {
        guard let account else { return }
        do {
            try await server.deleteAccount(account)
        } catch {
            report(error)
            return
        }
        forget()
    }
}
