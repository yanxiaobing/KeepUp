import SwiftUI

struct EntryContentEditor: View {
    let entry: CheckInEntry
    let card: HabitCard
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var content = EntryContent()
    @State private var initial = EntryContent()
    @State private var initialized = false
    @State private var busy = false
    @State private var showCancel = false
    @State private var showPhotoMenu = false
    @State private var source: PhotoSource?
    @State private var photoError = false
    @FocusState private var focused: Bool
    private enum PhotoSource: String, Identifiable { case library, camera, crop; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let s = geometry.size.width/375
                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $content.text).font(.system(size: 16*s)).frame(height: 100).padding(.horizontal, 15*s).padding(.top, 15*s)
                                .focused($focused).accessibilityIdentifier("content.text")
                            ZStack(alignment: .topTrailing) {
                                Button { focused = false; if content.photo != nil { source = .crop } else { showPhotoMenu = true } } label: {
                                    if let data = content.photo, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFill().frame(width: 100*s, height: 100*s).clipped()
                                    } else { Image("trend_add_pic").resizable().frame(width: 100*s, height: 100*s) }
                                }.buttonStyle(.plain).accessibilityLabel(Text("content.photo")).accessibilityIdentifier("content.photo")
                                if content.photo != nil {
                                    Button { content.photo = nil } label: {
                                        Image("trend_image_close").resizable().frame(width: 20*s, height: 20*s)
                                    }.padding(2*s).accessibilityLabel(Text("content.removePhoto")).accessibilityIdentifier("content.removePhoto")
                                }
                            }.padding(.leading, 15*s).offset(y: 245-115*s)
                        }.frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 245, alignment: .top).background(.white)
                        Text("content.singlePhoto").font(.system(size: 14)).foregroundStyle(Color(white: 34/255).opacity(0.3)).frame(height: 100)
                    }
                }.background(Color(white: 246/255))
            }
            .navigationTitle(Text(LocalizedStringKey(card.titleKey))).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KeepUpStyle.theme, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        focused = false
                        if content != initial { showCancel = true } else { dismiss() }
                    }.disabled(busy).accessibilityIdentifier("content.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(content.isEmpty && !model.snapshot.publishedContent(for: entry).isEmpty ? "action.delete" : "action.save") { save(asDraft: false) }
                        .disabled(busy || (content.isEmpty && model.snapshot.publishedContent(for: entry).isEmpty))
                        .accessibilityIdentifier("content.save")
                }
            }
            .onAppear {
                guard !initialized else { return }
                content = model.snapshot.editingContent(for: entry); initial = content; initialized = true; focused = true
            }
            .confirmationDialog("content.keepQuestion", isPresented: $showCancel, titleVisibility: .visible) {
                Button("content.keepDraft") { save(asDraft: true) }.accessibilityIdentifier("content.keepDraft")
                Button("content.discard", role: .destructive) {
                    busy = true
                    Task { if await model.discardContentDraft(entryID: entry.id) { dismiss() }; busy = false }
                }.accessibilityIdentifier("content.discard")
                Button("action.cancel", role: .cancel) {}
            }
            .confirmationDialog("content.photo", isPresented: $showPhotoMenu) {
                Button("info.camera") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { source = .camera } else { photoError = true }
                }
                Button("info.library") { source = .library }.accessibilityIdentifier("content.library")
                Button("action.cancel", role: .cancel) {}
            }
            .fullScreenCover(item: $source) { source in
                if source == .crop, let data = content.photo, let image = UIImage(data: data) {
                    ExistingImageCropper(image: image, locale: locale, completion: selectedPhoto).ignoresSafeArea()
                } else {
                    AvatarPicker(camera: source == .camera, locale: locale, completion: selectedPhoto).ignoresSafeArea()
                }
            }
            .alert("error.title", isPresented: $photoError) { Button("action.ok", role: .cancel) {} } message: { Text("info.photoError") }
            .interactiveDismissDisabled()
        }
    }
    private func selectedPhoto(_ image: UIImage?) {
        source = nil
        if let image { content.photo = image.profileJPEG() }
    }
    private func save(asDraft: Bool) {
        focused = false; busy = true
        Task {
            if await model.saveContent(entryID: entry.id, content: content.isEmpty && !asDraft ? nil : content, asDraft: asDraft) { dismiss() }
            busy = false
        }
    }
}
