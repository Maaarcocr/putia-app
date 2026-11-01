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
                } header: {
                    Text(L10n.shortlist)
                } footer: {
                    Text(L10n.shortlistFooter)
                }
                Section(L10n.inspiration) {
                    ForEach(model.library.inspiration) { reference in
                        NavigationLink(value: Route.reference(reference.id)) {
                            HStack(spacing: 12) {
                                PhotoView(photoId: reference.value.photoIds.first)
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
            .sheet(isPresented: $addingWish) {
                WishEditor(wish: nil) { id in path.append(.wish(id)) }
                    .environment(model)
            }
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
            Text([L10n.priority(wish.value.priority), L10n.status(wish.value.status)].joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let problem = wish.value.problem {
                Text(problem)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}

/// A shortlist entry: what it solves, what it goes with, what's already owned that might do.
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
                if let description = wish.value.description {
                    Text(description)
                }
                Picker(L10n.priorityLabel, selection: Binding(get: { wish.value.priority }, set: { value in update { $0.priority = value } })) {
                    ForEach(Wish.Priority.allCases, id: \.self) { priority in
                        Text(L10n.priority(priority)).tag(priority)
                    }
                }
                Picker(L10n.statusLabel, selection: Binding(get: { wish.value.status }, set: { value in update { $0.status = value } })) {
                    ForEach(Wish.Status.allCases, id: \.self) { status in
                        Text(L10n.status(status)).tag(status)
                    }
                }
                Text(L10n.madeBy(wish.author))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let problem = wish.value.problem {
                Section(L10n.problem) { Text(problem) }
            }
            pieces(L10n.complements, wish.value.complementsPieceIds)
            pieces(L10n.ownedAlternatives, wish.value.alternativesOwnedIds)
            let outfits = wish.value.outfitsToTryIds.compactMap { model.library.outfits[$0] }
            if !outfits.isEmpty {
                Section(L10n.tryFirst) {
                    ForEach(outfits) { outfit in
                        NavigationLink(outfit.value.title, value: Route.outfit(outfit.id))
                    }
                }
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

    @ViewBuilder
    private func pieces(_ title: String, _ ids: [String]) -> some View {
        let pieces = ids.compactMap { model.library.pieces[$0] }
        if !pieces.isEmpty {
            Section(title) {
                ForEach(pieces) { piece in
                    NavigationLink(value: Route.piece(piece.id)) { PieceRow(piece: piece) }
                }
            }
        }
    }

    private func update(_ change: (inout Wish) -> Void) {
        guard let wish = model.library.wishes[id] else { return }
        var value = wish.value
        change(&value)
        guard value != wish.value else { return }
        Task { await model.save(.wish(value), id: id, revision: wish.revision) }
    }
}

/// Adds a shortlist entry, or edits its name, problem and priority.
private struct WishEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let wish: Record<Wish>?
    let created: (String) -> Void
    @State private var name = ""
    @State private var problem = ""
    @State private var priority = Wish.Priority.medium

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.wishName, text: $name)
                    .accessibilityIdentifier("wish.name")
                TextField(L10n.problemHint, text: $problem, axis: .vertical)
                    .lineLimit(3...6)
                Picker(L10n.priorityLabel, selection: $priority) {
                    ForEach(Wish.Priority.allCases, id: \.self) { priority in
                        Text(L10n.priority(priority)).tag(priority)
                    }
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
                problem = wish.value.problem ?? ""
                priority = wish.value.priority
            }
        }
    }

    private func save() {
        var value = wish?.value ?? Wish(name: name.trimmed)
        value.name = name.trimmed
        value.problem = problem.trimmed.isEmpty ? nil : problem.trimmed
        value.priority = priority
        Task {
            let saved: String?
            if let wish {
                saved = await model.save(.wish(value), id: wish.id, revision: wish.revision)?.id
            } else {
                saved = await model.create(.wish(value))
            }
            guard let saved else { return }
            dismiss()
            created(saved)
        }
    }
}

/// An inspiration image: what draws the person to it, and how owned pieces could carry the same
/// relationship (usually written by an AI).
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
                ForEach(reference.value.photoIds, id: \.self) { photoId in
                    PhotoView(photoId: photoId, size: .full)
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                }
                TextField(L10n.referenceTitle, text: $title)
                    .font(.title3.bold())
                    .submitLabel(.done)
                    .onSubmit {
                        guard !title.trimmed.isEmpty else { return }
                        update { $0.title = title.trimmed }
                    }
            }
            Section {
                ForEach(Reference.Attraction.allCases, id: \.self) { attraction in
                    Toggle(L10n.attraction(attraction), isOn: Binding(
                        get: { reference.value.attraction.contains(attraction) },
                        set: { on in
                            update {
                                $0.attraction.removeAll { $0 == attraction }
                                if on { $0.attraction.append(attraction) }
                            }
                        }
                    ))
                }
            } header: {
                Text(L10n.whatDrawsYou)
            } footer: {
                Text(L10n.attractionFooter)
            }
            Section(L10n.note) {
                TextField(L10n.noteHint, text: $note)
                    .submitLabel(.done)
                    .onSubmit { update { $0.note = note.trimmed.isEmpty ? nil : note.trimmed } }
            }
            Section(L10n.translation) {
                if let translation = reference.value.translation {
                    Text(translation.text)
                    ForEach(translation.pieceIds.compactMap { model.library.pieces[$0] }) { piece in
                        NavigationLink(value: Route.piece(piece.id)) { PieceRow(piece: piece) }
                    }
                    ForEach(translation.outfitIds.compactMap { model.library.outfits[$0] }) { outfit in
                        NavigationLink(outfit.value.title, value: Route.outfit(outfit.id))
                    }
                } else {
                    Text(L10n.noTranslation)
                        .foregroundStyle(.secondary)
                }
            }
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
