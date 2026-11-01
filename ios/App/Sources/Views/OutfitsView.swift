import PutiaCore
import SwiftUI

/// The workbench: outfits as large cards, by stage. Proposed ones come from the person or an AI;
/// only the person moves them to tried or favourite.
struct OutfitsView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var stage = Outfit.Stage.proposed
    @State private var creating = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                Picker(L10n.stageLabel, selection: $stage) {
                    ForEach(Outfit.Stage.allCases, id: \.self) { stage in
                        Text(L10n.stage(stage)).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityIdentifier("outfits.stage")
                let outfits = model.library.outfits(in: stage)
                if outfits.isEmpty {
                    ContentUnavailableView(L10n.outfitsEmptyTitle, systemImage: "rectangle.on.rectangle.angled", description: Text(L10n.outfitsEmptyMessage))
                }
                LazyVStack(spacing: 16) {
                    ForEach(outfits) { outfit in
                        NavigationLink(value: Route.outfit(outfit.id)) {
                            OutfitCard(outfit: outfit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("outfits.card")
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.tabOutfits)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.newOutfit, systemImage: "plus") { creating = true }
                        .accessibilityIdentifier("outfits.add")
                }
            }
            .sheet(isPresented: $creating) {
                OutfitEditor { id in path.append(.outfit(id)) }
                    .environment(model)
            }
            .refreshable { await model.refresh() }
            .routes()
        }
    }
}

private struct OutfitCard: View {
    let outfit: Record<Outfit>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Collage(pieceIds: outfit.value.items.map(\.pieceId))
            Text(outfit.value.title)
                .font(.headline)
            if let intent = outfit.value.intent {
                Text(intent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(L10n.madeBy(outfit.author))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}

/// A new outfit from owned pieces.
private struct OutfitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let created: (String) -> Void
    @State private var title = ""
    @State private var chosen: [String] = []

    var body: some View {
        NavigationStack {
            List {
                TextField(L10n.outfitTitle, text: $title)
                    .accessibilityIdentifier("editor.title")
                Section(L10n.choosePieces) {
                    ForEach(model.library.ownedPieces) { piece in
                        Button {
                            if let index = chosen.firstIndex(of: piece.id) {
                                chosen.remove(at: index)
                            } else if chosen.count < 12 {
                                chosen.append(piece.id)
                            }
                        } label: {
                            HStack {
                                PieceRow(piece: piece)
                                Spacer()
                                if chosen.contains(piece.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("editor.piece")
                    }
                }
            }
            .navigationTitle(L10n.newOutfit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) { save() }
                        .disabled(title.trimmed.isEmpty || chosen.isEmpty)
                        .accessibilityIdentifier("editor.save")
                }
            }
        }
    }

    private func save() {
        let outfit = Outfit(title: title.trimmed, items: chosen.map { Outfit.Item(pieceId: $0) })
        Task {
            guard let id = await model.create(.outfit(outfit)) else { return }
            dismiss()
            created(id)
        }
    }
}
