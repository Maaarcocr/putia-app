import PutiaCore
import SwiftUI

/// Every screen a tab can push.
nonisolated enum Route: Hashable, Sendable {
    case piece(String)
    case outfit(String)
    /// An outfit and a variation of it, side by side.
    case compare(String, String)
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
            case .compare(let left, let right): CompareView(leftId: left, rightId: right)
            case .wish(let id): WishView(id: id)
            case .reference(let id): ReferenceView(id: id)
            }
        }
    }
}

extension Color {
    /// A colour from "#rrggbb".
    init?(hex: String?) {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double(value >> 16 & 0xff) / 255, green: Double(value >> 8 & 0xff) / 255, blue: Double(value & 0xff) / 255)
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

/// A piece's cut-out on a tint of its own colour.
struct PieceImage: View {
    @Environment(AppModel.self) private var model
    let piece: Record<Piece>?

    var body: some View {
        PhotoView(photoId: piece.flatMap { model.library.heroPhotoId(of: $0.value) })
            .padding(6)
            .background((Color(hex: piece?.value.swatches.first?.hex) ?? .gray).opacity(0.18), in: .rect(cornerRadius: 12))
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

/// An outfit's pieces, large.
struct Collage: View {
    @Environment(AppModel.self) private var model
    let pieceIds: [String]
    var height: CGFloat = 150

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(pieceIds.enumerated()), id: \.offset) { _, id in
                PieceImage(piece: model.library.pieces[id])
                    .frame(height: height)
            }
        }
    }
}

/// A labelled paragraph, shown only when there is text.
struct LabeledText: View {
    let label: String
    let text: String?

    var body: some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
            }
        }
    }
}

/// The conversation on a record: the person's comments and reactions, and the AI's.
struct CommentsSection: View {
    @Environment(AppModel.self) private var model
    let subjectKind: Kind
    let subjectId: String
    @State private var draft = ""

    var body: some View {
        Section(L10n.comments) {
            ForEach(model.library.comments(on: subjectId)) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.commentHeader(comment.value))
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
