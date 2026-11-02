import PutiaCore
import SwiftUI

/// Collaboration: the AIs working on this bench, and every change anyone made, each undoable.
struct BenchView: View {
    @Environment(AppModel.self) private var model
    @State private var connecting = false
    @State private var confirmingDisconnect = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.benchIntro)
                        .font(.callout)
                    ForEach(model.agents, id: \.self) { name in
                        Label(name, systemImage: "sparkles")
                    }
                    Button(L10n.connectAI, systemImage: "link") { connecting = true }
                        .accessibilityIdentifier("bench.connect")
                        .sheet(isPresented: $connecting, onDismiss: { Task { await model.loadAgents() } }) {
                            ConnectView()
                                .environment(model)
                        }
                    if !model.agents.isEmpty {
                        Button(L10n.disconnectAll, role: .destructive) { confirmingDisconnect = true }
                            .alert(L10n.disconnectAllTitle, isPresented: $confirmingDisconnect) {
                                Button(L10n.disconnectAll, role: .destructive) { Task { await model.disconnectAgents() } }
                                Button(L10n.cancel, role: .cancel) {}
                            } message: {
                                Text(L10n.disconnectAllMessage)
                            }
                    }
                } header: {
                    Text(L10n.aiHeader)
                }
                PhotosSection(owner: .person, ownerId: model.account.id, title: L10n.photosOfYou, footer: L10n.photosOfYouFooter)
                Section(L10n.history) {
                    if model.history.isEmpty {
                        Text(L10n.noHistory)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.history) { change in
                        ChangeRow(change: change) {
                            Task { await model.undo(change) }
                        }
                    }
                }
                Section {
                    Button(L10n.deleteEverything, role: .destructive) { confirmingDelete = true }
                        .alert(L10n.deleteEverythingTitle, isPresented: $confirmingDelete) {
                            Button(L10n.deleteEverything, role: .destructive) { Task { await model.deleteEverything() } }
                            Button(L10n.cancel, role: .cancel) {}
                        } message: {
                            Text(L10n.deleteEverythingFooter)
                        }
                } footer: {
                    Text(L10n.deleteEverythingFooter)
                }
            }
            .navigationTitle(L10n.tabBench)
            .task {
                await model.loadHistory()
                await model.loadAgents()
            }
            .refreshable {
                await model.refresh()
                await model.loadHistory()
                await model.loadAgents()
            }
        }
    }
}

private struct ChangeRow: View {
    let change: Change
    let undo: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(change.label ?? L10n.kind(change.kind))
                    .lineLimit(2)
                Text(L10n.changeLine(change))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = change.note {
                    Text(note)
                        .font(.caption)
                        .italic()
                }
            }
            Spacer()
            Button(L10n.undo, action: undo)
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityIdentifier("history.undo")
        }
    }
}

/// Connecting an AI: add Putia's address as a connector in the AI app, then sign in there with
/// a one-time code shown here.
private struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pairing: Pairing?
    @State private var status = PairingStatus.waiting
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.connectStep1)
                    HStack {
                        Text(model.server.connectorURL.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Button(copied ? L10n.copied : L10n.copy) {
                            UIPasteboard.general.string = model.server.connectorURL.absoluteString
                            copied = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section {
                    Text(L10n.connectStep2)
                    if let pairing {
                        Text(pairing.code)
                            .font(.largeTitle.monospaced().bold())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("connect.code")
                    } else {
                        ProgressView()
                    }
                }
                Section {
                    switch status {
                    case .waiting:
                        Label(L10n.waitingForAI, systemImage: "hourglass")
                    case .connected(let agent):
                        Label(L10n.connected(agent), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("connect.connected")
                    case .expired:
                        Button(L10n.newCode) { Task { await start() } }
                    }
                } footer: {
                    Text(L10n.connectFooter)
                }
            }
            .navigationTitle(L10n.connectAI)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }
                }
            }
            .task { await start() }
        }
    }

    /// Shows a new code and waits for an AI to sign in with it.
    private func start() async {
        status = .waiting
        pairing = await model.pairingCode()
        guard let code = pairing?.code else { return }
        while !Task.isCancelled, status == .waiting {
            try? await Task.sleep(for: .seconds(2))
            if let next = await model.pairingStatus(code) { status = next }
        }
    }
}
