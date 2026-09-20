import Foundation
import Observation

@MainActor @Observable final class RunningController {
    private(set) var session: RunningSession?
    private(set) var lastFinishedSession: RunningSession?
    private(set) var authorization: RunningAuthorization
    private(set) var isBusy = false
    private(set) var errorKey: String?
    private(set) var locationReady = false
    private(set) var isRecovered = false
    private let source: any RunningLocationSource
    private let now: @MainActor () -> Date
    private var wantsLocation = false
    private var lastLocationAt: Date?
    private var timer: Task<Void, Never>?
    private var writeTail: Task<Bool, Never>?
    private var checkpointSequence = 0
    private var completedCheckpointSequence = 0
    private var checkpointAction: (@MainActor (RunningSession) async -> Bool)?
    private var finishAction: (@MainActor (RunningSession) async -> Bool)?
    private var discardAction: (@MainActor (String) async -> Bool)?

    init(source: any RunningLocationSource = RunningLocationSources.make(), now: @escaping @MainActor () -> Date = { .now }) {
        self.source = source
        self.now = now
        authorization = source.authorization
        source.onEvent = { [weak self] event in self?.receive(event) }
    }

    func configure(checkpoint: @escaping @MainActor (RunningSession) async -> Bool,
                   finish: @escaping @MainActor (RunningSession) async -> Bool,
                   discard: @escaping @MainActor (String) async -> Bool) {
        checkpointAction = checkpoint
        finishAction = finish
        discardAction = discard
    }

    func restore(_ saved: RunningSession) {
        guard session == nil, saved.phase != .finished else { return }
        var recovered = saved
        recovered.recover()
        session = recovered
        isRecovered = true
        source.stop()
        Task { [weak self] in await self?.tick() }
    }

    func prepare() {
        wantsLocation = true
        authorization = source.authorization
        if authorization == .authorized { source.start(background: session?.phase == .running); startTimer() }
    }
    func stopPreparing() {
        if session?.phase != .running {
            wantsLocation = false
            source.stop()
            timer?.cancel()
            timer = nil
            locationReady = false
            lastLocationAt = nil
        }
    }
    func requestPermission() {
        wantsLocation = true
        authorization = source.authorization
        if authorization == .notDetermined { source.requestPermission() }
        else { prepare() }
    }

    func start() async {
        guard !isBusy, session == nil else { return }
        authorization = source.authorization
        guard authorization == .authorized else { errorKey = "running.permissionRequired"; return }
        isBusy = true
        defer { isBusy = false }
        errorKey = nil
        lastFinishedSession = nil
        isRecovered = false
        var startedAt = now()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing"), let index = args.firstIndex(of: "-ui-testing-running"),
           args.indices.contains(index + 1), args[index + 1] == "route" {
            startedAt = startedAt.addingTimeInterval(-12)
        }
        #endif
        session = RunningSession(startedAt: startedAt)
        wantsLocation = true
        source.start(background: true)
        startTimer()
        await persistCheckpoint()
    }

    func pause() async {
        guard !isBusy, session?.phase == .running else { return }
        isBusy = true
        defer { isBusy = false }
        stopAndPause()
        await persistCheckpoint()
    }

    func resume() async {
        guard !isBusy, session?.phase == .paused else { return }
        authorization = source.authorization
        guard authorization == .authorized else { errorKey = "running.permissionRequired"; return }
        isBusy = true
        defer { isBusy = false }
        errorKey = nil
        isRecovered = false
        session?.resume(at: now())
        wantsLocation = true
        source.start(background: true)
        startTimer()
        await persistCheckpoint()
    }

    func finish() async {
        guard !isBusy, var final = session else { return }
        guard final.distanceMeters >= 100 else { errorKey = "running.tooShort"; return }
        isBusy = true
        defer { isBusy = false }
        wantsLocation = false
        source.stop()
        timer?.cancel()
        timer = nil
        locationReady = false
        final.finish(at: now())
        session = final
        let action = finishAction
        let succeeded = await enqueue { await action?(final) ?? false }.value
        if succeeded {
            lastFinishedSession = final
            session = nil
            isRecovered = false
            errorKey = nil
        } else { errorKey = "running.saveFailed" }
    }

    func discard() async {
        guard !isBusy, let id = session?.id else { return }
        isBusy = true
        defer { isBusy = false }
        stopAndPause()
        let action = discardAction
        let succeeded = await enqueue { await action?(id) ?? false }.value
        if succeeded { session = nil; isRecovered = false; errorKey = nil }
        else { errorKey = "running.saveFailed" }
    }

    /// Called periodically and on lifecycle transitions; unsuccessful checkpoints remain retryable.
    func tick() async {
        locationReady = lastLocationAt.map { now().timeIntervalSince($0) <= 15 } ?? false
        guard !isBusy, session != nil, session?.phase != .finished else { return }
        await persistCheckpoint()
    }

    private func stopAndPause() {
        session?.pause(at: now())
        wantsLocation = false
        source.stop()
        timer?.cancel()
        timer = nil
        locationReady = false
        lastLocationAt = nil
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self else { return }
                if self.session?.phase == .running { await self.tick() }
                else { self.locationReady = self.lastLocationAt.map { self.now().timeIntervalSince($0) <= 15 } ?? false }
            }
        }
    }

    private func receive(_ event: RunningLocationEvent) {
        switch event {
        case .authorization(let access):
            authorization = access
            if access == .authorized, wantsLocation { source.start(background: session?.phase == .running); startTimer() }
            if access != .authorized {
                locationReady = false
                if session?.phase == .running {
                    stopAndPause()
                    errorKey = "running.permissionRequired"
                    Task { [weak self] in await self?.persistCheckpoint() }
                }
            }
        case .points(let points):
            guard wantsLocation, authorization == .authorized else { return }
            let date = now()
            for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
                guard point.isUsable(at: date) else { continue }
                if lastLocationAt == nil || point.timestamp > lastLocationAt! { lastLocationAt = point.timestamp }
                locationReady = true
                if session?.append(point, now: date) == true, errorKey == "running.locationFailed" { errorKey = nil }
            }
        case .failed:
            locationReady = false
            errorKey = "running.locationFailed"
        }
    }

    private func persistCheckpoint() async {
        guard var snapshot = session, snapshot.phase != .finished else { return }
        snapshot.updatedAt = now()
        snapshot.revision += 1
        session = snapshot
        checkpointSequence += 1
        let sequence = checkpointSequence
        let action = checkpointAction
        let succeeded = await enqueue { await action?(snapshot) ?? false }.value
        guard session?.id == snapshot.id, session?.phase != .finished,
              sequence >= completedCheckpointSequence else { return }
        completedCheckpointSequence = sequence
        if succeeded {
            if errorKey == "running.saveFailed" { errorKey = nil }
        } else { errorKey = "running.saveFailed" }
    }

    /// Preserve write order across MainActor reentrancy: terminal writes always follow older checkpoints.
    private func enqueue(_ action: @escaping @MainActor () async -> Bool) -> Task<Bool, Never> {
        let previous = writeTail
        let next = Task { @MainActor in
            if let previous { _ = await previous.value }
            return await action()
        }
        writeTail = next
        return next
    }
}
