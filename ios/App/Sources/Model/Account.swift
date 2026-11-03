import Foundation
import os
import Security

private let logger = Logger(subsystem: "dev.putia.app", category: "Account")

/// This phone's account on the server: the account's id and this phone's secret, which the server
/// gives the app when the person signs in with Apple. Every request carries the secret.
nonisolated struct Account: Codable, Equatable, Sendable {
    let id: String
    let secret: String
}

/// Where the account is kept.
protocol AccountStore: AnyObject {
    func load() -> Account?
    func save(_ account: Account)
    func delete()
}

/// The Keychain item syncs through iCloud Keychain, so a new phone keeps the same bench.
final class KeychainAccountStore: AccountStore {
    private let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.putia.account",
        kSecAttrAccount as String: "account",
    ]

    func load() -> Account? {
        var query = base
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    func save(_ account: Account) {
        delete()
        guard let data = try? JSONEncoder().encode(account) else { return }
        var item = base
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed: \(status, privacy: .public)")
        }
    }

    func delete() {
        var query = base
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }
}

final class MemoryAccountStore: AccountStore {
    var account: Account?
    init(_ account: Account? = nil) {
        self.account = account
    }
    func load() -> Account? { account }
    func save(_ account: Account) { self.account = account }
    func delete() { account = nil }
}
