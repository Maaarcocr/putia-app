import PutiaCore
import SwiftUI

/// One piece: its photo, name, tags with where each came from, colours, notes, the outfits it is
/// in and the conversation about it.
struct PieceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var name = ""
    @State private var editing: AttributeKey?
    @State private var tagDraft = ""
    @State private var addingNote = false
    @State private var noteDraft = ""
    @State private var confirmingDelete = false

    var body: some View {
        if let piece = model.library.pieces[id] {
            content(piece)
        } else {
            ContentUnavailableView(L10n.gone, systemImage: "hanger")
        }
    }

    private func content(_ piece: Record<Piece>) -> some View {
        List {
            Section {
                PieceImage(piece: piece)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                TextField(L10n.pieceName, text: $name)
                    .font(.title3.bold())
                    .submitLabel(.done)
                    .onSubmit { update { $0.name = name.trimmed } }
                    .accessibilityIdentifier("piece.name")
            }
            Section {
                ForEach(AttributeKey.allCases, id: \.self) { key in
                    TagRow(key: key, attribute: piece.value[key]) {
                        update { $0[key]?.state = .confirmed; $0[key]?.by = Author.you.raw }
                    } edit: {
                        tagDraft = piece.value[key]?.text ?? ""
                        editing = key
                    }
                }
            } header: {
                Text(L10n.tags)
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
            if !piece.value.swatches.isEmpty {
                Section {
                    HStack {
                        ForEach(piece.value.swatches, id: \.hex) { swatch in
                            Circle()
                                .fill(Color(hex: swatch.hex) ?? .gray)
                                .frame(width: 30, height: 30)
                                .overlay { Circle().stroke(.secondary.opacity(0.3)) }
                        }
                    }
                } header: {
                    Text(L10n.colours)
                } footer: {
                    Text(L10n.coloursFooter)
                }
            }
            Section(L10n.notes) {
                ForEach(piece.value.notes) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.text)
                        Text(L10n.author(note.by))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(L10n.addNote, systemImage: "plus") {
                    noteDraft = ""
                    addingNote = true
                }
                .alert(L10n.addNote, isPresented: $addingNote) {
                    TextField(L10n.note, text: $noteDraft)
                    Button(L10n.save) {
                        let text = noteDraft.trimmed
                        guard !text.isEmpty else { return }
                        update { $0.notes.append(Note(id: AppModel.newId(), text: text, by: Author.you.raw, at: Date.now.ISO8601Format())) }
                    }
                    Button(L10n.cancel, role: .cancel) {}
                }
            }
            let outfits = model.library.outfits(using: id)
            if !outfits.isEmpty {
                Section(L10n.usedIn) {
                    ForEach(outfits) { outfit in
                        NavigationLink(outfit.value.title, value: Route.outfit(outfit.id))
                    }
                }
            }
            CommentsSection(subjectKind: .piece, subjectId: id)
            Section {
                Button(piece.value.status == .owned ? L10n.retire : L10n.bringBack) {
                    update { $0.status = $0.status == .owned ? .retired : .owned }
                }
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
        .onAppear { name = piece.value.name }
        .onChange(of: piece.value.name) { _, newName in name = newName }
    }

    /// A tag the person sets or edits is confirmed by them. Commas separate several values.
    private func saveTag(_ key: AttributeKey) {
        let values = tagDraft.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        update { $0[key] = values.isEmpty ? nil : Attribute(values, state: .confirmed, by: Author.you.raw) }
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

private struct TagRow: View {
    let key: AttributeKey
    let attribute: Attribute?
    let confirm: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.attribute(key))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let attribute {
                    Text(attribute.text)
                    Text(L10n.provenance(attribute))
                        .font(.caption2)
                        .foregroundStyle(attribute.state == .confirmed ? Color.secondary : Color.orange)
                } else {
                    Text(L10n.notSet)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if attribute?.state == .suggested {
                Button(L10n.confirm, action: confirm)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("piece.confirm.\(key.rawValue)")
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: edit)
    }
}
