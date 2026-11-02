import PutiaCore
import SwiftUI

/// What's missing: suggestions of things to get, from the person or an AI.
struct MissingView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var adding = false

    var body: some View {
        NavigationStack(path: $path) {
            let wishes = model.library.missing
            List(wishes) { wish in
                NavigationLink(value: Route.wish(wish.id)) { WishRow(wish: wish) }
                    .accessibilityIdentifier("missing.wish")
            }
            .overlay {
                if wishes.isEmpty {
                    ContentUnavailableView(L10n.missingEmptyTitle, systemImage: "bag", description: Text(L10n.missingEmptyMessage))
                }
            }
            .animation(.default, value: wishes.map(\.id))
            .navigationTitle(L10n.tabMissing)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.addWish, systemImage: "plus") { adding = true }
                        .accessibilityIdentifier("missing.add")
                        .sheet(isPresented: $adding) {
                            WishEditor(wish: nil) { id in path.append(.wish(id)) }
                                .environment(model)
                        }
                }
            }
            .refreshable { await model.refresh() }
            .routes()
        }
    }
}

/// A suggestion in the list: its first photo, name and what it solves.
private struct WishRow: View {
    @Environment(AppModel.self) private var model
    let wish: Record<Wish>

    var body: some View {
        HStack(spacing: 12) {
            PhotoView(photoId: model.library.photos(of: wish.id).first?.id, cornerRadius: 6)
                .padding(4)
                .frame(width: 52, height: 52)
                .background(.fill.tertiary, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(wish.value.name)
                if let note = wish.value.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// A suggestion: what it solves, its photos and links, and the conversation about it.
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
            ContentUnavailableView(L10n.gone, systemImage: "bag")
        }
    }

    private func content(_ wish: Record<Wish>) -> some View {
        List {
            Section {
                Text(wish.value.name)
                    .font(.title3.bold())
                if let note = wish.value.note {
                    Text(note)
                }
            } footer: {
                Byline(author: wish.author)
            }
            PhotosSection(owner: .wish, ownerId: id)
            if !wish.value.links.isEmpty {
                Section(L10n.links) {
                    ForEach(wish.value.links, id: \.self) { link in
                        if let url = URL(string: link) {
                            Link(destination: url) {
                                Label(url.host() ?? link, systemImage: "safari")
                            }
                            .accessibilityIdentifier("wish.link")
                        }
                    }
                }
            }
            CommentsSection(subjectKind: .wish, subjectId: id)
            Section {
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.edit) { editing = true }
                    .accessibilityIdentifier("wish.edit")
                    .sheet(isPresented: $editing) {
                        WishEditor(wish: wish) { _ in }
                            .environment(model)
                    }
            }
        }
    }
}

/// Adds a suggestion, or edits its name, what it solves and its links (one per line).
private struct WishEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let wish: Record<Wish>?
    let saved: (String) -> Void
    @State private var name = ""
    @State private var note = ""
    @State private var links = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.wishName, text: $name)
                        .accessibilityIdentifier("wish.name")
                    TextField(L10n.problemHint, text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section(L10n.links) {
                    TextField(L10n.linksHint, text: $links, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wish.links")
                }
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
                links = wish.value.links.joined(separator: "\n")
            }
        }
    }

    private func save() {
        var value = wish?.value ?? Wish(name: "")
        value.name = name.trimmed
        value.note = note.trimmed.isEmpty ? nil : note.trimmed
        value.links = links.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }
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
