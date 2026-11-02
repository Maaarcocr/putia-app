import PutiaCore
import SwiftUI

/// One piece: its photos, name, tags with who set each, the outfits it's in and the
/// conversation about it.
struct PieceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var name = ""
    @State private var editing: AttributeKey?
    @State private var tagDraft = ""
    @State private var confirmingDelete = false

    var body: some View {
        if let piece = model.library.pieces[id] {
            content(piece)
        } else {
            ContentUnavailableView(L10n.gone, systemImage: "hanger")
        }
    }

    private func content(_ piece: Record<Piece>) -> some View {
        let suggested = AttributeKey.allCases.filter { piece.value[$0]?.state == .suggested }
        return List {
            Section {
                VStack(spacing: 14) {
                    PieceImage(piece: piece)
                        .frame(height: 300)
                    TextField(L10n.pieceName, text: $name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .submitLabel(.done)
                        .onSubmit { update { $0.name = name.trimmed } }
                        .accessibilityIdentifier("piece.name")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(AttributeKey.allCases, id: \.self) { key in
                    TagRow(key: key, attribute: piece.value[key]) {
                        update { confirm(key, in: &$0) }
                    } edit: {
                        tagDraft = piece.value[key]?.value ?? ""
                        editing = key
                    }
                }
            } header: {
                HStack {
                    Text(L10n.tags)
                    Spacer()
                    if suggested.count > 1 {
                        Button(L10n.confirmAll) {
                            update { value in suggested.forEach { confirm($0, in: &value) } }
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .tint(.orange)
                        .accessibilityIdentifier("piece.confirmAll")
                    }
                }
            } footer: {
                Text(L10n.tagsFooter)
            }
            .alert(L10n.tagTitle, isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), presenting: editing) { key in
                TextField(L10n.attribute(key), text: $tagDraft)
                Button(L10n.save) { saveTag(key) }
                Button(L10n.cancel, role: .cancel) {}
            } message: { key in
                Text(L10n.attribute(key))
            }
            PhotosSection(owner: .piece, ownerId: id)
            let outfits = model.library.outfits(using: id)
            if !outfits.isEmpty {
                Section(L10n.usedIn) {
                    ForEach(outfits) { outfit in
                        NavigationLink(value: Route.outfit(outfit.id)) {
                            HStack {
                                Text(outfit.value.title)
                                if outfit.value.favourite {
                                    Spacer()
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.pink)
                                        .accessibilityLabel(L10n.favourite)
                                }
                            }
                        }
                    }
                }
            }
            CommentsSection(subjectKind: .piece, subjectId: id)
            Section {
                Button(L10n.delete, role: .destructive) { confirmingDelete = true }
                    .alert(L10n.deletePieceTitle, isPresented: $confirmingDelete) {
                        Button(L10n.delete, role: .destructive) {
                            Task {
                                if await model.delete(.piece, id: id, revision: piece.revision) { dismiss() }
                            }
                        }
                        Button(L10n.cancel, role: .cancel) {}
                    } message: {
                        Text(L10n.deleteUndoable)
                    }
            }
        }
        .navigationTitle(L10n.name(of: piece.value))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: suggested.count) { old, new in new < old }
        .onAppear { name = piece.value.name }
        .onChange(of: piece.value.name) { _, newName in name = newName }
    }

    /// A tag the person confirms becomes theirs.
    private func confirm(_ key: AttributeKey, in piece: inout Piece) {
        piece[key]?.state = .confirmed
        piece[key]?.by = Author.you.raw
    }

    /// A tag the person sets or edits is confirmed by them.
    private func saveTag(_ key: AttributeKey) {
        let value = tagDraft.trimmed
        update { $0[key] = value.isEmpty ? nil : Attribute(value, state: .confirmed, by: Author.you.raw) }
    }

    /// Changes the latest version of the piece and saves it.
    private func update(_ change: (inout Piece) -> Void) {
        guard let piece = model.library.pieces[id] else { return }
        var value = piece.value
        change(&value)
        guard value != piece.value else { return }
        Task { await model.save(.piece(value), id: id, revision: piece.revision) }
    }
}

/// A tag: its name and value, and for a suggestion who made it and a button to confirm it.
/// Tapping the row edits the tag.
private struct TagRow: View {
    let key: AttributeKey
    let attribute: Attribute?
    let confirm: () -> Void
    let edit: () -> Void

    var body: some View {
        let suggested = attribute?.state == .suggested
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.attribute(key))
                // A tag the person set needs no note; anyone else's says who.
                if let attribute, suggested || attribute.author != .you {
                    Credit(text: L10n.provenance(attribute), symbol: attribute.author.symbol)
                        .font(.caption)
                        .foregroundStyle(suggested ? Color.orange : Color.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(attribute?.value ?? L10n.notSet)
                    .foregroundStyle(attribute == nil ? .tertiary : .secondary)
                    .multilineTextAlignment(.trailing)
                if suggested {
                    Button(L10n.confirm, action: confirm)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                        .accessibilityIdentifier("piece.confirm.\(key.rawValue)")
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: edit)
        .animation(.default, value: attribute)
    }
}
