import SwiftUI

struct MembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isOnboarding = false
    var onClose: (() -> Void)? = nil
    @State private var store = MembershipStore()
    @State private var themeIndex = 0
    @State private var offerIndex = 0
    @State private var pulse = false
    @State private var pauseOffers = false
    private var theme: MembershipTheme { MembershipTheme.all[themeIndex] }
    private var freezeAnimation: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width/375
            let statusHeight = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.statusBarManager?.statusBarFrame.height ?? geometry.safeAreaInsets.top
            let bottom = (isOnboarding ? 211 : 179)*s + max(geometry.safeAreaInsets.bottom, 34)
            ZStack(alignment: .top) {
                Color.white.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        themes(s, top: statusHeight)
                        Color.clear.frame(height: 30)
                        noAds(s)
                        Color.clear.frame(height: 50)
                        cloud(s)
                        Color.clear.frame(height: 15+bottom)
                    }
                }.ignoresSafeArea().accessibilityIdentifier("membership.benefits")
                ZStack {
                    MembershipHornText(text: localized(store.isPremium ? "membership.active" : "membership.title", locale), first: 18*s, last: 20*s, weight: .semibold)
                        .allowsHitTesting(false)
                    HStack {
                        Button { close() } label: {
                            Image(systemName: "xmark").font(.system(size: 15*s, weight: .medium)).foregroundStyle(.black.opacity(0.3 * store.configuration.closeAlpha))
                                .frame(width: 32*s, height: 44).contentShape(Rectangle())
                        }.padding(.leading, -8*s)
                            .opacity(isOnboarding && !store.isPremium ? 0 : 1).disabled(isOnboarding && !store.isPremium)
                            .accessibilityIdentifier("membership.close")
                        Spacer()
                        Button("membership.restore") { Task { await store.restore(); if store.isPremium { close() } } }
                            .font(.custom("PingFangSC-Regular", fixedSize: 15*s)).foregroundStyle(.black.opacity(0.5))
                            .disabled(store.busy).opacity(store.isPremium ? 0 : 1).accessibilityIdentifier("membership.restore")
                    }
                }.padding(.horizontal, 15*s).frame(height: 44).offset(y: statusHeight-geometry.safeAreaInsets.top).zIndex(2)

                if !store.isPremium {
                    VStack { Spacer(minLength: 0); purchaseArea(s, bottom: max(geometry.safeAreaInsets.bottom, 34)) }.ignoresSafeArea(edges: .bottom)
                }
            }
            .task { await store.load() }
            .task {
                guard !reduceMotion, !freezeAnimation else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        themeIndex = (themeIndex+1) % MembershipTheme.all.count
                        if !pauseOffers, store.configuration.offers.count > 1, !isOnboarding {
                            offerIndex = (offerIndex+1) % store.configuration.offers.count
                        }
                    }
                }
            }
            .alert("error.title", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("action.ok") { store.message = nil }
            } message: { Text(LocalizedStringKey(store.message ?? "error.storage")) }
        }.preferredColorScheme(.light)
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }

    private func themes(_ s: CGFloat, top: CGFloat) -> some View {
        TabView(selection: $themeIndex) {
            ForEach(Array(MembershipTheme.all.enumerated()), id: \.offset) { index, theme in
                ZStack(alignment: .bottom) {
                    Color(hex: theme.hex)
                    Image(theme.image).resizable().frame(height: 136*s)
                    LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom).frame(height: 40*s)
                    HStack {
                        Text(locale.identifier.hasPrefix("zh") ? theme.name + " (" + theme.english + ")" : theme.english)
                            .font(.custom("PingFangSC-Regular", fixedSize: 16*s)).foregroundStyle(.black.opacity(0.3))
                        Spacer(minLength: 5)
                        MembershipHornText(text: localized(store.isPremium ? "membership.unlocked" : "membership.unlock", locale), first: 16*s, last: 18*s,
                                           colors: [UIColor(red: 79/255, green: 164/255, blue: 73/255, alpha: 1), UIColor(red: 110/255, green: 36/255, blue: 68/255, alpha: 1)])
                    }.padding(.horizontal, 20*s).frame(height: 18*s).frame(maxHeight: .infinity, alignment: .top).padding(.top, top+44+24*s)
                }.tag(index)
            }
        }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 290*s)
    }
    private func noAds(_ s: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16*s) {
                MembershipHornText(text: localized("membership.noAds", locale), first: 26*s, last: 20*s, weight: .semibold).frame(maxWidth: .infinity)
                MembershipHornText(text: localized("membership.focus", locale), first: 20*s, last: 26*s, weight: .semibold).frame(maxWidth: .infinity)
            }.padding(.horizontal, 30*s).padding(.top, 10*s)
            Spacer(minLength: 0)
            Text("membership.noAdsDescription").font(.custom("PingFangSC-Regular", fixedSize: 12*s)).foregroundStyle(Color(hex: 0x999999)).padding(.bottom, 20*s)
        }.frame(height: 85*s)
    }
    private func cloud(_ s: CGFloat) -> some View {
        ZStack {
            Image(systemName: "icloud").font(.system(size: 110*s, weight: .thin)).imageScale(.small)
            Text(verbatim: "iCloud").font(.system(size: 15*s, weight: .heavy, design: .monospaced)).offset(y: 15*s)
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 20*s, weight: .bold)).imageScale(.small).offset(x: 15*s, y: -14*s)
            VStack(spacing: 8*s) {
                HStack(spacing: 130*s) {
                    MembershipHornText(text: localized("membership.private", locale), first: 25*s, last: 18*s).frame(maxWidth: .infinity)
                    MembershipHornText(text: localized("membership.control", locale), first: 18*s, last: 25*s).frame(maxWidth: .infinity)
                }.padding(.horizontal, 50*s)
                HStack(spacing: 150*s) {
                    MembershipHornText(text: localized("membership.secure", locale), first: 25*s, last: 18*s).frame(maxWidth: .infinity)
                    MembershipHornText(text: localized("membership.sync", locale), first: 18*s, last: 25*s).frame(maxWidth: .infinity)
                }.padding(.horizontal, 40*s)
            }
        }.frame(height: 80*s)
    }
    private func purchaseArea(_ s: CGFloat, bottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            TabView(selection: $offerIndex) {
                ForEach(Array(store.configuration.offers.enumerated()), id: \.offset) { index, offer in offerCard(offer, s).tag(index) }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 99*s)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 0) {
                        ForEach(store.configuration.offers.indices, id: \.self) { index in
                            Capsule().fill(.white.opacity(index == offerIndex ? 1 : 0.25)).frame(width: (index == offerIndex ? 10 : 4)*s, height: 4*s)
                        }
                    }.padding(.trailing, 24*s).offset(y: 10*s)
                }
            Button {
                pauseOffers = true
                guard store.configuration.offers.indices.contains(offerIndex) else { return }
                Task { await store.purchase(store.configuration.offers[offerIndex]); pauseOffers = false; if store.isPremium { close() } }
            } label: {
                HStack(spacing: 12*s) {
                    Text("info.continue").font(.custom("PingFangSC-Semibold", fixedSize: 18*s))
                    Image(systemName: "hand.tap").font(.custom("PingFangSC-Medium", fixedSize: 18*s)).scaleEffect(pulse ? 1.25 : 1)
                }.foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 56*s)
                    .background(.white, in: Capsule()).scaleEffect(pulse ? 1.07 : 1)
            }.buttonStyle(.plain).padding(.horizontal, 24*s).padding(.top, 20*s).disabled(store.busy)
                .accessibilityIdentifier("membership.purchase")
            if isOnboarding {
                Button("membership.giveUp") { close() }.font(.custom("PingFangSC-Regular", fixedSize: 12*s)).foregroundStyle(.white.opacity(0.5))
                    .frame(height: 16*s).padding(.top, 16*s).accessibilityIdentifier("membership.skip")
            }
        }.padding(.bottom, bottom)
            .background {
                LinearGradient(colors: [Color(hex: theme.hex), .white], startPoint: .top, endPoint: .bottom)
                    .overlay(LinearGradient(colors: [.black.opacity(0.5), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            }.clipShape(UnevenRoundedRectangle(topLeadingRadius: 20*s, topTrailingRadius: 20*s))
            .onAppear { if !reduceMotion, !freezeAnimation { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true } } }
    }
    private func offerCard(_ offer: MembershipConfiguration.Offer, _ s: CGFloat) -> some View {
        let product = store.products[offer.id]
        let lifetime = offer.kind == "lifetime"
        return VStack(spacing: 20*s) {
            Group {
                if lifetime {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 8*s) {
                            Text("membership.countdown").font(.custom("PingFangSC-Regular", fixedSize: 14*s)).lineLimit(1).minimumScaleFactor(0.6)
                            countdown(context.date, s)
                        }
                    }
                } else {
                    Text(product?.description ?? localized("membership.period.\(offer.months)", locale)).font(.custom("PingFangSC-Regular", fixedSize: 15*s)).lineLimit(1)
                }
            }.frame(height: 20*s).padding(.top, 15*s)
            HStack(spacing: 6*s) {
                VStack(spacing: 0) { Circle().frame(width: 8*s,height: 8*s); Rectangle().frame(width: 2*s, height: 17*s); Circle().frame(width: 8*s,height: 8*s) }
                VStack(alignment: .leading, spacing: 9*s) {
                    Text(lifetime ? "membership.lifetime" : "membership.fromToday").font(.custom("PingFangSC-Semibold", fixedSize: 12*s))
                    Text(lifetime ? localized("membership.healthier", locale) : expiry(months: offer.months)).font(.custom("PingFangSC-Regular", fixedSize: 12*s))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8*s) {
                    Text(lifetime ? localized("membership.limited", locale) : (product?.displayName ?? localized("membership.period.\(offer.months)", locale)))
                        .font(.custom("PingFangSC-Semibold", fixedSize: 10*s)).padding(.horizontal, 8*s).frame(height: 18*s).background(Color(hex: 0x34C759), in: Capsule())
                    Text(product.map { $0.displayPrice + (lifetime ? "" : "/" + localized("membership.unit.\(offer.months)", locale)) } ?? localized("membership.priceUnavailable", locale)).font(.custom("PingFangSC-Regular", fixedSize: 12*s)).opacity(store.configuration.priceAlpha)
                        .accessibilityIdentifier("membership.price")
                }
            }.frame(height: 44*s).padding(.horizontal, 24*s)
        }.foregroundStyle(.white).frame(maxHeight: .infinity, alignment: .top)
    }
    private func expiry(months: Int) -> String {
        let date = Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = locale.identifier.hasPrefix("zh") ? "yyyy.MM.dd" : "MMM d, yyyy"
        return localized("membership.until", locale) + formatter.string(from: date)
    }
    private func countdown(_ date: Date, _ s: CGFloat) -> some View {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        let remaining = max(0, Int(tomorrow.timeIntervalSince(date)))
        let values = [remaining/3600, remaining%3600/60, remaining%60]
        return HStack(spacing: 0) {
            ForEach(0..<3) { index in
                if index > 0 { Text(verbatim: ":").frame(width: 11*s) }
                Text(String(format: "%02d", values[index])).frame(width: 18*s, height: 20*s)
                    .background(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.25)], startPoint: .top, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 3*s))
            }
        }.font(.system(size: 12*s, design: .monospaced)).fixedSize()
    }
}
