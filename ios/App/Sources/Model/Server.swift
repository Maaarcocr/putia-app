import Foundation
import PutiaCore

nonisolated enum PhotoSize: String, Sendable {
    case thumb, full
}

/// A one-time code an AI signs in with.
nonisolated struct Pairing: Equatable, Sendable {
    let code: String
    let expiresAt: Date
}

nonisolated enum PairingStatus: Equatable, Sendable {
    case waiting
    case connected(agent: String)
    case expired
}

/// Why the server didn't do something.
nonisolated enum ServerError: Error {
    /// The record changed since it was read. `current` is the latest version (nil: it's gone).
    case conflict(current: Doc?)
    /// Refused or not valid, with the server's explanation (in English).
    case refused(String)
    /// The server no longer knows this phone's secret (the account was deleted, perhaps from
    /// another phone): sign in again.
    case signedOut
    /// No connection, or the server failed.
    case unavailable
}

/// The server's API for the app (server/src/app-api.ts).
protocol Server: AnyObject {
    /// The address to add in an AI app as a custom connector.
    var connectorURL: URL { get }
    /// Trades the one-time code from Sign in with Apple for the account and this phone's secret.
    func signIn(code: String) async throws -> Account
    func changes(since cursor: Int, account: Account) async throws -> Feed
    func save(_ content: Doc.Content, id: String, baseRevision: Int, note: String?, account: Account) async throws -> Doc
    func delete(_ kind: Kind, id: String, baseRevision: Int, account: Account) async throws -> Doc
    /// The latest changes, newest first.
    func history(account: Account) async throws -> [Change]
    func undo(_ seq: Int, account: Account) async throws -> Doc
    /// Saves a new photo record with its images: the full photo (JPEG) and its thumbnail.
    func addPhoto(_ photo: Photo, id: String, full: Data, thumb: Data, thumbType: String, account: Account) async throws -> Doc
    func photo(_ id: String, size: PhotoSize, account: Account) async throws -> Data
    func pairingCode(account: Account) async throws -> Pairing
    func pairingStatus(_ code: String, account: Account) async throws -> PairingStatus
    /// The names of the connected AIs.
    func agents(account: Account) async throws -> [String]
    func disconnectAgents(account: Account) async throws
    func deleteAccount(_ account: Account) async throws
}

final class HTTPServer: Server {
    private let base: URL

    init(host: String) {
        base = URL(string: "https://\(host)") ?? URL(string: "https://invalid.invalid")!
    }

    var connectorURL: URL { base.appending(path: "mcp") }

    func signIn(code: String) async throws -> Account {
        struct Session: Decodable {
            let accountId: String
            let secret: String
        }
        var request = URLRequest(url: base.appending(path: "v1/sign-in"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code])
        let session = try JSONDecoder().decode(Session.self, from: await perform(request))
        return Account(id: session.accountId, secret: session.secret)
    }

    func changes(since cursor: Int, account: Account) async throws -> Feed {
        try JSONDecoder().decode(Feed.self, from: await send("GET", "changes", query: ["since": "\(cursor)"], account: account))
    }

    func save(_ content: Doc.Content, id: String, baseRevision: Int, note: String?, account: Account) async throws -> Doc {
        struct Body: Encodable {
            let baseRevision: Int
            let data: Doc.Content
            let note: String?
        }
        let body = try JSONEncoder().encode(Body(baseRevision: baseRevision, data: content, note: note))
        let path = "docs/\(content.kind.rawValue)/\(id)"
        return try JSONDecoder().decode(Doc.self, from: await send("PUT", path, account: account, body: body, type: "application/json"))
    }

    func delete(_ kind: Kind, id: String, baseRevision: Int, account: Account) async throws -> Doc {
        let data = try await send("DELETE", "docs/\(kind.rawValue)/\(id)", query: ["base": "\(baseRevision)"], account: account)
        return try JSONDecoder().decode(Doc.self, from: data)
    }

    func history(account: Account) async throws -> [Change] {
        try JSONDecoder().decode([Change].self, from: await send("GET", "history", account: account))
    }

    func undo(_ seq: Int, account: Account) async throws -> Doc {
        try JSONDecoder().decode(Doc.self, from: await send("POST", "undo/\(seq)", account: account))
    }

    func addPhoto(_ photo: Photo, id: String, full: Data, thumb: Data, thumbType: String, account: Account) async throws -> Doc {
        // multipart/form-data: the record's data, then the two images.
        let boundary = "putia-\(UUID().uuidString)"
        var body = Data()
        func part(_ name: String, _ data: Data, type: String, filename: String? = nil) {
            let file = filename.map { "; filename=\"\($0)\"" } ?? ""
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\(file)\r\nContent-Type: \(type)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        let record = try JSONEncoder().encode(photo)
        part("data", record, type: "application/json")
        part("full", full, type: "image/jpeg", filename: "full")
        part("thumb", thumb, type: thumbType, filename: "thumb")
        body.append(Data("--\(boundary)--\r\n".utf8))
        let data = try await send("PUT", "photos/\(id)", account: account, body: body, type: "multipart/form-data; boundary=\(boundary)")
        return try JSONDecoder().decode(Doc.self, from: data)
    }

    func photo(_ id: String, size: PhotoSize, account: Account) async throws -> Data {
        try await send("GET", "photos/\(id)/\(size.rawValue)", account: account)
    }

    func pairingCode(account: Account) async throws -> Pairing {
        struct Body: Decodable {
            let code: String
            let expiresInSeconds: Double
        }
        let body = try JSONDecoder().decode(Body.self, from: await send("POST", "pairing", account: account))
        return Pairing(code: body.code, expiresAt: .now.addingTimeInterval(body.expiresInSeconds))
    }

    func pairingStatus(_ code: String, account: Account) async throws -> PairingStatus {
        struct Body: Decodable {
            let status: String
            let agent: String?
        }
        let body = try JSONDecoder().decode(Body.self, from: await send("GET", "pairing/\(code)", account: account))
        switch body.status {
        case "connected": return .connected(agent: body.agent ?? "")
        case "waiting": return .waiting
        default: return .expired
        }
    }

    func agents(account: Account) async throws -> [String] {
        struct Agent: Decodable {
            let name: String
        }
        return try JSONDecoder().decode([Agent].self, from: await send("GET", "agents", account: account)).map(\.name)
    }

    func disconnectAgents(account: Account) async throws {
        _ = try await send("DELETE", "agents", account: account)
    }

    func deleteAccount(_ account: Account) async throws {
        _ = try await send("DELETE", "", account: account)
    }

    private func send(
        _ method: String, _ path: String, query: [String: String] = [:], account: Account, body: Data? = nil, type: String? = nil
    ) async throws -> Data {
        var url = base.appending(path: "v1/accounts/\(account.id)/\(path)")
        if !query.isEmpty {
            url.append(queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(account.secret)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        if let type {
            request.setValue(type, forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw ServerError.unavailable
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 409:
            struct Conflict: Decodable {
                let current: Doc?
            }
            throw ServerError.conflict(current: (try? JSONDecoder().decode(Conflict.self, from: data))?.current)
        case 401:
            throw ServerError.signedOut
        case 400..<500:
            struct Refusal: Decodable {
                let error: String
                let problems: [String]?
            }
            let refusal = try? JSONDecoder().decode(Refusal.self, from: data)
            throw ServerError.refused(([refusal?.error ?? "\(status)"] + (refusal?.problems ?? [])).joined(separator: "\n"))
        default:
            throw ServerError.unavailable
        }
    }
}
