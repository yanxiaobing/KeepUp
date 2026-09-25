import SwiftUI
import Photos

/// One preview/export surface for the freshly saved result and historical workout details.
struct RunningShareView: View {
    let session: RunningSession
    var style: RunningShareStyle = .report
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Default(.runningSettings) private var settings
    @State private var artifact: RunningShareArtifact?
    @State private var sharingArtifact: RunningShareArtifact?
    @State private var rendering = false
    @State private var saving = false
    @State private var message: String?
    @State private var renderID = UUID()
    @State private var retryTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let artifact {
                    LazyVStack(spacing: 18) {
                        if artifact.mapStatus == .schematic {
                            VStack(spacing: 10) {
                                Text("runningShare.mapUnavailable").font(.footnote).multilineTextAlignment(.center)
                                Button("runningShare.retryMap") { retry() }
                                    .accessibilityIdentifier("running.share.retry").disabled(rendering)
                            }.padding(16)
                        }
                        if artifact.pages.count > 1 {
                            Text("runningShare.multiplePages").font(.footnote).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal, 16)
                        }
                        ForEach(artifact.pages) { page in
                            RunningSharePagePreview(page: page)
                                .id(page.url)
                        }
                    }.padding(16).accessibilityIdentifier("running.share.ready")
                } else if !rendering {
                    ContentUnavailableView {
                        Label("entry.shareError", systemImage: "photo")
                    } actions: {
                        Button("runningShare.retry") { retry() }
                    }
                }
                if rendering {
                    ProgressView("runningShare.preparing").padding(28)
                        .accessibilityIdentifier("running.share.loading")
                }
            }.background(Color(white: 0.94))
                .navigationTitle("entry.share").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text("action.close")).accessibilityIdentifier("running.share.close")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 16) {
                        Button("entry.saveImage", systemImage: "square.and.arrow.down") { savePhotos() }
                            .accessibilityIdentifier("running.share.save")
                        Spacer()
                        Button("entry.share", systemImage: "square.and.arrow.up") { sharingArtifact = artifact }
                            .accessibilityIdentifier("running.share.system")
                    }.padding(20).background(.regularMaterial).disabled(artifact == nil || saving)
                }
                .sheet(item: $sharingArtifact) { shared in
                    // Retaining the artifact while this sheet is open keeps its temporary files alive.
                    SystemImageShare(files: shared.pages.map(\.url))
                }
                .alert("entry.share", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    if message == "entry.photoDenied" {
                        Button("running.settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Button("action.ok") { message = nil }
                } message: { Text(LocalizedStringKey(message ?? "entry.shareError")) }
        }
        .task(id: locale.identifier + String(settings.satelliteMap)) { await render() }
        .onDisappear { retryTask?.cancel() }
    }

    private func retry() {
        retryTask?.cancel()
        retryTask = Task { await render() }
    }

    @MainActor private func render() async {
        let id = UUID()
        renderID = id
        rendering = true
        defer { if renderID == id { rendering = false } }
        do {
            let result = try await RunningShareRenderer().render(session: session, locale: locale, satellite: settings.satelliteMap, style: style)
            guard !Task.isCancelled, renderID == id else { return }
            artifact = result
        } catch is CancellationError {
            // Closing the preview or changing the language cancels only this render.
        } catch {
            guard !Task.isCancelled, renderID == id else { return }
            message = "entry.shareError"
        }
    }

    private func savePhotos() {
        guard let artifact, !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { message = "entry.photoDenied"; return }
            do {
                let urls = artifact.pages.map(\.url)
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    for url in urls {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, fileURL: url, options: nil)
                    }
                }
                // Keep the artifact alive until Photos has consumed every source file.
                withExtendedLifetime(artifact) {}
                message = "entry.imageSaved"
            } catch { message = "entry.shareError" }
        }
    }
}

/// Keep the page dimensions stable while releasing offscreen decoded images.
private struct RunningSharePagePreview: View {
    let page: RunningShareArtifact.Page
    @State private var image: UIImage?

    var body: some View {
        Color.white
            .aspectRatio(page.size.width / page.size.height, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFit() }
            }
            .accessibilityLabel(Text("runningShare.preview"))
            .accessibilityIdentifier("running.share.page.\(page.id)")
            .onAppear { image = page.previewImage() }
            .onDisappear { image = nil }
    }
}
