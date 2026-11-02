import PhotosUI
import PutiaCore
import SwiftUI

/// What's missing: the latest conclusion, the shortlist, and inspiration, all kept apart from
/// the pieces the person owns. "Nothing needed" is a valid conclusion.
struct MissingView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var addingWish = false
    @State private var pick: PhotosPickerItem?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section(L10n.latestConclusion) {
                    if let review = model.library.latestReview {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.conclusion(review.value.conclusion))
                                .font(.headline)
                            Text(review.value.summary)
                            Text(L10n.madeBy(review.author))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(L10n.noConclusion)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(model.library.shortlist) { wish in
                        NavigationLink(value: Route.wish(wish.id)) { WishRow(wish: wish) }
                            .accessibilityIdentifier("missing.wish")
                    }
                    Button(L10n.addWish, systemImage: "plus") { addingWish = true }
                        .sheet(isPresented: $addingWish) {
                            WishEditor(wish: nil) { id in path.append(.wish(id)) }
                                .environment(model)
                        }
                } header: {
                    Text(L10n.shortlist)
                } footer: {
                    Text(L10n.shortlistFooter)
                }
                Section(L10n.inspiration) {
                    ForEach(model.library.inspiration) { reference in
                        NavigationLink(value: Route.reference(reference.id)) {
                            HStack(spacing: 12) {
                                PhotoView(photoId: model.library.photos(of: reference.id).first?.id)
                                    .frame(width: 52, height: 52)
                                    .clipShape(.rect(cornerRadius: 8))
                                Text(reference.value.title)
                            }
                        }
                    }
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label(L10n.addInspiration, systemImage: "photo.badge.plus")
                    }
                    if model.working {
                        ProgressView(L10n.preparingPhoto)
                    }
                }
                if !model.library.decidedWishes.isEmpty {
                    Section(L10n.decided) {
                        ForEach(model.library.decidedWishes) { wish in
                            NavigationLink(value: Route.wish(wish.id)) { WishRow(wish: wish) }
                        }
                    }
                }
            }
            .navigationTitle(L10n.tabMissing)
            .onChange(of: pick) { _, item in
                guard let item else { return }
                pick = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let id = await model.addInspiration(data)
                    else { return }
                    path.append(.reference(id))
                }
            }
            .refreshable { await model.refresh() }
            .routes()
        }
    }
}

private struct WishRow: View {
    let wish: Record<Wish>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(wish.value.name)
            if wish.value.status != .considering {
                Text(L10n.status(wish.value.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let note = wish.value.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

/// A shortlist entry: what it would solve, and where to find it.
struct WishView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        if let wish = model.library.wishes[id] {
            content(wish)
        } else {
            ContentUnavailableView(L10n.gone, systemImage: "list.bullet")
        }
    }

    private func content(_ wish: Record<Wish>) -> some View {
        List {
            Section {
                Text(wish.value.name)
                    .font(.title3.bold())
                Picker(L10n.statusLabel, selection: Binding(get: { wish.value.status }, set: { value in update { $0.status = value } })) {
                    ForEach(Wish.Status.allCases, id: \.self) { status in
                        Text(L10n.status(status)).tag(status)
                    }
                }
                Text(L10n.madeBy(wish.author))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = wish.value.note {
                Section(L10n.problem) { Text(note) }
            }
            if let link = wish.value.link, let url = URL(string: link) {
                Section {
                    Link(L10n.openLink, destination: url)
                }
            }
            CommentsSection(subjectKind: .wish, subjectId: id)
            Section {
                Button(L10n.edit) { editing = true }
                    .sheet(isPresented: $editing) {
                        WishEditor(wish: wish) { _ in }
                            .environment(model)
                    }
                Button(L10n.delete, role: .destructive) { confirmingDelete = true }
                    .alert(L10n.deleteWishTitle, isPresented: $confirmingDelete) {
                        Button(L10n.delete, role: .destructive) {
                            Task {
                                if await model.delete(.wish, id: id, revision: wish.revision) { dismiss() }
                            }
                        }
                        Button(L10n.cancel, role: .cancel) {}
                    } message: {
                        Text(L10n.deleteUndoable)
                    }
            }
        }
        .navigationTitle(wish.value.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout Wish) -> Void) {
        guard let wish = model.library.wishes[id] else { return }
        var value = wish.value
        change(&value)
        guard value != wish.value else { return }
        Task { await model.save(.wish(value), id: id, revision: wish.revision) }
    }
}

/// Adds a shortlist entry, or edits its name and why.
private struct WishEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let wish: Record<Wish>?
    let saved: (String) -> Void
    @State private var name = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.wishName, text: $name)
                    .accessibilityIdentifier("wish.name")
                TextField(L10n.problemHint, text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle(wish == nil ? L10n.addWish : L10n.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) { save() }
                        .disabled(name.trimmed.isEmpty)
                        .accessibilityIdentifier("wish.save")
                }
            }
            .onAppear {
                guard let wish else { return }
                name = wish.value.name
                note = wish.value.note ?? ""
            }
        }
    }

    private func save() {
        var value = wish?.value ?? Wish(name: "")
        value.name = name.trimmed
        value.note = note.trimmed.isEmpty ? nil : note.trimmed
        Task {
            let id: String?
            if let wish {
                id = await model.save(.wish(value), id: wish.id, revision: wish.revision) ? wish.id : nil
            } else {
                id = await model.create(.wish(value))
            }
            guard let id else { return }
            dismiss()
            saved(id)
        }
    }
}

/// An inspiration image: what the person likes about it, and the conversation about it.
struct ReferenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var title = ""
    @State private var note = ""
    @State private var confirmingDelete = false

    var body: some View {
        if let reference = model.library.references[id] {
            content(reference)
        } else {
            ContentUnavailableView(L10n.gone, systemImage: "photo")
        }
    }

    private func content(_ reference: Record<Reference>) -> some View {
        List {
            Section {
                TextField(L10n.referenceTitle, text: $title)
                    .font(.title3.bold())
                    .submitLabel(.done)
                    .onSubmit {
                        guard !title.trimmed.isEmpty else { return }
                        update { $0.title = title.trimmed }
                    }
                TextField(L10n.referenceNoteHint, text: $note)
                    .submitLabel(.done)
                    .onSubmit { update { $0.note = note.trimmed.isEmpty ? nil : note.trimmed } }
            }
            PhotosSection(owner: .reference, ownerId: id)
            CommentsSection(subjectKind: .reference, subjectId: id)
            Section {
                Button(L10n.delete, role: .destructive) { confirmingDelete = true }
                    .alert(L10n.deleteInspirationTitle, isPresented: $confirmingDelete) {
                        Button(L10n.delete, role: .destructive) {
                            Task {
                                if await model.delete(.reference, id: id, revision: reference.revision) { dismiss() }
                            }
                        }
                        Button(L10n.cancel, role: .cancel) {}
                    } message: {
                        Text(L10n.deleteUndoable)
                    }
            }
        }
        .navigationTitle(reference.value.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            title = reference.value.title
            note = reference.value.note ?? ""
        }
    }

    private func update(_ change: (inout Reference) -> Void) {
        guard let reference = model.library.references[id] else { return }
        var value = reference.value
        change(&value)
        guard value != reference.value else { return }
        Task { await model.save(.reference(value), id: id, revision: reference.revision) }
    }
}
