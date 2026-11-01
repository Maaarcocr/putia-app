import PutiaCore
import SwiftUI

/// One outfit: the pieces large, its stage, why it should work, photos of it worn and the
/// conversation about it.
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
                Collage(pieceIds: outfit.value.pieceIds, height: 170)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                Picker(L10n.stageLabel, selection: Binding(get: { outfit.value.stage }, set: { stage in update { $0.stage = stage } })) {
                    ForEach(Outfit.Stage.allCases, id: \.self) { stage in
                        Text(L10n.stage(stage)).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("outfit.stage")
                Text(L10n.madeBy(outfit.author))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Button(L10n.edit) { editing = true }
                    .accessibilityIdentifier("outfit.edit")
                    .sheet(isPresented: $editing) {
                        OutfitEditor(outfit: outfit) { _ in }
                            .environment(model)
                    }
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
    }

    /// Changes the latest version of the outfit and saves it.
    private func update(_ change: (inout Outfit) -> Void) {
        guard let outfit = model.library.outfits[id] else { return }
        var value = outfit.value
        change(&value)
        guard value != outfit.value else { return }
        Task { await model.save(.outfit(value), id: id, revision: outfit.revision) }
    }
}
