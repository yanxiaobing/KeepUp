import SwiftUI

/// PunchCard's existing-user personal information page, with per-field local persistence.
struct ProfileInfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var nicknameFocused = false
    @State private var menu: MenuKind?
    @State private var pendingSource: ImageSource?
    @State private var sheetKind: MenuKind?
    @State private var metric: ProfileMetric?
    @State private var source: ImageSource?
    @State private var photoError = false
    @State private var pendingSaves = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var submittedNickname = ""
    @State private var initialized = false
    @State private var closeRequested = false
    @State private var saveError: String?
    private var profile: UserProfile { model.snapshot.profile ?? UserProfile() }
    private enum MenuKind { case avatar, gender }
    private enum ImageSource: String, Identifiable { case camera, library; var id: String { rawValue } }

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width / 375
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Button { closeAfterSaving() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 20)).frame(width: 44, height: 44)
                        }.accessibilityLabel(Text("action.back")).accessibilityIdentifier("profile.info.back")
                        Spacer()
                        Text("profile.personalInfo").font(.system(size: 17, weight: .medium))
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }.foregroundStyle(Color(white: 0.13)).background(KeepUpStyle.theme)
                    ScrollView {
                        VStack(spacing: 10*s) {
                            VStack(spacing: 0) {
                                row("info.avatarLabel", s: s, height: 70*s) { blur(); sheetKind = .avatar } value: {
                                    if let data = profile.avatar, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFill().frame(width: 60*s, height: 60*s).clipShape(Circle())
                                    } else { Text("profile.tapToSet") }
                                }.accessibilityIdentifier("profile.info.avatar")
                                HStack(spacing: 6*s) {
                                    Text("info.nicknameLabel").foregroundStyle(Color(white: 0.13))
                                    Spacer()
                                    ProfileNicknameField(text: $nickname, focused: $nicknameFocused,
                                                         placeholder: localized("profile.nickname", locale), scale: s,
                                                         settingsStyle: true, onCommit: commitNickname)
                                        .frame(width: 140*s, height: 50*s)
                                    arrow(s)
                                }.font(.system(size: 16*s)).padding(.horizontal, 15*s).frame(height: 50*s)
                                    .background(.white).overlay(alignment: .bottom) { separator(s) }
                                    .contentShape(Rectangle()).onTapGesture { nicknameFocused = true }
                                row("info.gender", s: s) { blur(); sheetKind = .gender } value: {
                                    Text(LocalizedStringKey(profile.isMale ? "info.male" : "info.female"))
                                }.accessibilityIdentifier("profile.info.gender")
                            }
                            VStack(spacing: 0) {
                                ForEach(ProfileMetric.allCases) { kind in
                                    row(kind == .year ? "info.year" : kind == .height ? "info.heightLabel" : "info.weightLabel", s: s) {
                                        blur(); metric = kind
                                    } value: {
                                        Text(kind == .year ? String(profile.year) : kind.value(in: profile).formatted(.number.precision(.fractionLength(1)).locale(locale)))
                                    }.accessibilityIdentifier("profile.info.\(kind.rawValue)")
                                }
                            }
                        }
                    }.background(Color(white: 246/255))
                }
                if let metric {
                    ProfileRulerOverlay(metric: metric, value: metric.value(in: profile), scale: s) { value in
                        self.metric = nil
                        guard let value else { return }
                        switch metric { case .year: save(.year(Int(value.rounded()))); case .height: save(.height(value)); case .weight: save(.weight(value)) }
                    }.id(metric).ignoresSafeArea()
                }
            }.background(KeepUpStyle.theme.ignoresSafeArea(edges: .top))
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            nickname = profile.nickname
            submittedNickname = profile.nickname
        }
        .onChange(of: pendingSaves) { _, count in
            if count == 0, closeRequested, saveError == nil { dismiss() }
        }
        .sheet(isPresented: Binding(get: { sheetKind != nil }, set: { if !$0 { sheetKind = nil } }), onDismiss: {
            guard let selection = pendingSource else { return }
            pendingSource = nil
            if selection == .camera, !UIImagePickerController.isSourceTypeAvailable(.camera) { photoError = true }
            else { source = selection }
        }) {
            if sheetKind == .avatar {
                AvatarSourceSheet(options: [
                    .init(id: "info.camera", titleKey: "info.camera"),
                    .init(id: "info.library", titleKey: "info.library")
                ]) { selection in
                    pendingSource = selection == "info.camera" ? .camera : selection == "info.library" ? .library : nil
                    sheetKind = nil
                }
            } else {
                AvatarSourceSheet(options: [
                    .init(id: "info.gender.male", titleKey: "info.male"),
                    .init(id: "info.gender.female", titleKey: "info.female")
                ]) { selection in
                    if selection == "info.gender.male" { save(.gender(true)) }
                    if selection == "info.gender.female" { save(.gender(false)) }
                    sheetKind = nil
                }
            }
        }
        .fullScreenCover(item: $source) { source in
            AvatarPicker(camera: source == .camera, locale: locale) { image in
                self.source = nil
                if let image, let data = image.profileJPEG() { save(.avatar(data)) }
            }.ignoresSafeArea()
        }
        .alert("error.title", isPresented: $photoError) { Button("action.ok", role: .cancel) {} } message: { Text("info.photoError") }
        .alert("error.title", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("action.ok") { saveError = nil }
        } message: { Text(LocalizedStringKey(saveError ?? "error.storage")) }
        .interactiveDismissDisabled(nicknameFocused || pendingSaves > 0)
    }
    private func blur() {
        // Commit marked text before opening a picker or leaving the page.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        nicknameFocused = false
        commitNickname()
    }
    private func closeAfterSaving() {
        blur()
        closeRequested = true
        if pendingSaves == 0, saveError == nil { dismiss() }
    }
    private func commitNickname() {
        let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { nickname = submittedNickname; return }
        nickname = value
        guard value != submittedNickname else { return }
        submittedNickname = value
        save(.nickname(value))
    }
    private func save(_ change: ProfileChange) {
        pendingSaves += 1
        let previous = saveTask
        saveTask = Task { @MainActor in
            await previous?.value
            let success = await model.updateProfile(change)
            if !success {
                saveError = model.actionError ?? "error.storage"
                model.actionError = nil
                closeRequested = false
                if case .nickname = change { submittedNickname = profile.nickname }
            }
            pendingSaves -= 1
        }
    }
    private func arrow(_ s: CGFloat) -> some View { Image("me_arrow_ic").resizable().frame(width: 14*s, height: 14*s) }
    private func separator(_ s: CGFloat) -> some View { Color.black.opacity(0.15).frame(height: 1/3).padding(.leading, 20) }
    private func row<Value: View>(_ title: String, s: CGFloat, height: CGFloat? = nil, action: @escaping () -> Void, @ViewBuilder value: () -> Value) -> some View {
        Button(action: action) {
            HStack(spacing: 6*s) {
                Text(LocalizedStringKey(title)).foregroundStyle(Color(white: 0.13))
                Spacer()
                value().foregroundStyle(Color(white: 34/255).opacity(0.3))
                arrow(s)
            }.font(.system(size: 16*s)).padding(.horizontal, 15*s).frame(height: height ?? 50*s)
                .background(.white).overlay(alignment: .bottom) { separator(s) }
        }.buttonStyle(.plain)
    }
}

extension UIImage {
    func profileJPEG() -> Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
            .image { _ in draw(in: CGRect(x: 0, y: 0, width: 512, height: 512)) }.jpegData(compressionQuality: 0.75)
    }
}
