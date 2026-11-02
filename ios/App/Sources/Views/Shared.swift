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

extension Author {
    /// Shown next to what someone made: a person for you, sparkles for an AI.
    var symbol: String { self == .you ? "person.crop.circle" : "sparkles" }
}

/// Who made something: "Made by you" or "Proposed by Claude".
struct Byline: View {
    let author: Author

    var body: some View {
        Label(L10n.madeBy(author), systemImage: author.symbol)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// A photo loaded through the app model, with a hanger while there is none. It fits its frame,
/// with rounded corners if asked; or fills it, and the caller clips it.
struct PhotoView: View {
    @Environment(AppModel.self) private var model
    let photoId: String?
    var size: PhotoSize = .thumb
    var fill = false
    var cornerRadius: CGFloat = 0
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .clipShape(.rect(cornerRadius: cornerRadius))
            } else {
                Image(systemName: "hanger")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: image)
        .task(id: photoId) {
            image = nil
            if let photoId {
                image = await model.image(photoId, size: size)
            }
        }
    }
}

/// A piece's main photo on a soft tile, so a white shirt still shows.
struct PieceImage: View {
    @Environment(AppModel.self) private var model
    let piece: Record<Piece>?
    var small = false

    var body: some View {
        PhotoView(photoId: piece.flatMap { model.library.mainPhotoId(of: $0) })
            .padding(small ? 4 : 10)
            .background(.fill.tertiary, in: .rect(cornerRadius: small ? 10 : 18))
    }
}

/// A piece in a list: its image and name.
struct PieceRow: View {
    let piece: Record<Piece>

    var body: some View {
        HStack(spacing: 12) {
            PieceImage(piece: piece, small: true)
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

/// A record's (or the person's) photos as a strip, ending with a tile to add one. Tapping a photo
/// opens it large.
struct PhotosSection: View {
    @Environment(AppModel.self) private var model
    let owner: Photo.Owner
    let ownerId: String
    var title: String?
    var footer: String?
    @State private var pick: PhotosPickerItem?

    var body: some View {
        let photos = model.library.photos(of: ownerId)
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        PhotoThumbnail(photo: photo)
                    }
                    if model.working {
                        ProgressView()
                            .frame(width: PhotoThumbnail.width, height: PhotoThumbnail.height)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                            .accessibilityLabel(L10n.preparingPhoto)
                    }
                    PhotosPicker(selection: $pick, matching: .images) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: PhotoThumbnail.width, height: PhotoThumbnail.height)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                    }
                    .accessibilityLabel(L10n.addPhoto)
                    .accessibilityIdentifier("photos.add.\(owner.rawValue)")
                }
                // Each photo is its own tap target inside the one list row.
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets())
            .animation(.default, value: photos.map(\.id))
            .animation(.default, value: model.working)
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

private struct PhotoThumbnail: View {
    static let width: CGFloat = 90
    static let height: CGFloat = 120

    @Environment(AppModel.self) private var model
    let photo: Record<Photo>
    @State private var open = false

    var body: some View {
        let piece = photo.value.ownerKind == .piece
        let main = isMain
        Button { open = true } label: {
            PhotoView(photoId: photo.id, fill: !piece)
                .padding(piece ? 6 : 0)
                .frame(width: Self.width, height: Self.height)
                .background(.fill.tertiary)
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if main {
                        Image(systemName: "star.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.tint, in: .circle)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .accessibilityLabel(main ? L10n.mainPhoto : L10n.kind(.photo))
        .accessibilityIdentifier(main ? "photo.main.\(photo.id)" : "photo.\(photo.id)")
        .animation(.spring, value: main)
        .sensoryFeedback(.selection, trigger: main) { _, now in now }
        .sheet(isPresented: $open) {
            PhotoViewer(photo: photo, canBeMain: piece && !main)
                .environment(model)
        }
    }

    private var isMain: Bool {
        guard let piece = model.library.pieces[photo.value.ownerId] else { return false }
        return model.library.mainPhotoId(of: piece) == photo.id
    }
}

/// A photo large, with who added it. A piece's photo can be made its main one.
private struct PhotoViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let photo: Record<Photo>
    let canBeMain: Bool
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            PhotoView(photoId: photo.id, size: .full, cornerRadius: 12)
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Label(L10n.author(photo.createdBy), systemImage: photo.author.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.headline)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { dismiss() }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        if canBeMain {
                            Button(L10n.useAsMainPhoto, systemImage: "star") {
                                Task { await model.setMainPhoto(photo.id, of: photo.value.ownerId) }
                                dismiss()
                            }
                            .labelStyle(.titleAndIcon)
                            .accessibilityIdentifier("photo.useAsMain")
                        }
                        Spacer()
                        Button(L10n.delete, systemImage: "trash", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("photo.delete")
                            .alert(L10n.deletePhotoTitle, isPresented: $confirmingDelete) {
                                Button(L10n.delete, role: .destructive) {
                                    Task {
                                        if await model.delete(.photo, id: photo.id, revision: photo.revision) { dismiss() }
                                    }
                                }
                                Button(L10n.cancel, role: .cancel) {}
                            } message: {
                                Text(L10n.deleteUndoable)
                            }
                    }
                }
        }
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
                    Label(L10n.author(comment.createdBy), systemImage: comment.author.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(comment.value.text)
                }
                .padding(.vertical, 2)
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
