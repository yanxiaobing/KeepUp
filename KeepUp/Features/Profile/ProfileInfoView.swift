import SwiftUI

/// PunchCard's existing-user personal information page, with per-field local persistence.
struct ProfileInfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var nicknameFocused = false
    @State private var motto = ""
    @State private var mottoFocused = false
    @State private var pendingSource: ImageSource?
    @State private var sheetKind: MenuKind?
    @State private var metric: ProfileMetric?
    @State private var source: ImageSource?
    @State private var photoError = false
    @State private var pendingSaves = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var submittedNickname = ""
    @State private var submittedMotto = ""
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
                    ScrollView {
                        VStack(spacing: 16*s) {
                            VStack(spacing: 0) {
                                row("info.avatarLabel", s: s, height: 88*s) { blur(); sheetKind = .avatar } value: {
                                    if let data = profile.avatar, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFill().frame(width: 60*s, height: 60*s).clipShape(Circle())
                                    } else {
                                        Image("user_default_head").resizable().scaledToFill()
                                            .frame(width: 60*s, height: 60*s).clipShape(Circle())
                                    }
                                }.accessibilityIdentifier("profile.info.avatar")
                                HStack(spacing: 6*s) {
                                    Text("info.nicknameLabel").foregroundStyle(.primary)
                                    Spacer()
                                    ProfileNicknameField(text: $nickname, focused: $nicknameFocused,
                                                         placeholder: localized("profile.nickname", locale), scale: s,
                                                         settingsStyle: true, onCommit: commitNickname)
                                        .frame(maxWidth: 190*s, minHeight: 56*s)
                                    arrow(s)
                                }.font(.system(size: 16*s)).padding(.horizontal, 15*s).frame(height: 56*s)
                                    .background(Color(.secondarySystemGroupedBackground)).overlay(alignment: .bottom) { separator(s) }
                                    .contentShape(Rectangle()).onTapGesture { nicknameFocused = true }
                                HStack(spacing: 6*s) {
                                    Text("profile.motto").foregroundStyle(.primary)
                                    Spacer()
                                    ProfileNicknameField(text: $motto, focused: $mottoFocused,
                                                         placeholder: localized("profile.defaultMotto", locale), scale: s,
                                                         maxLength: 40, fieldIdentifier: "info.motto",
                                                         selectAllOnFocus: true, settingsStyle: true, onCommit: commitMotto)
                                        .frame(maxWidth: 220*s, minHeight: 56*s)
                                    arrow(s)
                                }.font(.system(size: 16*s)).padding(.horizontal, 15*s).frame(height: 56*s)
                                    .background(Color(.secondarySystemGroupedBackground)).overlay(alignment: .bottom) { separator(s) }
                                    .contentShape(Rectangle()).onTapGesture { mottoFocused = true }
                                row("info.gender", s: s, showsSeparator: false) { blur(); sheetKind = .gender } value: {
                                    Text(LocalizedStringKey(profile.isMale ? "info.male" : "info.female"))
                                }.accessibilityIdentifier("profile.info.gender")
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16*s))
                            VStack(spacing: 0) {
                                ForEach(ProfileMetric.allCases) { kind in
                                    row(kind == .year ? "info.year" : kind == .height ? "info.heightLabel" : "info.weightLabel", s: s, showsSeparator: kind != .weight) {
                                        blur(); metric = kind
                                    } value: {
                                        Text(kind == .year ? String(profile.year) : kind.value(in: profile).formatted(.number.precision(.fractionLength(1)).locale(locale)))
                                    }.accessibilityIdentifier("profile.info.\(kind.rawValue)")
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16*s))
                        }
                        .padding(.horizontal, 16*s)
                        .padding(.top, 16*s)
                        .padding(.bottom, 24*s)
                    }
                    .scrollIndicators(.hidden)
                    .scrollEdgeEffectHidden(true, for: .all)
                    .scrollDismissesKeyboard(.interactively)
                }
                if let metric {
                    ProfileRulerOverlay(metric: metric, value: metric.value(in: profile), scale: s) { value in
                        self.metric = nil
                        guard let value else { return }
                        switch metric { case .year: save(.year(Int(value.rounded()))); case .height: save(.height(value)); case .weight: save(.weight(value)) }
                    }.id(metric).ignoresSafeArea()
                }
            }.background {
                LinearGradient(colors: [KeepUpStyle.theme, .white], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .navigationTitle("profile.personalInfo")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeAfterSaving) {
                    Image(systemName: "chevron.left")
                }
                .tint(.primary)
                .disabled(metric != nil || closeRequested)
                .accessibilityLabel(Text("action.back"))
                .accessibilityIdentifier("profile.info.back")
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            nickname = profile.nickname
            submittedNickname = profile.nickname
            motto = profile.motto ?? localized("profile.defaultMotto", locale)
            submittedMotto = motto
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
    }
    private func blur() {
        // Commit marked text before opening a picker or leaving the page.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        nicknameFocused = false
        mottoFocused = false
        commitNickname()
        commitMotto()
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
    private func commitMotto() {
        let value = motto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { motto = submittedMotto; return }
        motto = value
        guard value != submittedMotto else { return }
        submittedMotto = value
        save(.motto(value))
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
                if case .motto = change {
                    submittedMotto = profile.motto ?? localized("profile.defaultMotto", locale)
                    motto = submittedMotto
                }
            }
            pendingSaves -= 1
        }
    }
    private func arrow(_ s: CGFloat) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12*s, weight: .semibold))
            .foregroundStyle(Color(white: 0.65))
            .frame(width: 14*s, height: 14*s)
            .accessibilityHidden(true)
    }
    private func separator(_ s: CGFloat) -> some View { Color.black.opacity(0.08).frame(height: 1/3).padding(.horizontal, 16*s) }
    private func row<Value: View>(_ title: String, s: CGFloat, height: CGFloat? = nil, showsSeparator: Bool = true, action: @escaping () -> Void, @ViewBuilder value: () -> Value) -> some View {
        Button(action: action) {
            HStack(spacing: 6*s) {
                Text(LocalizedStringKey(title)).foregroundStyle(.primary)
                Spacer()
                value().foregroundStyle(.secondary)
                arrow(s)
            }.font(.system(size: 16*s)).padding(.horizontal, 15*s).frame(height: height ?? 56*s)
                .background(Color(.secondarySystemGroupedBackground))
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { if showsSeparator { separator(s) } }
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
