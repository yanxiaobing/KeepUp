import Foundation
import GoogleMobileAds

/// One presentation lease for all formats. A cancelled visible ad retains its lease
/// until the SDK confirms dismissal/failure; a timer must never unlock visible content.
@MainActor final class FullScreenAdGate {
    static let shared = FullScreenAdGate()
    private(set) var owner: UUID?
    func acquire(_ token: UUID) -> Bool {
        guard owner == nil else { return false }
        owner = token
        return true
    }
    func release(_ token: UUID) {
        if owner == token { owner = nil }
    }
}

@MainActor enum AdMobRuntime {
    private static var initialization: Task<Void, Never>?

    static var isConfigured: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String else { return false }
        return value.range(of: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#, options: .regularExpression) != nil
    }

    static func initializeIfNeeded() async {
        if let initialization { await initialization.value; return }
        let task = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in continuation.resume() }
            }
        }
        initialization = task
        await task.value
    }
}

/// Resolve at the SDK boundary so remote configuration cannot send live requests in Debug.
enum AdMobAdUnit {
    enum Format { case appOpen, interstitial, rewarded }
    static func resolve(_ configuredID: String, format: Format) -> String {
        #if DEBUG
        switch format {
        case .appOpen: "ca-app-pub-3940256099942544/5575463023"
        case .interstitial: "ca-app-pub-3940256099942544/4411468910"
        case .rewarded: "ca-app-pub-3940256099942544/1712485313"
        }
        #else
        configuredID
        #endif
    }
}
