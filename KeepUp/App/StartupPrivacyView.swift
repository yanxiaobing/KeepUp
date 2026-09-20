import SwiftUI

/// Mirrors PunchCard's launch backdrop and bottom privacy panel.
struct StartupPrivacyView: View {
    let onAgree: () -> Void

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
                    // The product owner has deferred policy/agreement links.
                    Text("startup.agreementNotice")
                        .font(.system(size: 11 * scale)).foregroundStyle(Color(hex: 0x666666))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 30 * scale)
                }
                .padding(.top, 100 * scale)
                .padding(.bottom, geometry.safeAreaInsets.bottom == 0 ? 16 : 0)
                .frame(maxWidth: .infinity)
                .background(Color.white.ignoresSafeArea(edges: .bottom))
            }
        }
    }
}
