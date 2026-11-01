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
                OutfitEditor(outfit: nil) { id in path.append(.outfit(id)) }
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
            Collage(pieceIds: outfit.value.pieceIds)
            Text(outfit.value.title)
                .font(.headline)
            if let note = outfit.value.note {
                Text(note)
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

/// A new outfit from owned pieces, or a change to an outfit's title and pieces.
struct OutfitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let outfit: Record<Outfit>?
    let saved: (String) -> Void
    @State private var title = ""
    @State private var chosen: [String] = []

    var body: some View {
        NavigationStack {
            List {
                TextField(L10n.outfitTitle, text: $title)
                    .accessibilityIdentifier("editor.title")
                Section(L10n.choosePieces) {
                    ForEach(model.library.closet) { piece in
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
            .navigationTitle(outfit == nil ? L10n.newOutfit : L10n.edit)
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
            .onAppear {
                guard let outfit else { return }
                title = outfit.value.title
                chosen = outfit.value.pieceIds
            }
        }
    }

    private func save() {
        var value = outfit?.value ?? Outfit(title: "", pieceIds: [])
        value.title = title.trimmed
        value.pieceIds = chosen
        Task {
            let id: String?
            if let outfit {
                id = await model.save(.outfit(value), id: outfit.id, revision: outfit.revision)?.id
            } else {
                id = await model.create(.outfit(value))
            }
            guard let id else { return }
            dismiss()
            saved(id)
        }
    }
}
