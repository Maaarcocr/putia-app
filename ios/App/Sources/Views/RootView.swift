import SwiftUI

nonisolated enum AppTab: Hashable, Sendable {
    case closet, outfits, missing, bench
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.closet

    var body: some View {
        TabView(selection: $tab) {
            Tab(L10n.tabCloset, systemImage: "hanger", value: AppTab.closet) {
                ClosetView()
            }
            Tab(L10n.tabOutfits, systemImage: "rectangle.on.rectangle.angled", value: AppTab.outfits) {
                OutfitsView()
            }
            Tab(L10n.tabMissing, systemImage: "sparkle.magnifyingglass", value: AppTab.missing) {
                MissingView()
            }
            Tab(L10n.tabBench, systemImage: "person.2", value: AppTab.bench) {
                BenchView()
            }
        }
        .task {
            // Pick up what an AI (or another device) changes while the app is open.
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .alert(L10n.notSaved, isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } }), presenting: model.problem) { _ in
            Button(L10n.ok) {}
        } message: { problem in
            Text(L10n.message(problem))
        }
    }
}
