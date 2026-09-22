import Testing
import UIKit
@testable import KeepUp

@MainActor struct AdMobConsentManagerTests {
    @Test func constructionDoesNotRequestConsentOrTrustCachedPermission() {
        let client = TestConsentClient()
        let manager = AdMobConsentManager(client: client)
        #expect(!manager.canRequestAds)
        #expect(!manager.isPrepared)
        #expect(client.calls.isEmpty)
    }

    @Test func successfulPreparationUpdatesConsentBeforeLoadingForm() async throws {
        let client = TestConsentClient()
        let manager = AdMobConsentManager(client: client)
        try await manager.prepare(from: UIViewController())
        #expect(client.calls == ["update", "form"])
        #expect(manager.isPrepared)
        #expect(manager.canRequestAds)
        #expect(manager.privacyOptionsRequired)
        #expect(!manager.isBusy)
    }

    @Test func updateOrFormFailureKeepsAdsDisabledDespiteCachedConsent() async {
        for failure in ["update", "form"] {
            let client = TestConsentClient()
            client.failure = failure
            let manager = AdMobConsentManager(client: client)
            do { try await manager.prepare(from: UIViewController()); Issue.record("Expected failure") }
            catch {}
            #expect(!manager.canRequestAds)
            #expect(!manager.isPrepared)
            #expect(!manager.isBusy)
        }
    }

    @Test func successfulFormWithoutPermissionDoesNotEnableAds() async throws {
        let client = TestConsentClient()
        client.canRequestAds = false
        let manager = AdMobConsentManager(client: client)
        try await manager.prepare(from: UIViewController())
        #expect(manager.isPrepared)
        #expect(!manager.canRequestAds)
    }

    @Test func privacyOptionsRefreshRevokedPermission() async throws {
        let client = TestConsentClient()
        let manager = AdMobConsentManager(client: client)
        try await manager.prepare(from: UIViewController())
        client.canRequestAds = false
        try await manager.presentPrivacyOptions(from: UIViewController())
        #expect(client.calls == ["update", "form", "options"])
        #expect(!manager.canRequestAds)
    }

    @Test func privacyOptionsCannotRunBeforePreparation() async {
        let client = TestConsentClient()
        let manager = AdMobConsentManager(client: client)
        do { try await manager.presentPrivacyOptions(from: UIViewController()); Issue.record("Expected failure") }
        catch {}
        #expect(client.calls.isEmpty)
        #expect(!manager.canRequestAds)
    }

    @Test func stalledInfoUpdateTimesOutAndLateCallbackCannotPresentForm() async {
        let client = TestConsentClient()
        client.suspendUpdate = true
        let manager = AdMobConsentManager(client: client, updateTimeout: .milliseconds(5))
        do { try await manager.prepare(from: UIViewController()); Issue.record("Expected timeout") }
        catch AdMobConsentManager.OperationError.updateTimedOut {}
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(!manager.isBusy && !manager.canRequestAds && !manager.isPrepared)
        client.updateContinuation?.resume()
        client.updateContinuation = nil
        await Task.yield()
        #expect(client.calls == ["update"])
        #expect(!manager.canRequestAds)
    }

    @Test func cancellationReleasesStalledInfoUpdateAndIgnoresLateCallback() async {
        let client = TestConsentClient()
        client.suspendUpdate = true
        let manager = AdMobConsentManager(client: client, updateTimeout: .seconds(60))
        let task = Task { try await manager.prepare(from: UIViewController()) }
        while client.updateContinuation == nil { await Task.yield() }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(!manager.isBusy && !manager.canRequestAds && !manager.isPrepared)
        client.updateContinuation?.resume()
        client.updateContinuation = nil
        await Task.yield()
        #expect(client.calls == ["update"])
        #expect(!manager.canRequestAds)
    }

    @Test func infoUpdateDeadlineNeverTimesOutAnActiveConsentForm() async throws {
        let client = TestConsentClient()
        client.suspendForm = true
        let manager = AdMobConsentManager(client: client, updateTimeout: .milliseconds(10))
        let task = Task { try await manager.prepare(from: UIViewController()) }
        while client.formContinuation == nil { await Task.yield() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(manager.isBusy && !manager.canRequestAds && !manager.isPrepared)
        client.formContinuation?.resume()
        client.formContinuation = nil
        try await task.value
        #expect(manager.isPrepared && manager.canRequestAds)
    }

    @Test func privacyOptionsFailureDisablesAdsAndRequiresPreparationAgain() async throws {
        let client = TestConsentClient()
        let manager = AdMobConsentManager(client: client)
        try await manager.prepare(from: UIViewController())
        client.failure = "options"
        do { try await manager.presentPrivacyOptions(from: UIViewController()); Issue.record("Expected failure") }
        catch {}
        #expect(!manager.canRequestAds)
        #expect(!manager.isPrepared)
        #expect(!manager.isBusy)
    }
}

@MainActor private final class TestConsentClient: AdMobConsentClient {
    enum Failure: Error { case failed }
    var canRequestAds = true
    var privacyOptionsRequired = true
    var calls: [String] = []
    var failure: String?
    var suspendUpdate = false
    var suspendForm = false
    var updateContinuation: CheckedContinuation<Void, Error>?
    var formContinuation: CheckedContinuation<Void, Error>?
    func requestUpdate() async throws {
        try record("update")
        if suspendUpdate { try await withCheckedThrowingContinuation { updateContinuation = $0 } }
    }
    func loadAndPresentIfRequired(from presenter: UIViewController) async throws {
        try record("form")
        if suspendForm { try await withCheckedThrowingContinuation { formContinuation = $0 } }
    }
    func presentPrivacyOptions(from presenter: UIViewController) async throws { try record("options") }
    private func record(_ name: String) throws {
        calls.append(name)
        if failure == name { throw Failure.failed }
    }
}
