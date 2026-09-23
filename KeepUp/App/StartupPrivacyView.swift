import SwiftUI
import SafariServices

enum LegalDocument: String, Identifiable {
    case privacy, agreement

    var id: String { rawValue }

    static func from(_ url: URL) -> Self? {
        guard url.scheme == "https", url.host == "assets.xbingo.top",
              url.path.hasPrefix("/keep-up/pro/pages/") else { return nil }
        switch url.lastPathComponent {
        case "privacy.html": return .privacy
        case "agreement.html": return .agreement
        default: return nil
        }
    }

    func url(for locale: Locale) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "assets.xbingo.top"
        components.path = "/keep-up/pro/pages/\(rawValue).html"
        components.queryItems = [URLQueryItem(name: "lang", value: locale.identifier.lowercased().hasPrefix("zh") ? "zh-Hans" : "en")]
        return components.url!
    }
}

struct LegalDocumentSafariView: UIViewControllerRepresentable {
    let document: LegalDocument
    let locale: Locale

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: document.url(for: locale))
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Mirrors PunchCard's launch backdrop and bottom privacy panel.
struct StartupPrivacyView: View {
    let onAgree: () -> Void
    @Environment(\.locale) private var locale
    @State private var selectedLegalDocument: LegalDocument?

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 375
            ZStack(alignment: .bottom) {
                Color.white.ignoresSafeArea()
                VStack(spacing: 8) {
                    Image("app_icon").resizable().scaledToFit().frame(width: 120, height: 120)
                    Text(verbatim: "KeepUp").font(.system(size: 24)).foregroundStyle(.black.opacity(0.85))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 150)
                Text("startup.slogan")
                    .font(.system(size: 17)).foregroundStyle(.black.opacity(0.75))
                    .padding(.bottom, 125)
                VStack(spacing: 20 * scale) {
                    Button(action: onAgree) {
                        Text("startup.agree").font(.system(size: 15 * scale, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xFDE2C7))
                            .frame(width: 260 * scale, height: 44 * scale)
                            .background(LinearGradient(colors: [Color(hex: 0x4F4F4F), Color(hex: 0x252220)],
                                                       startPoint: .leading, endPoint: .trailing), in: Capsule())
                    }.accessibilityIdentifier("startup.agree")
                    Text("startup.agreementNotice")
                        .font(.system(size: 11 * scale)).foregroundStyle(Color(hex: 0x666666))
                        .tint(Color(hex: 0x007AFF))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 30 * scale)
                        .environment(\.openURL, OpenURLAction { url in
                            guard let document = LegalDocument.from(url) else { return .systemAction }
                            selectedLegalDocument = document
                            return .handled
                        })
                }
                .padding(.top, 100 * scale)
                .padding(.bottom, geometry.safeAreaInsets.bottom == 0 ? 16 : 0)
                .frame(maxWidth: .infinity)
                .background(Color.white.ignoresSafeArea(edges: .bottom))
            }
        }
        .sheet(item: $selectedLegalDocument) { document in
            LegalDocumentSafariView(document: document, locale: locale)
        }
    }
}
