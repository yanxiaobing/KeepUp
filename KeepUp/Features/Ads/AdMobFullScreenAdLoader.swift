import GoogleMobileAds
import UIKit

@MainActor final class AdMobFullScreenAdLoader: FullScreenAdLoading {
    func load(format: AdMobFullScreenFormat, adUnitID: String) async throws -> any LoadedFullScreenAd {
        guard AdMobRuntime.isConfigured else { throw FullScreenAdLoadError.unavailable }
        await AdMobRuntime.initializeIfNeeded()
        try Task.checkCancellation()
        do {
            switch format {
            case .appOpen:
                return AdMobLoadedFullScreenAd(appOpen: try await AppOpenAd.load(with: adUnitID, request: Request()))
            case .interstitial:
                return AdMobLoadedFullScreenAd(interstitial: try await InterstitialAd.load(with: adUnitID, request: Request()))
            }
        } catch {
            let requestError = error as NSError
            if requestError.domain == GADErrorDomain && requestError.code == RequestError.Code.noFill.rawValue {
                throw FullScreenAdLoadError.unavailable
            }
            throw error
        }
    }
}

@MainActor private final class AdMobLoadedFullScreenAd: NSObject, LoadedFullScreenAd, FullScreenContentDelegate {
    private let appOpen: AppOpenAd?
    private let interstitial: InterstitialAd?
    private var callback: (@MainActor (FullScreenAdEvent) -> Void)?
    private var didPresent = false

    init(appOpen: AppOpenAd) {
        self.appOpen = appOpen
        self.interstitial = nil
    }

    init(interstitial: InterstitialAd) {
        self.appOpen = nil
        self.interstitial = interstitial
    }

    func present(from presenter: UIViewController, receive: @escaping @MainActor (FullScreenAdEvent) -> Void) {
        guard !didPresent else { receive(.failed); return }
        didPresent = true
        callback = receive
        if let appOpen {
            appOpen.fullScreenContentDelegate = self
            appOpen.present(from: presenter)
        } else if let interstitial {
            interstitial.fullScreenContentDelegate = self
            interstitial.present(from: presenter)
        } else { finish(.failed) }
    }

    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) { callback?(.presented) }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) { finish(.closed) }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { finish(.failed) }

    private func finish(_ event: FullScreenAdEvent) {
        let receive = callback
        callback = nil
        appOpen?.fullScreenContentDelegate = nil
        interstitial?.fullScreenContentDelegate = nil
        receive?(event)
    }
}
