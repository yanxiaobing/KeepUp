import SwiftUI

/// Coordinates and dimensions come from PunchCard/Module/UserInfo (375 pt design).
struct UserInfoFlowView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    let initial: UserProfile?
    let allowCancel: Bool
    let onComplete: (UserProfile) async -> Bool
    @State private var profile: UserProfile
    @State private var bodyStep = false
    @State private var selectedMetrics: Set<ProfileMetric> = []
    @State private var metric: ProfileMetric?
    @State private var confirming = false
    @State private var saving = false
    @State private var showAvatarActions = false
    @State private var avatarSource: AvatarSource?
    @State private var photoError = false
    @State private var nicknameFocused = false

    init(initial: UserProfile? = nil, allowCancel: Bool = false, onComplete: @escaping (UserProfile) async -> Bool) {
        self.initial = initial; self.allowCancel = allowCancel; self.onComplete = onComplete
        _profile = State(initialValue: initial ?? UserProfile())
        _selectedMetrics = State(initialValue: initial == nil ? [] : Set(ProfileMetric.allCases))
    }

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width / 375
            ZStack {
                LinearGradient(colors: [Color(hex: 0xF0EFFA), Color(hex: 0xF5F4FB), Color(hex: 0xFAFAFD)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack {
                        Text("info.title").font(.custom("PingFangSC-Medium", fixedSize: 17*s)).foregroundStyle(Color(hex: 0x0F0F0F))
                        HStack {
                            if bodyStep || allowCancel {
                                Button { nicknameFocused = false; if bodyStep { withAnimation(.easeInOut(duration: 0.3)) { bodyStep = false } } else { dismiss() } } label: {
                                    Image(systemName: bodyStep ? "chevron.left" : "xmark").font(.custom("PingFangSC-Medium", fixedSize: 14*s))
                                }.accessibilityIdentifier("info.back").accessibilityLabel(Text(bodyStep ? "action.back" : "action.cancel"))
                            }
                            Spacer()
                            Button(bodyStep ? "info.done" : "info.continue") {
                                nicknameFocused = false
                                if bodyStep { confirming = true } else { withAnimation(.easeInOut(duration: 0.3)) { bodyStep = true } }
                            }.font(.custom("PingFangSC-Medium", fixedSize: 15*s)).accessibilityIdentifier("info.next")
                        }.padding(.horizontal, 16*s).foregroundStyle(Color(hex: 0x6C63FF))
                    }.frame(height: 52*s)
                    GeometryReader { page in
                        HStack(spacing: 0) {
                            ScrollView(showsIndicators: false) {
                                ZStack(alignment: .topLeading) { Color.clear; socialItems(s) }.frame(width: geometry.size.width, height: 709*s)
                            }.scrollDismissesKeyboard(.interactively).frame(width: geometry.size.width).accessibilityHidden(bodyStep)
                            ScrollView(showsIndicators: false) {
                                ZStack(alignment: .topLeading) { Color.clear; bodyItems(s) }.frame(width: geometry.size.width, height: 722*s)
                            }.frame(width: geometry.size.width).accessibilityHidden(!bodyStep)
                        }.frame(width: geometry.size.width*2, height: page.size.height).offset(x: bodyStep ? -geometry.size.width : 0)
                    }.clipped()

                }.ignoresSafeArea(.container, edges: .bottom)
                if let metric {
                    ProfileRulerOverlay(metric: metric, value: metric.value(in: profile), scale: s) { value in
                        if let value { metric.set(value, in: &profile); selectedMetrics.insert(metric) }
                        self.metric = nil
                    }.ignoresSafeArea()
                }
                if confirming { confirmation(s).ignoresSafeArea() }
                if showAvatarActions { avatarActions(s).ignoresSafeArea() }
            }
            .fullScreenCover(item: $avatarSource) { source in
                AvatarPicker(camera: source == .camera, locale: locale) { image in
                    if let image {
                        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
                        profile.avatar = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 512, height: 512)) }.jpegData(compressionQuality: 0.75)
                    }
                    avatarSource = nil
                }.ignoresSafeArea()
            }
            .task { if initial == nil { nicknameFocused = true } }
            .alert("error.title", isPresented: $photoError) { Button("action.ok", role: .cancel) {} } message: { Text("info.photoError") }
        }.toolbar(.hidden, for: .navigationBar).interactiveDismissDisabled(!allowCancel)
    }

    private enum AvatarSource: String, Identifiable { case camera, library; var id: String { rawValue } }
    private func avatarActions(_ s: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5).onTapGesture { showAvatarActions = false }
            VStack(spacing: 8*s) {
                Button("info.camera") {
                    showAvatarActions = false
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { avatarSource = .camera } else { photoError = true }
                }.accessibilityIdentifier("info.camera")
                Button("info.library") { showAvatarActions = false; avatarSource = .library }.accessibilityIdentifier("info.library")
                Button("action.cancel") { showAvatarActions = false }.foregroundStyle(Color(hex: 0x48484D).opacity(0.6)).padding(.top, 4*s)
            }.buttonStyle(AvatarActionStyle(scale: s)).padding(.horizontal, 15*s).padding(.bottom, 34)
        }
    }
    private func socialItems(_ s: CGFloat) -> some View {
        Group {
            ZStack(alignment: .topLeading) {
                infoCard(title: "info.nicknameTitle", s: s) {
                    ProfileNicknameField(text: $profile.nickname, focused: $nicknameFocused,
                                         placeholder: localized("info.nicknamePlaceholder", locale), scale: s)

                }.offset(y: 24*s)
                artwork("user_info_item_bg_nickname", 242, 204, s)
            }.frame(width: 242*s, height: 204*s).offset(x: 95*s, y: 10*s)
            ZStack(alignment: .topLeading) {
                Button { nicknameFocused = false; showAvatarActions = true } label: {
                    VStack(spacing: 6*s) {
                        if let data = profile.avatar, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 94*s, height: 94*s).clipped().clipShape(RoundedRectangle(cornerRadius: 12*s))
                        } else {
                            Image(systemName: "camera.fill").font(.custom("PingFangSC-Medium", fixedSize: 28*s)).foregroundStyle(Color(hex: 0x8070FF).opacity(0.72))
                                .frame(width: 94*s, height: 73*s).background(Color(hex: 0xEBE8FF), in: RoundedRectangle(cornerRadius: 12*s))
                            Text("info.avatarHint").font(.custom("PingFangSC-Medium", fixedSize: 12*s)).foregroundStyle(Color(hex: 0x666666)).frame(height: 14*s)
                        }
                    }.frame(width: 108*s, height: 108*s).background(.white, in: RoundedRectangle(cornerRadius: 18*s))
                        .shadow(color: Color(hex: 0x625CA8).opacity(0.1), radius: 22*s, y: 10*s)
                }.buttonStyle(.plain).offset(x: 91*s, y: 18*s).accessibilityIdentifier("info.avatar")
                artwork("user_info_item_bg_avator", 199, 224, s)
            }.frame(width: 199*s, height: 224*s).offset(x: 32*s, y: 232*s)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 62*s) { gender(true, s); gender(false, s) }
                artwork("user_info_item_bg_sex", 182, 211, s)
            }.frame(width: 182*s, height: 211*s).offset(x: 172*s, y: 474*s)
        }
    }

    private func gender(_ male: Bool, _ s: CGFloat) -> some View {
        let selected = profile.isMale == male
        let name = "user_info_gender_" + (male ? "male" : "female") + (selected ? "" : "_unselected")
        return Button { nicknameFocused = false; profile.isMale = male } label: {
            Image(name).resizable().scaledToFit().frame(width: 34*s, height: 52*s).offset(y: 2*s)
                .frame(width: 60*s, height: 77*s).background(.white.opacity(selected ? 1 : 0.96), in: RoundedRectangle(cornerRadius: 16*s))
                .overlay(RoundedRectangle(cornerRadius: 16*s).stroke(Color(hex: 0xA79CFF).opacity(selected ? 0.55 : 0), lineWidth: 1.2*s))
                .shadow(color: Color(hex: 0x625CA8).opacity(0.08), radius: 18*s, y: 10*s)
        }.buttonStyle(.plain).rotationEffect(.radians(male ? -0.03 : -0.01))
            .accessibilityLabel(Text(male ? "info.male" : "info.female")).accessibilityIdentifier(male ? "info.male" : "info.female")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bodyItems(_ s: CGFloat) -> some View {
        Group {
            metricItem(.year, image: "user_info_item_bg_year", width: 257, height: 185, cardX: 117, cardY: 19, s: s).offset(x: 32*s, y: 24*s)
            metricItem(.height, image: "user_info_item_bg_height", width: 228, height: 184, cardX: 0, cardY: 4, s: s).offset(x: 116*s, y: 255*s)
            metricItem(.weight, image: "user_info_item_bg_weight", width: 338, height: 195, cardX: 198, cardY: 23, s: s).offset(x: 13*s, y: 503*s)
        }
    }
    private func metricItem(_ kind: ProfileMetric, image: String, width: CGFloat, height: CGFloat, cardX: CGFloat, cardY: CGFloat, s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Button { nicknameFocused = false; metric = kind } label: {
                infoCard(title: kind.titleKey, s: s) {
                    ProfileReadOnlyField(value: selectedMetrics.contains(kind) ? kind.display(kind.value(in: profile), locale: locale) : nil,
                                         placeholder: localized(kind.placeholderKey, locale), scale: s)

                }
            }.buttonStyle(.plain).offset(x: cardX*s, y: cardY*s).accessibilityIdentifier("info.\(kind.rawValue)").accessibilityLabel(Text(LocalizedStringKey(kind.titleKey)))
            artwork(image, width, height, s)
        }.frame(width: width*s, height: height*s)
    }
    private func infoCard<Content: View>(title: String, s: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18*s).fill(.white).shadow(color: Color(hex: 0x625CA8).opacity(0.1), radius: 22*s, y: 10*s)
            ProfileOriginalLabel(text: localized(title, locale), size: 12*s, medium: true)
                .frame(width: 116*s, height: 14*s, alignment: .leading).offset(x: 12*s, y: 12*s)

            Color(hex: 0xDFDFDF).opacity(0.9).frame(width: 116*s, height: 0.75*s).offset(x: 12*s, y: 32*s)
            content().tint(Color(hex: 0x6C63FF)).frame(width: 116*s, height: 16*s).offset(x: 12*s, y: 41*s)
        }.frame(width: 140*s, height: 70*s)
    }
    private func artwork(_ name: String, _ width: CGFloat, _ height: CGFloat, _ s: CGFloat) -> some View {
        Image(name).resizable().scaledToFit().frame(width: width*s, height: height*s).allowsHitTesting(false).accessibilityHidden(true)
    }
    private func confirmation(_ s: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.7).onTapGesture { if !saving { confirming = false } }
            VStack(spacing: 0) {
                Text("info.important").font(.custom("PingFangSC-Medium", fixedSize: 18*s)).frame(height: 45*s)
                Divider()
                ProfileOriginalLabel(text: localized("info.confirmHint", locale), size: 12*s, color: UIColor(white: 0.2, alpha: 0.8), multiline: true)
                    .fixedSize(horizontal: false, vertical: true).padding(15*s)

                confirmRow("info.avatarLabel", value: "info.none", s: s, avatar: true)
                confirmRow("info.nicknameLabel", value: profile.nickname.isEmpty ? localized("profile.nickname", locale) : profile.nickname, s: s)
                confirmRow("info.gender", value: localized(profile.isMale ? "info.male" : "info.female", locale), s: s)
                confirmRow("info.year", value: String(profile.year), s: s)
                confirmRow("info.heightLabel", value: String(format: "%.1f", profile.height), s: s)
                confirmRow("info.weightLabel", value: String(format: "%.1f", profile.weight), s: s)
                HStack(spacing: 0) {
                    Button("info.reconsider") { confirming = false }.font(.custom("PingFangSC-Regular", fixedSize: 15*s)).frame(maxWidth: .infinity)
                    Rectangle().fill(.black.opacity(0.12)).frame(width: 1/3)
                    Button { saving = true; Task { if await onComplete(profile) { dismiss() }; saving = false } } label: {
                        if saving { ProgressView() } else { Text("info.confirm").font(.custom("PingFangSC-Medium", fixedSize: 15*s)) }
                    }.frame(maxWidth: .infinity).accessibilityIdentifier("info.confirm")
                }.frame(height: 60*s).disabled(saving)
            }.foregroundStyle(Color(hex: 0x333333)).background(.white, in: RoundedRectangle(cornerRadius: 12*s)).clipShape(RoundedRectangle(cornerRadius: 12*s))
                .padding(.horizontal, 32*s)
        }.accessibilityElement(children: .contain)
    }
    private func confirmRow(_ key: String, value: String, s: CGFloat, avatar: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                ProfileOriginalLabel(text: localized(key, locale), size: 15*s)
                Spacer()
                if avatar, let data = profile.avatar, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 50*s, height: 50*s).clipShape(Circle())
                } else { ProfileOriginalLabel(text: avatar ? localized(value, locale) : value, size: 15*s, color: UIColor(white: 0.4, alpha: 1)) }
            }.font(.custom("PingFangSC-Regular", fixedSize: 15*s)).padding(.horizontal, 15*s).frame(height: (avatar ? 60 : 45)*s)
            Divider()
        }
    }
}

func localized(_ key: String, _ locale: Locale) -> String {
    let language = locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
    let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}

private struct AvatarActionStyle: ButtonStyle {
    let scale: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.custom("PingFangSC-Regular", fixedSize: 17*scale)).frame(maxWidth: .infinity).frame(height: 56*scale)
            .foregroundStyle(Color(hex: 0x48484D)).background(configuration.isPressed ? Color(white: 233/255) : .white, in: RoundedRectangle(cornerRadius: 12*scale))
    }
}
