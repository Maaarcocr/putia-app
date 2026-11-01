import PhotosUI
import PutiaCore
import SwiftUI

/// The pieces the person owns. Adding one is picking a photo: the cut-out, colours and
/// suggested tags are made on the phone, and the piece opens to be named.
struct ClosetView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var pick: PhotosPickerItem?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if model.library.ownedPieces.isEmpty {
                    ContentUnavailableView(L10n.closetEmptyTitle, systemImage: "hanger", description: Text(L10n.closetEmptyMessage))
                }
                grid(model.library.ownedPieces)
                if !model.library.retiredPieces.isEmpty {
                    Text(L10n.retired)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    grid(model.library.retiredPieces)
                        .opacity(0.6)
                }
            }
            .navigationTitle(L10n.tabCloset)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label(L10n.addPiece, systemImage: "plus")
                    }
                    .accessibilityIdentifier("closet.add")
                }
            }
            .overlay {
                if model.working {
                    ProgressView(L10n.preparingPhoto)
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .refreshable { await model.refresh() }
            .routes()
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            pick = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let id = await model.addPiece(from: data)
                else { return }
                path.append(.piece(id))
            }
        }
    }

    private func grid(_ pieces: [Record<Piece>]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(pieces) { piece in
                NavigationLink(value: Route.piece(piece.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        PieceImage(piece: piece)
                            .frame(height: 120)
                            .overlay(alignment: .topTrailing) {
                                if piece.value.needsReview {
                                    Image(systemName: "questionmark.circle.fill")
                                        .foregroundStyle(.orange)
                                        .padding(6)
                                        .accessibilityLabel(L10n.needsReview)
                                }
                            }
                        Text(L10n.name(of: piece.value))
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("closet.piece")
            }
        }
        .padding()
    }
}
