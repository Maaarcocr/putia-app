import PutiaCore
import SwiftUI

/// The workbench: outfits as large cards, favourites first. They come from the person or an AI.
struct OutfitsView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var creating = false

    var body: some View {
        NavigationStack(path: $path) {
            let outfits = model.library.workbench
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(outfits) { outfit in
                        NavigationLink(value: Route.outfit(outfit.id)) {
                            OutfitCard(outfit: outfit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("outfits.card")
                        .overlay(alignment: .topTrailing) {
                            FavouriteButton(outfit: outfit)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .padding(10)
                                .accessibilityIdentifier("outfits.favourite")
                        }
                    }
                }
                .padding()
                .animation(.spring, value: outfits.map(\.id))
            }
            .overlay {
                if outfits.isEmpty {
                    ContentUnavailableView(L10n.outfitsEmptyTitle, systemImage: "rectangle.on.rectangle.angled", description: Text(L10n.outfitsEmptyMessage))
                }
            }
            .navigationTitle(L10n.tabOutfits)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.newOutfit, systemImage: "plus") { creating = true }
                        .accessibilityIdentifier("outfits.add")
                        .sheet(isPresented: $creating) {
                            OutfitEditor(outfit: nil) { id in path.append(.outfit(id)) }
                                .environment(model)
                        }
                }
            }
            .refreshable { await model.refresh() }
            .routes()
        }
    }
}

private struct OutfitCard: View {
    let outfit: Record<Outfit>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Collage(pieceIds: outfit.value.pieceIds)
                .padding(.bottom, 8)
            Text(outfit.value.title)
                .font(.title3.bold())
            if let note = outfit.value.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Byline(author: outfit.author)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }
}

/// A new outfit from owned pieces, or a change to an outfit's title and pieces. The numbers show
/// the order the collage lays them out in.
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
                Section {
                    ForEach(model.library.closet) { piece in
                        let index = chosen.firstIndex(of: piece.id)
                        Button {
                            if let index {
                                chosen.remove(at: index)
                            } else if chosen.count < 12 {
                                chosen.append(piece.id)
                            }
                        } label: {
                            HStack {
                                PieceRow(piece: piece)
                                Spacer()
                                Image(systemName: index.map { "\($0 + 1).circle.fill" } ?? "circle")
                                    .imageScale(.large)
                                    .foregroundStyle(index == nil ? Color.secondary : Color.accentColor)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .tint(.primary)
                        .accessibilityAddTraits(index == nil ? [] : .isSelected)
                        .accessibilityIdentifier("editor.piece")
                    }
                } header: {
                    Text(L10n.choosePieces)
                } footer: {
                    Text(L10n.choosePiecesFooter)
                }
            }
            .sensoryFeedback(.selection, trigger: chosen)
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
                id = await model.save(.outfit(value), id: outfit.id, revision: outfit.revision) ? outfit.id : nil
            } else {
                id = await model.create(.outfit(value))
            }
            guard let id else { return }
            dismiss()
            saved(id)
        }
    }
}
