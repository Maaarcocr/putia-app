import PutiaCore
import SwiftUI

/// One outfit: the pieces large, why it should work, photos of it worn and the conversation about
/// it. The heart marks it a favourite.
struct OutfitView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        if let outfit = model.library.outfits[id] {
            content(outfit)
        } else {
            ContentUnavailableView(L10n.gone, systemImage: "rectangle.on.rectangle.angled")
        }
    }

    private func content(_ outfit: Record<Outfit>) -> some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Collage(pieceIds: outfit.value.pieceIds, height: 170)
                        .padding(16)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 24))
                    Text(outfit.value.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                    Byline(author: outfit.author)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let note = outfit.value.note {
                Section(L10n.why) { Text(note) }
            }
            Section(L10n.piecesTitle) {
                ForEach(outfit.value.pieceIds.compactMap { model.library.pieces[$0] }) { piece in
                    NavigationLink(value: Route.piece(piece.id)) { PieceRow(piece: piece) }
                }
            }
            PhotosSection(owner: .outfit, ownerId: id)
            CommentsSection(subjectKind: .outfit, subjectId: id)
            Section {
                Button(L10n.delete, role: .destructive) { confirmingDelete = true }
                    .alert(L10n.deleteOutfitTitle, isPresented: $confirmingDelete) {
                        Button(L10n.delete, role: .destructive) {
                            Task {
                                if await model.delete(.outfit, id: id, revision: outfit.revision) { dismiss() }
                            }
                        }
                        Button(L10n.cancel, role: .cancel) {}
                    } message: {
                        Text(L10n.deleteUndoable)
                    }
            }
        }
        .navigationTitle(outfit.value.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FavouriteButton(outfit: outfit)
                    .accessibilityIdentifier("outfit.favourite")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.edit) { editing = true }
                    .accessibilityIdentifier("outfit.edit")
                    .sheet(isPresented: $editing) {
                        OutfitEditor(outfit: outfit) { _ in }
                            .environment(model)
                    }
            }
        }
    }
}

/// The heart that marks an outfit a favourite, which puts it first.
struct FavouriteButton: View {
    @Environment(AppModel.self) private var model
    let outfit: Record<Outfit>

    var body: some View {
        let favourite = outfit.value.favourite
        Button {
            var value = outfit.value
            value.favourite.toggle()
            Task { await model.save(.outfit(value), id: outfit.id, revision: outfit.revision) }
        } label: {
            Label(favourite ? L10n.removeFavourite : L10n.addFavourite, systemImage: favourite ? "heart.fill" : "heart")
                .labelStyle(.iconOnly)
                .foregroundStyle(favourite ? Color.pink : Color.primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .sensoryFeedback(.impact, trigger: favourite)
    }
}
