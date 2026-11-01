import SwiftUI

@main
struct PutiaApp: App {
    @State private var model: AppModel

    init() {
        // Composition root: the only place that picks the server and where the account is kept.
        // UI tests (-ui-testing) use an in-memory server with a sample wardrobe.
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let host = Bundle.main.object(forInfoDictionaryKey: "PutiaServerHost") as? String ?? ""
        let server: any Server = uiTesting ? MemoryServer.sample() : HTTPServer(host: host)
        let accounts: any AccountStore = uiTesting ? MemoryAccountStore() : KeychainAccountStore()
        let cache = uiTesting ? nil : URL.cachesDirectory.appending(path: "Putia")
        _model = State(initialValue: AppModel(server: server, accounts: accounts, cacheDirectory: cache))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
