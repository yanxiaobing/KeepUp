import SwiftUI

/// Load large GPS tracks only when a record is opened; legacy manual runs keep their existing detail view.
struct RunningRecordView: View {
    let entry: CheckInEntry
    let card: HabitCard
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: RunningSession?
    @State private var loaded = false
    @State private var failed = false
    @State private var loading = false

    var body: some View {
        Group {
            if let session {
                RunningDetailView(session: session, entry: entry, card: card)
            } else if loaded {
                EntryDetailView(entry: entry, card: card)
            } else {
                NavigationStack {
                    VStack(spacing: 18) {
                        if failed {
                            Text("running.loadFailed").multilineTextAlignment(.center)
                                .accessibilityIdentifier("running.loadFailed")
                            Button("running.retryLoad") { Task { await load() } }
                                .accessibilityIdentifier("running.retryLoad")
                        } else {
                            ProgressView("running.loading")
                        }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle("running.result").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { dismiss() } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel(Text("action.close")).accessibilityIdentifier("running.result.close")
                                    .tint(KeepUpStyle.navigationTint)
                            }
                        }
                }
            }
        }.task(id: entry.id) { await load() }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        failed = false
        defer { loading = false }
        do {
            session = try await model.runningSession(id: entry.id)
            loaded = true
        } catch {
            failed = true
        }
    }
}
