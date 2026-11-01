import PhotosUI
import PutiaCore
import SwiftUI

/// One outfit: the pieces large, its stage, why it should work, swaps, reactions, mirror photos
/// and the conversation about it.
struct OutfitView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var pick: PhotosPickerItem?
    @State private var variation: String?
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
                Collage(pieceIds: outfit.value.items.map(\.pieceId), height: 170)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                Picker(L10n.stageLabel, selection: Binding(get: { outfit.value.stage }, set: { stage in update { $0.stage = stage } })) {
                    ForEach(Outfit.Stage.allCases, id: \.self) { stage in
                        Text(L10n.stage(stage)).tag(stage)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("outfit.stage")
                Button(L10n.woreToday, systemImage: "calendar.badge.checkmark") {
                    update {
                        $0.wornOn = Array(($0.wornOn + [AppModel.today()]).suffix(60))
                        if $0.stage == .proposed { $0.stage = .tried }
                    }
                }
                .disabled(outfit.value.wornOn.contains(AppModel.today()))
                if !outfit.value.wornOn.isEmpty {
                    LabeledText(label: L10n.worn, text: outfit.value.wornOn.sorted(by: >).joined(separator: ", "))
                }
                Text(L10n.madeBy(outfit.author))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.why) {
                LabeledText(label: L10n.intent, text: outfit.value.intent)
                LabeledText(label: L10n.silhouette, text: outfit.value.rationale?.silhouette)
                LabeledText(label: L10n.texture, text: outfit.value.rationale?.texture)
                LabeledText(label: L10n.effect, text: outfit.value.rationale?.effect)
                LabeledText(label: L10n.occasion, text: outfit.value.occasion)
                LabeledText(label: L10n.uncertainty, text: outfit.value.uncertainty)
                if let parentId = outfit.value.parentId, let parent = model.library.outfits[parentId] {
                    NavigationLink(value: Route.compare(parentId, id)) {
                        LabeledText(label: L10n.variationOf(parent.value.title), text: outfit.value.changed ?? "")
                    }
                }
            }
            Section {
                ForEach(Array(outfit.value.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        if let piece = model.library.pieces[item.pieceId] {
                            NavigationLink(value: Route.piece(piece.id)) { PieceRow(piece: piece) }
                        }
                        Menu {
                            ForEach(model.library.ownedPieces.filter { candidate in !outfit.value.items.contains { $0.pieceId == candidate.id } }) { candidate in
                                Button(L10n.name(of: candidate.value)) { swap(item.pieceId, for: candidate.id) }
                            }
                        } label: {
                            Label(L10n.swap, systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("outfit.swap")
                    }
                }
            } header: {
                Text(L10n.piecesTitle)
            } footer: {
                Text(L10n.swapFooter)
            }
            let variations = model.library.variations(of: id)
            if !variations.isEmpty {
                Section(L10n.variations) {
                    ForEach(variations) { variation in
                        NavigationLink(variation.value.changed ?? variation.value.title, value: Route.compare(id, variation.id))
                    }
                }
            }
            Section(L10n.howItWent) {
                HStack {
                    ForEach(Comment.Feeling.allCases, id: \.self) { feeling in
                        Button {
                            react(feeling)
                        } label: {
                            Text(L10n.feeling(feeling))
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("outfit.react.\(feeling.rawValue)")
                    }
                }
                if !outfit.value.photoIds.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(outfit.value.photoIds, id: \.self) { photoId in
                                PhotoView(photoId: photoId)
                                    .frame(width: 96, height: 128)
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }
                }
                PhotosPicker(selection: $pick, matching: .images) {
                    Label(L10n.addMirrorPhoto, systemImage: "camera")
                }
                if model.working {
                    ProgressView(L10n.preparingPhoto)
                }
            }
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
        .navigationDestination(item: $variation) { variationId in
            CompareView(leftId: id, rightId: variationId)
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            pick = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await model.addMirrorPhoto(data, toOutfit: id)
            }
        }
    }

    /// Swapping makes a new version, so the two can be compared; the original stays as it was.
    private func swap(_ oldId: String, for newId: String) {
        guard let outfit = model.library.outfits[id] else { return }
        let changed = L10n.swapped(name(oldId), name(newId))
        let copy = outfit.value.swapping(oldId, for: newId, parentId: id, changed: String(changed.prefix(200)))
        Task { variation = await model.create(.outfit(copy)) }
    }

    private func react(_ feeling: Comment.Feeling) {
        let reaction = Comment(subjectKind: .outfit, subjectId: id, kind: .reaction, text: L10n.feeling(feeling), feeling: feeling)
        Task { await model.create(.comment(reaction)) }
    }

    private func name(_ pieceId: String) -> String {
        model.library.pieces[pieceId].map { L10n.name(of: $0.value) } ?? ""
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

/// Two versions side by side: an outfit and a variation with one thing changed.
struct CompareView: View {
    @Environment(AppModel.self) private var model
    let leftId: String
    let rightId: String

    var body: some View {
        ScrollView {
            if let changed = model.library.outfits[rightId]?.value.changed {
                Text(changed)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            HStack(alignment: .top, spacing: 12) {
                column(leftId)
                column(rightId)
            }
            .padding()
        }
        .navigationTitle(L10n.compare)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func column(_ outfitId: String) -> some View {
        if let outfit = model.library.outfits[outfitId] {
            NavigationLink(value: Route.outfit(outfitId)) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(outfit.value.items.enumerated()), id: \.offset) { _, item in
                        PieceImage(piece: model.library.pieces[item.pieceId])
                            .frame(height: 110)
                    }
                    Text(outfit.value.title)
                        .font(.subheadline.bold())
                    Text(L10n.stage(outfit.value.stage))
                        .font(.caption)
                    let feelings = model.library.comments(on: outfitId).compactMap(\.value.feeling)
                    if !feelings.isEmpty {
                        Text(feelings.map(L10n.feeling).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}
