import PhotosUI
import PutiaCore
import SwiftUI

/// The pieces the person owns. Adding one is picking a photo: it's cut out on the phone, and the
/// piece opens to be named.
struct ClosetView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var pick: PhotosPickerItem?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                grid(model.library.closet)
            }
            .overlay {
                if model.library.closet.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.closetEmptyTitle, systemImage: "hanger")
                    } description: {
                        Text(L10n.closetEmptyMessage)
                    } actions: {
                        PhotosPicker(selection: $pick, matching: .images) {
                            Text(L10n.addPiece)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(L10n.tabCloset)
            .toolbarTitleDisplayMode(.inlineLarge)
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
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 18))
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
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(pieces) { piece in
                NavigationLink(value: Route.piece(piece.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        PieceImage(piece: piece)
                            .aspectRatio(4 / 5, contentMode: .fit)
                            .overlay(alignment: .topTrailing) {
                                if piece.value.needsReview {
                                    Image(systemName: "questionmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .orange)
                                        .font(.title3)
                                        .padding(6)
                                        .accessibilityLabel(L10n.needsReview)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        Text(L10n.name(of: piece.value))
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 4)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("closet.piece")
            }
        }
        .padding()
        .animation(.default, value: pieces.map(\.id))
        .animation(.spring, value: pieces.map(\.value.needsReview))
    }
}
