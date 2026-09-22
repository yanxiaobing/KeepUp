import SwiftUI
import StoreKit

struct MembershipView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isOnboarding = false
    var onClose: (() -> Void)? = nil
    var entryPoint: String? = nil
    private var entry: String { entryPoint ?? (isOnboarding ? "guide" : "vip") }
    @Environment(MembershipStore.self) private var store
    @Environment(IAAPConfigurationStore.self) private var iaap
    private var page: IAAPConfiguration.Page? { iaap.configuration.page(for: entry) }
    private var configuration: MembershipConfiguration { iaap.configuration.membershipConfiguration(for: entry) }
    private var benefits: [IAAPConfiguration.Page.Benefit] {
        page?.displayedBenefits ?? IAAPConfiguration.Page.Benefit.defaults
    }
    private var themeBenefit: IAAPConfiguration.Page.Benefit? { benefits.first { $0.type == "themes" } }
    @State private var themeIndex = 0
    @State private var offerIndex = 0
    @State private var pulse = false
    @State private var pauseOffers = false
    private var canPurchaseSelection: Bool {
        guard configuration.offers.indices.contains(offerIndex) else { return false }
        return !store.busy && store.products[configuration.offers[offerIndex].id] != nil
    }
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
            let bottom = 223*s + max(geometry.safeAreaInsets.bottom, 34)
            ZStack(alignment: .top) {
                Color.white.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if benefits.first?.type != "themes" {
                            Color.clear.frame(height: statusHeight + 44 + 24*s)
                        }
                        ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                            Group {
                                if benefit.type == "themes" {
                                    themes(s, top: index == 0 ? statusHeight : 0,
                                           isFirst: index == 0, benefit: benefit)
                                } else if benefit.type == "noad" {
                                    noAds(s)
                                } else if benefit.type == "cloud" {
                                    cloud(s)
                                }
                            }
                            .accessibilityIdentifier("membership.benefit.\(benefit.type ?? "unknown")")
                            Color.clear.frame(height: benefit.footer ?? 0)
                        }
                        Color.clear.frame(height: 15+bottom)
                    }
                }.ignoresSafeArea().accessibilityIdentifier("membership.benefits")
                ZStack {
                    MembershipHornText(text: localized(store.isPremium ? "membership.active" : "membership.title", locale), first: 18*s, last: 20*s, weight: .semibold)
                        .allowsHitTesting(false)
                    HStack {
                        Button { close() } label: {
                            Image(systemName: "xmark").font(.system(size: 15*s, weight: .medium)).foregroundStyle(.black.opacity(configuration.closeAlpha))
                                .frame(width: 32*s, height: 44).contentShape(Rectangle())
                        }.padding(.leading, -8*s)
                            .opacity(1)
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
            .task(id: configuration.offers.map(\.id)) { await store.load(offers: configuration.offers) }
            .task(id: configuration.carouselInterval) {
                guard !reduceMotion, !freezeAnimation, configuration.carouselInterval > 0 else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(configuration.carouselInterval)) } catch { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        if !pauseOffers, configuration.offers.count > 1 {
                            offerIndex = (offerIndex+1) % configuration.offers.count
                        }
                    }
                }
            }
            .task(id: themeBenefit.map { "themes:\($0.timeInterval ?? configuration.carouselInterval)" }) {
                guard !reduceMotion, !freezeAnimation, let benefit = themeBenefit else { return }
                let interval = benefit.timeInterval ?? configuration.carouselInterval
                guard interval > 0 else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(interval)) }
                    catch { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        themeIndex = (themeIndex + 1) % MembershipTheme.all.count
                    }
                }
            }
            .alert("error.title", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                if store.message == "membership.loadError" || store.message == "membership.unavailable" {
                    Button("action.retry") { Task { await store.load(offers: configuration.offers, cache: false) } }
                }
                Button("action.ok") { store.message = nil }
            } message: { Text(LocalizedStringKey(store.message ?? "error.storage")) }
        }.preferredColorScheme(.light)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !store.busy {
                    Task { await store.load(offers: configuration.offers, cache: false) }
                }
            }
            .onChange(of: configuration.offers.map(\.id)) { oldIDs, newIDs in
                let selectedID = oldIDs.indices.contains(offerIndex) ? oldIDs[offerIndex] : nil
                offerIndex = selectedID.flatMap { newIDs.firstIndex(of: $0) } ?? 0
            }
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }

    private func themes(_ s: CGFloat, top: CGFloat, isFirst: Bool, benefit: IAAPConfiguration.Page.Benefit) -> some View {
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
                        MembershipHornText(text: localized("theme.list", locale), first: 16*s, last: 18*s,
                                           colors: [UIColor(red: 79/255, green: 164/255, blue: 73/255, alpha: 1), UIColor(red: 110/255, green: 36/255, blue: 68/255, alpha: 1)])
                    }.padding(.horizontal, 20*s).frame(height: 18*s).frame(maxHeight: .infinity, alignment: .top).padding(.top, top+(isFirst ? 44 : 0)+24*s)
                }.tag(index)
            }
        }.tabViewStyle(.page(indexDisplayMode: benefit.hidePageControl == false ? .always : .never)).frame(height: 290*s)
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
        VStack(spacing: 12*s) {
            Image(systemName: "icloud").font(.system(size: 64*s, weight: .thin))
                .accessibilityHidden(true)
            Text("iCloud").font(.system(size: 22*s, weight: .semibold))
            Text("membership.cloudDescription")
                .font(.system(size: 12*s)).foregroundStyle(Color(hex: 0x999999))
                .multilineTextAlignment(.center)
        }.foregroundStyle(.black).frame(maxWidth: .infinity).padding(.horizontal, 24*s)
    }
    private func purchaseArea(_ s: CGFloat, bottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            TabView(selection: $offerIndex) {
                ForEach(Array(configuration.offers.enumerated()), id: \.offset) { index, offer in offerCard(offer, s).tag(index) }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 99*s)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 0) {
                        ForEach(configuration.offers.indices, id: \.self) { index in
                            Capsule().fill(.white.opacity(index == offerIndex ? 1 : 0.25)).frame(width: (index == offerIndex ? 10 : 4)*s, height: 4*s)
                        }
                    }.padding(.trailing, 24*s).offset(y: 10*s).opacity(page?.iap.hidePageControl == true ? 0 : 1)
                }
            Button {
                guard configuration.offers.indices.contains(offerIndex) else { return }
                let offer = configuration.offers[offerIndex]
                pauseOffers = true
                Task { await store.purchase(offer); pauseOffers = false; if store.isPremium { close() } }
            } label: {
                HStack(spacing: 12*s) {
                    Text("info.continue").font(.custom("PingFangSC-Semibold", fixedSize: 18*s))
                    Image(systemName: "hand.tap").font(.custom("PingFangSC-Medium", fixedSize: 18*s)).scaleEffect(pulse ? 1.25 : 1)
                }.foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 56*s)
                    .background(.white, in: Capsule()).scaleEffect(pulse ? 1.07 : 1)
            }.buttonStyle(.plain).padding(.horizontal, 24*s).padding(.top, 20*s).disabled(!canPurchaseSelection)
                .accessibilityIdentifier("membership.purchase")
            if page?.hideFuncBtn != true && page?.showGiveUp != false {
                Button { close() } label: {
                    Text("membership.giveUp")
                        .font(.custom("PingFangSC-Regular", fixedSize: 12*s))
                        .foregroundStyle(Color(white: 0.25))
                        .frame(maxWidth: .infinity).frame(minHeight: 44*s)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("membership.skip")
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
                if offer.titleType == "timer" {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let end = Calendar.current.dateInterval(of: .day, for: context.date)?.end ?? context.date
                        let remaining = max(0, Int(end.timeIntervalSince(context.date)))
                        HStack(spacing: 8*s) {
                            Text("membership.todayRemaining")
                            Text(String(format: "%02d:%02d:%02d", remaining / 3600, remaining / 60 % 60, remaining % 60)).monospacedDigit()
                        }
                    }
                } else if offer.titleType == "desc" {
                    Text(offer.description ?? "")
                } else if offer.titleType == "appstoreDesc" || !lifetime {
                    Text(product?.description ?? localized("membership.priceUnavailable", locale))
                } else {
                    Text("membership.lifetime")
                }
            }.font(.custom("PingFangSC-Regular", fixedSize: 14*s)).lineLimit(1)
                .frame(height: 20*s).padding(.top, 15*s)
            HStack(spacing: 6*s) {
                VStack(spacing: 0) { Circle().frame(width: 8*s,height: 8*s); Rectangle().frame(width: 2*s, height: 17*s); Circle().frame(width: 8*s,height: 8*s) }
                VStack(alignment: .leading, spacing: 9*s) {
                    Text(lifetime ? "membership.lifetime" : "membership.fromToday").font(.custom("PingFangSC-Semibold", fixedSize: 12*s))
                    Text(lifetime ? localized("membership.healthier", locale) : (product?.displayName ?? localized("membership.priceUnavailable", locale))).font(.custom("PingFangSC-Regular", fixedSize: 12*s))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8*s) {
                    Text(lifetime ? localized("membership.lifetime", locale) : (product?.displayName ?? localized("membership.priceUnavailable", locale)))
                        .font(.custom("PingFangSC-Semibold", fixedSize: 10*s)).padding(.horizontal, 8*s).frame(height: 18*s).background(Color(hex: 0x34C759), in: Capsule())
                    Text(store.productDetails(for: offer.id)?.priceDescription(locale: locale) ?? product.map { $0.displayPrice + subscriptionPeriod($0) } ?? localized("membership.priceUnavailable", locale)).font(.custom("PingFangSC-Regular", fixedSize: 12*s)).opacity(configuration.priceAlpha)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("membership.price")
                }
            }.frame(height: 44*s).padding(.horizontal, 24*s)
        }.foregroundStyle(.white).frame(maxHeight: .infinity, alignment: .top)
    }
    private func subscriptionPeriod(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.calendar?.locale = locale
        formatter.unitsStyle = .full
        var components = DateComponents()
        switch period.unit {
        case .day: components.day = period.value
        case .week: components.weekOfMonth = period.value
        case .month: components.month = period.value
        case .year: components.year = period.value
        @unknown default: return ""
        }
        return formatter.string(from: components).map { "/" + $0 } ?? ""
    }
}
