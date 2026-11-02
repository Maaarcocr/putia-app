import PhotosUI
import PutiaCore
import SwiftUI

/// Every screen a tab can push.
nonisolated enum Route: Hashable, Sendable {
    case piece(String)
    case outfit(String)
    case wish(String)
    case reference(String)
}

extension View {
    /// The screens every tab's navigation stack can show.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .piece(let id): PieceView(id: id)
            case .outfit(let id): OutfitView(id: id)
            case .wish(let id): WishView(id: id)
            case .reference(let id): ReferenceView(id: id)
            }
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A photo loaded through the app model, with a hanger while there is none.
struct PhotoView: View {
    @Environment(AppModel.self) private var model
    let photoId: String?
    var size: PhotoSize = .thumb
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "hanger")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photoId) {
            image = nil
            if let photoId {
                image = await model.image(photoId, size: size)
            }
        }
    }
}

/// A piece's main photo.
struct PieceImage: View {
    @Environment(AppModel.self) private var model
    let piece: Record<Piece>?

    var body: some View {
        PhotoView(photoId: piece.flatMap { model.library.mainPhotoId(of: $0) })
            .padding(6)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

/// A piece in a list: its image and name.
struct PieceRow: View {
    let piece: Record<Piece>

    var body: some View {
        HStack(spacing: 12) {
            PieceImage(piece: piece)
                .frame(width: 52, height: 52)
            Text(L10n.name(of: piece.value))
        }
    }
}

/// An outfit drawn from each piece's main photo, like a flat lay. The pieces run from head to feet
/// down two overlapping columns, and each lies over the next: the jacket over the shirt, the shirt
/// over the trousers.
struct Collage: View {
    @Environment(AppModel.self) private var model
    let pieceIds: [String]
    var height: CGFloat = 150

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * 0.6
            ZStack(alignment: .topLeading) {
                ForEach(Array(pieceIds.enumerated()), id: \.offset) { index, id in
                    PhotoView(photoId: model.library.pieces[id].flatMap { model.library.mainPhotoId(of: $0) })
                        .frame(width: width, height: height)
                        .offset(x: index.isMultiple(of: 2) ? 0 : geometry.size.width - width, y: top(index))
                        .zIndex(Double(pieceIds.count - index))
                }
            }
        }
        .frame(height: top(pieceIds.count - 1) + height)
    }

    /// Each row overlaps the one above by a third; the right column sits half a row lower.
    private func top(_ index: Int) -> CGFloat {
        height * (0.7 * CGFloat(index / 2) + 0.35 * CGFloat(index % 2))
    }
}

/// A record's (or the person's) photos, each of which can be deleted, and a button to add one. A
/// piece's photo can be made its main one.
struct PhotosSection: View {
    @Environment(AppModel.self) private var model
    let owner: Photo.Owner
    let ownerId: String
    var title: String?
    var footer: String?
    @State private var pick: PhotosPickerItem?

    var body: some View {
        Section {
            ForEach(model.library.photos(of: ownerId)) { photo in
                PhotoRow(photo: photo)
            }
            PhotosPicker(selection: $pick, matching: .images) {
                Label(L10n.addPhoto, systemImage: "photo.badge.plus")
            }
            .accessibilityIdentifier("photos.add.\(owner.rawValue)")
            if model.working {
                ProgressView(L10n.preparingPhoto)
            }
        } header: {
            Text(title ?? L10n.photos)
        } footer: {
            if let footer {
                Text(footer)
            }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            pick = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await model.addPhoto(data, to: owner, ownerId: ownerId)
            }
        }
    }
}

private struct PhotoRow: View {
    @Environment(AppModel.self) private var model
    let photo: Record<Photo>
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 8) {
            PhotoView(photoId: photo.id)
                .frame(height: 180)
            HStack {
                if photo.value.ownerKind == .piece, let piece = model.library.pieces[photo.value.ownerId], model.library.mainPhotoId(of: piece) != photo.id {
                    Button(L10n.useAsMainPhoto) { Task { await model.setMainPhoto(photo.id, of: piece.id) } }
                        .accessibilityIdentifier("photo.useAsMain.\(photo.id)")
                }
                Spacer()
                Button(L10n.delete, role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("photo.delete")
                    .alert(L10n.deletePhotoTitle, isPresented: $confirmingDelete) {
                        Button(L10n.delete, role: .destructive) { Task { await model.delete(.photo, id: photo.id, revision: photo.revision) } }
                        Button(L10n.cancel, role: .cancel) {}
                    } message: {
                        Text(L10n.deleteUndoable)
                    }
            }
            // Separate tap targets inside one list row.
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

/// The conversation on a record: the person's comments and the AI's.
struct CommentsSection: View {
    @Environment(AppModel.self) private var model
    let subjectKind: Kind
    let subjectId: String
    @State private var draft = ""

    var body: some View {
        Section(L10n.comments) {
            ForEach(model.library.comments(on: subjectId)) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.author(comment.createdBy))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(comment.value.text)
                }
            }
            HStack {
                TextField(L10n.addComment, text: $draft, axis: .vertical)
                    .accessibilityIdentifier("comments.field")
                Button(L10n.send, systemImage: "arrow.up.circle.fill") {
                    send()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
                .disabled(draft.trimmed.isEmpty)
                .accessibilityIdentifier("comments.send")
            }
        }
    }

    private func send() {
        let comment = Comment(subjectKind: subjectKind, subjectId: subjectId, text: draft.trimmed)
        Task {
            if await model.create(.comment(comment)) != nil {
                draft = ""
            }
        }
    }
}
