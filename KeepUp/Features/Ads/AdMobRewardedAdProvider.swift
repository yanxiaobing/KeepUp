import UIKit

/// Reference RewardService responsibilities: eligibility, preloading and presentation.
/// Loader owns SDK objects and cache; controller owns terminal events and rewards.
@MainActor final class AdMobRewardedAdProvider: RewardedAdProvider {
    let providerID = "admob"
    private let appID: String?
    private let privacyAllowsAds: @MainActor () -> Bool
    private let presenter: @MainActor () -> UIViewController?
    private let loader: RewardedAdLoader
    private var activeRequest: UUID?
    private var receive: (@MainActor (RewardedAdEvent) -> Void)?
    private var rewardedAd: (any LoadedRewardedAd)?
    private var loadTask: Task<Void, Never>?
    private let presentationGate: FullScreenAdGate
    private var presentationLease: UUID?

    init(appID: String? = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
         privacyAllowsAds: @escaping @MainActor () -> Bool,
         presenter: @escaping @MainActor () -> UIViewController? = AdMobRewardedAdProvider.activePresenter,
         presentationGate: FullScreenAdGate? = nil, loader: RewardedAdLoader? = nil) {
        self.appID = appID
        self.privacyAllowsAds = privacyAllowsAds
        self.presenter = presenter
        self.presentationGate = presentationGate ?? .shared
        self.loader = loader ?? RewardedAdLoader(source: AdMobRewardedAdLoader())
    }

    private func canLoad(_ placement: RewardedAdPlacement) -> Bool {
        privacyAllowsAds() && placement.providerID == providerID && placement.isConfigured
            && appID.map(Self.isAppID) == true
            && Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String == appID
    }

    func preload(placement: RewardedAdPlacement) async -> Bool {
        guard canLoad(placement) else { return false }
        do {
            try await loader.preload(placement.adUnitID)
            guard canLoad(placement), !Task.isCancelled else { return false }
            return true
        } catch { return false }
    }

    func invalidateCache() { loader.invalidate() }

    func present(placement: RewardedAdPlacement, requestID: UUID,
                 receive: @escaping @MainActor (RewardedAdEvent) -> Void) {
        guard activeRequest == nil, rewardedAd == nil else { receive(.failed); return }
        guard canLoad(placement), presenter() != nil else { receive(.unavailable); return }
        activeRequest = requestID
        self.receive = receive
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.loader.preload(placement.adUnitID)
                guard self.activeRequest == requestID, !Task.isCancelled else { return }
                guard self.canLoad(placement), let viewController = self.presenter(),
                      viewController.viewIfLoaded?.window != nil,
                      !viewController.isBeingDismissed, !viewController.isBeingPresented,
                      let ad = self.loader.take(placement.adUnitID) else { self.finish(.unavailable); return }
                guard self.presentationGate.acquire(requestID) else { self.finish(.unavailable); return }
                self.presentationLease = requestID
                self.rewardedAd = ad
                ad.present(from: viewController) { [weak self] event in
                    guard let self, self.presentationLease == requestID else { return }
                    switch event {
                    case .closed, .failed, .unavailable: self.finish(event)
                    case .presented, .rewardEarned:
                        guard self.activeRequest == requestID else { return }
                        guard self.privacyAllowsAds() else { self.cancel(requestID: requestID); return }
                        self.receive?(event)
                    }
                }
            } catch {
                guard self.activeRequest == requestID, !Task.isCancelled else { return }
                self.finish(error is RewardedAdLoadError ? .unavailable : .failed)
            }
        }
    }

    func cancel(requestID: UUID) {
        guard activeRequest == requestID else { return }
        activeRequest = nil
        receive = nil
        loadTask?.cancel()
        loadTask = nil
        // Retain a visible ad and its lease until SDK dismissal, as in showingLoader.
    }

    private func finish(_ event: RewardedAdEvent) {
        let callback = receive
        if let presentationLease { presentationGate.release(presentationLease) }
        presentationLease = nil
        activeRequest = nil
        receive = nil
        rewardedAd = nil
        loadTask?.cancel()
        loadTask = nil
        callback?(event)
    }

    private static func isAppID(_ value: String) -> Bool {
        value.range(of: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#, options: .regularExpression) != nil
    }

    /// Refuse ambiguous multi-window presentation. A scene-specific presenter can be
    /// injected by the eventual reward entry point instead of choosing an arbitrary scene.
    static func activePresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard scenes.count == 1,
              let window = scenes[0].windows.first(where: \.isKeyWindow),
              let root = window.rootViewController else { return nil }
        var current = root
        while true {
            if let presented = current.presentedViewController, !presented.isBeingDismissed {
                current = presented
            } else if let navigation = current as? UINavigationController, let visible = navigation.visibleViewController {
                current = visible
            } else if let tabs = current as? UITabBarController, let selected = tabs.selectedViewController {
                current = selected
            } else {
                return current
            }
        }
    }
}
