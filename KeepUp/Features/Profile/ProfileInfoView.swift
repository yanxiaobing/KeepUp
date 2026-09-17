import SwiftUI

/// PunchCard's existing-user personal information page, with per-field local persistence.
struct ProfileInfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var nicknameFocused = false
    @State private var menu: MenuKind?
    @State private var metric: ProfileMetric?
    @State private var source: ImageSource?
    @State private var photoError = false
    @State private var pendingSaves = 0
    private var profile: UserProfile { model.snapshot.profile ?? UserProfile() }
    private enum MenuKind { case avatar, gender }
    private enum ImageSource: String, Identifiable { case camera, library; var id: String { rawValue } }

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width / 375
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Button { nicknameFocused = false; commitNickname(); dismiss() } label: {
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
                                row("info.avatarLabel", s: s, height: 70*s) { blur(); menu = .avatar } value: {
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
                                row("info.gender", s: s) { blur(); menu = .gender } value: {
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
                if let menu {
                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.5).onTapGesture { self.menu = nil }
                        VStack(spacing: 8*s) {
                            if menu == .avatar {
                                Button("info.camera") {
                                    self.menu = nil
                                    if UIImagePickerController.isSourceTypeAvailable(.camera) { source = .camera } else { photoError = true }
                                }.accessibilityIdentifier("info.camera")
                                Button("info.library") { self.menu = nil; source = .library }.accessibilityIdentifier("info.library")
                            } else {
                                Button("info.male") { self.menu = nil; save(.gender(true)) }.accessibilityIdentifier("profile.info.male")
                                Button("info.female") { self.menu = nil; save(.gender(false)) }.accessibilityIdentifier("profile.info.female")
                            }
                            Button("action.cancel") { self.menu = nil }.foregroundStyle(Color(white: 0.45)).padding(.top, 4*s)
                        }.buttonStyle(ProfileActionStyle(scale: s)).padding(.horizontal, 15*s).padding(.bottom, 34)
                    }.ignoresSafeArea()
                }
                if let metric {
                    ProfileRulerOverlay(metric: metric, value: metric.value(in: profile), scale: s) { value in
                        self.metric = nil
                        guard let value else { return }
                        switch metric { case .year: save(.year(Int(value.rounded()))); case .height: save(.height(value)); case .weight: save(.weight(value)) }
                    }.ignoresSafeArea()
                }
            }.background(KeepUpStyle.theme.ignoresSafeArea(edges: .top))
        }
        .onAppear { nickname = profile.nickname }
        .fullScreenCover(item: $source) { source in
            AvatarPicker(camera: source == .camera, locale: locale) { image in
                self.source = nil
                if let image, let data = image.profileJPEG() { save(.avatar(data)) }
            }.ignoresSafeArea()
        }
        .alert("error.title", isPresented: $photoError) { Button("action.ok", role: .cancel) {} } message: { Text("info.photoError") }
        .interactiveDismissDisabled(nicknameFocused || pendingSaves > 0)
    }
    private func blur() { nicknameFocused = false }
    private func commitNickname() {
        let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != profile.nickname else { nickname = profile.nickname; return }
        save(.nickname(value))
    }
    private func save(_ change: ProfileChange) {
        pendingSaves += 1
        Task { _ = await model.updateProfile(change); pendingSaves -= 1 }
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

struct ProfileActionStyle: ButtonStyle {
    let scale: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 17*scale)).frame(maxWidth: .infinity).frame(height: 56*scale)
            .foregroundStyle(Color(white: 0.13)).background(configuration.isPressed ? Color(white: 0.91) : .white, in: RoundedRectangle(cornerRadius: 12*scale))
    }
}

extension UIImage {
    func profileJPEG() -> Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
            .image { _ in draw(in: CGRect(x: 0, y: 0, width: 512, height: 512)) }.jpegData(compressionQuality: 0.75)
    }
}
