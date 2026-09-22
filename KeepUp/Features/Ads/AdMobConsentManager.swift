import Observation
import UIKit
import UserMessagingPlatform

@MainActor protocol AdMobConsentClient: AnyObject {
    var canRequestAds: Bool { get }
    var privacyOptionsRequired: Bool { get }
    func requestUpdate() async throws
    func loadAndPresentIfRequired(from presenter: UIViewController) async throws
    func presentPrivacyOptions(from presenter: UIViewController) async throws
}

@MainActor private final class UMPAdMobConsentClient: AdMobConsentClient {
    private let parameters: RequestParameters

    init(parameters: RequestParameters?) {
        self.parameters = parameters ?? RequestParameters()
    }

    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }
    var privacyOptionsRequired: Bool { ConsentInformation.shared.privacyOptionsRequirementStatus == .required }

    func requestUpdate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func loadAndPresentIfRequired(from presenter: UIViewController) async throws {
        try await ConsentForm.loadAndPresentIfRequired(from: presenter)
    }

    func presentPrivacyOptions(from presenter: UIViewController) async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: presenter)
    }
}

/// Construction is inert. The future ad entry point must explicitly prepare consent
/// before enabling ads, and expose privacy options when required by UMP.
@MainActor @Observable final class AdMobConsentManager {
    enum OperationError: Error { case busy, notPrepared, privacyOptionsNotRequired, updateTimedOut }

    private(set) var canRequestAds = false
    private(set) var privacyOptionsRequired = false
    private(set) var isPrepared = false
    private(set) var isBusy = false
    @ObservationIgnored private let client: any AdMobConsentClient
    @ObservationIgnored private let updateTimeout: Duration

    convenience init(parameters: RequestParameters? = nil) {
        self.init(client: UMPAdMobConsentClient(parameters: parameters))
    }

    init(client: any AdMobConsentClient, updateTimeout: Duration = .seconds(8)) {
        self.client = client
        self.updateTimeout = updateTimeout
    }

    /// Call explicitly when enabling the future ads flow, once per app launch.
    /// UMP may display a form here; merely constructing the manager never does so.
    /// Unlike UMP's optional cached-consent fallback, this app fails closed on errors.
    func prepare(from presenter: UIViewController) async throws {
        guard !isBusy else { throw OperationError.busy }
        isBusy = true
        isPrepared = false
        canRequestAds = false
        defer { isBusy = false }
        do {
            try await requestUpdateWithTimeout()
            try Task.checkCancellation()
            privacyOptionsRequired = client.privacyOptionsRequired
            try await client.loadAndPresentIfRequired(from: presenter)
            try Task.checkCancellation()
            isPrepared = true
            canRequestAds = client.canRequestAds
            privacyOptionsRequired = client.privacyOptionsRequired
        } catch {
            canRequestAds = false
            throw error
        }
    }

    /// Do not use a structured task-group race: an SDK callback may never resume its
    /// task, which would make the group wait forever even after cancellation.
    private func requestUpdateWithTimeout() async throws {
        let wait = ConsentUpdateWait()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                wait.continuation = continuation
                guard !Task.isCancelled else { wait.finish(.failure(CancellationError())); return }
                wait.updateTask = Task { [weak wait, client] in
                    do {
                        try await client.requestUpdate()
                        try Task.checkCancellation()
                        wait?.finish(.success(()))
                    } catch { wait?.finish(.failure(error)) }
                }
                wait.timeoutTask = Task { [weak wait, updateTimeout] in
                    do { try await Task.sleep(for: updateTimeout) } catch { return }
                    wait?.finish(.failure(OperationError.updateTimedOut))
                }
            }
        } onCancel: {
            Task { @MainActor in wait.finish(.failure(CancellationError())) }
        }
    }

    /// Wire a visible settings action to this when privacyOptionsRequired is true.
    /// Ads pause while the user changes their choice and eligibility is refreshed after.
    func presentPrivacyOptions(from presenter: UIViewController) async throws {
        guard !isBusy else { throw OperationError.busy }
        guard isPrepared else { throw OperationError.notPrepared }
        guard privacyOptionsRequired else { throw OperationError.privacyOptionsNotRequired }
        isBusy = true
        canRequestAds = false
        defer { isBusy = false }
        do {
            try await client.presentPrivacyOptions(from: presenter)
            try Task.checkCancellation()
            canRequestAds = client.canRequestAds
            privacyOptionsRequired = client.privacyOptionsRequired
        } catch {
            isPrepared = false
            canRequestAds = false
            throw error
        }
    }
}

/// This gate only releases the info-update waiter. It never completes, dismisses,
/// or imposes a deadline on a visible UMP consent form.
@MainActor private final class ConsentUpdateWait {
    var continuation: CheckedContinuation<Void, Error>?
    var updateTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?

    func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        updateTask?.cancel()
        timeoutTask?.cancel()
        updateTask = nil
        timeoutTask = nil
        continuation.resume(with: result)
    }
}
