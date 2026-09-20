import Foundation
import Observation

@MainActor @Observable final class RunningController {
    private(set) var session: RunningSession?
    private(set) var lastFinishedSession: RunningSession?
    private(set) var authorization: RunningAuthorization
    private(set) var selectedKind = RunningKind.outdoor
    private(set) var motionReady = false
    var kind: RunningKind { session?.kind ?? selectedKind }
    private(set) var isBusy = false
    private(set) var errorKey: String?
    private(set) var locationReady = false
    private(set) var isRecovered = false
    private(set) var countdownRemaining: Int?
    private(set) var isAutoPaused = false
    var onEvent: (@MainActor (RunningEvent) -> Void)?
    private let settings: @MainActor () -> RunningSettings
    private let sleep: @MainActor (Duration) async throws -> Void
    private var countdownTask: Task<Bool, Never>?
    private var startGeneration = 0
    private var lastMovementAt: Date?
    private var autoPausedAt: Date?
    private var autoPausePoint: RunningPoint?
    private let source: any RunningLocationSource
    private let motionSource: any RunningMotionSource
    private var motionSubscriptionStart: Date?
    private var lastMotionAt: Date?
    private var lastMotionDistance: Double = 0
    private var lastMotionSteps = 0
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

    init(source: any RunningLocationSource = RunningLocationSources.make(), motionSource: any RunningMotionSource = RunningMotionSources.make(), now: @escaping @MainActor () -> Date = { .now },
         settings: @escaping @MainActor () -> RunningSettings = { Defaults[.runningSettings] },
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.source = source
        self.motionSource = motionSource
        self.now = now
        self.settings = settings
        self.sleep = sleep
        authorization = source.authorization
        source.onEvent = { [weak self] event in self?.receive(event) }
        motionSource.onEvent = { [weak self] event in self?.receiveMotion(event) }
    }

    func cancelCountdown() {
        guard countdownRemaining != nil else { return }
        startGeneration += 1
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
        isBusy = false
        onEvent?(.countdownCancelled)
    }

    func settingsDidChange() {
        if isAutoPaused, !settings().autoPause {
            stopAndPause()
            if let session { onEvent?(.paused(session, automatic: false)) }
            Task { [weak self] in await self?.persistCheckpoint() }
        }
    }

    func selectKind(_ value: RunningKind) {
        guard session == nil, !isBusy, value != selectedKind else { return }
        stopPreparing()
        selectedKind = value
        authorization = currentAuthorization
        motionReady = value == .indoor && authorization == .authorized
        errorKey = nil
    }

    private var currentAuthorization: RunningAuthorization { kind.usesGPS ? source.authorization : motionSource.authorization }

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
        selectedKind = recovered.kind
        authorization = currentAuthorization
        motionReady = recovered.kind == .indoor && authorization == .authorized
        isRecovered = true
        isAutoPaused = false
        lastMovementAt = nil
        onEvent?(.restored(recovered))
        source.stop()
        motionSource.stop()
        Task { [weak self] in await self?.tick() }
    }

    func prepare() {
        let access = currentAuthorization
        if session != nil, (session?.phase == .running || isAutoPaused), access != .authorized {
            if kind.usesGPS { receive(.authorization(access)) } else { receiveMotion(.authorization(access)) }
            return
        }
        authorization = access
        if session?.phase == .paused, !isAutoPaused {
            motionReady = kind == .indoor && access == .authorized
            return
        }
        wantsLocation = kind.usesGPS
        if kind.usesGPS {
            source.configure(kind: kind)
            if authorization == .authorized { source.start(background: session?.phase == .running || isAutoPaused); startTimer() }
        } else {
            motionReady = authorization == .authorized
            if session?.phase == .running || isAutoPaused, let start = motionSubscriptionStart, motionReady { motionSource.start(from: start) }
        }
    }
    func stopPreparing() {
        cancelCountdown()
        if session?.phase != .running, !isAutoPaused {
            wantsLocation = false
            source.stop()
            motionSource.stop()
            timer?.cancel()
            timer = nil
            locationReady = false
            lastLocationAt = nil
        }
    }
    func requestPermission() {
        wantsLocation = kind.usesGPS
        authorization = currentAuthorization
        if authorization == .notDetermined {
            if kind.usesGPS { source.requestPermission() } else { motionSource.requestPermission() }
        } else { prepare() }
    }

    func start() async {
        guard !isBusy, session == nil else { return }
        authorization = currentAuthorization
        guard authorization == .authorized else { errorKey = kind.usesGPS ? "running.permissionRequired" : "running.motionPermissionRequired"; return }
        isBusy = true
        startGeneration += 1
        let generation = startGeneration
        defer { if startGeneration == generation { isBusy = false } }
        errorKey = nil
        if settings().countdown {
            countdownRemaining = 3
            let task = Task { @MainActor [weak self] () -> Bool in
                guard let self else { return false }
                for count in stride(from: 3, through: 1, by: -1) {
                    guard self.startGeneration == generation, !Task.isCancelled else { return false }
                    self.countdownRemaining = count
                    self.onEvent?(.countdown(count))
                    do { try await self.sleep(.seconds(1)) } catch { return false }
                }
                return !Task.isCancelled
            }
            countdownTask = task
            let completed = await task.value
            guard startGeneration == generation else { return }
            countdownTask = nil
            if !completed || Task.isCancelled { cancelCountdown(); return }
            countdownRemaining = nil
        }
        guard startGeneration == generation, !Task.isCancelled, session == nil else { return }
        authorization = currentAuthorization
        guard authorization == .authorized else { errorKey = kind.usesGPS ? "running.permissionRequired" : "running.motionPermissionRequired"; return }
        lastFinishedSession = nil
        isRecovered = false
        var startedAt = now()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing"), let index = args.firstIndex(of: "-ui-testing-running"),
           args.indices.contains(index + 1), (args[index + 1] == "route" && kind.usesGPS || args[index + 1] == "motion" && kind == .indoor) {
            startedAt = startedAt.addingTimeInterval(kind == .indoor ? -60 : -12)
        }
        #endif
        session = RunningSession(startedAt: startedAt, kind: selectedKind)
        isAutoPaused = false
        lastMovementAt = now()
        if let session { onEvent?(.started(session)) }
        activateSources()
        startTimer()
        await persistCheckpoint()
    }

    func pause() async {
        guard !isBusy, session?.phase == .running || isAutoPaused else { return }
        isBusy = true
        defer { isBusy = false }
        stopAndPause()
        if let session { onEvent?(.paused(session, automatic: false)) }
        await persistCheckpoint()
    }

    func resume() async {
        guard !isBusy, session?.phase == .paused else { return }
        authorization = currentAuthorization
        guard authorization == .authorized else { errorKey = kind.usesGPS ? "running.permissionRequired" : "running.motionPermissionRequired"; return }
        isBusy = true
        defer { isBusy = false }
        errorKey = nil
        isRecovered = false
        session?.resume(at: now())
        isAutoPaused = false
        lastMovementAt = now()
        autoPausedAt = nil
        autoPausePoint = nil
        if let session { onEvent?(.resumed(session, automatic: false)) }
        activateSources()
        startTimer()
        await persistCheckpoint()
    }

    func finish() async {
        guard !isBusy, var final = session else { return }
        guard final.distanceMeters >= final.kind.minimumDistanceMeters else { errorKey = final.kind == .cycling ? "running.cyclingTooShort" : "running.tooShort"; return }
        isBusy = true
        defer { isBusy = false }
        wantsLocation = false
        source.stop()
        motionSource.stop()
        motionSubscriptionStart = nil
        timer?.cancel()
        timer = nil
        locationReady = false
        isAutoPaused = false
        final.finish(at: now())
        session = final
        let action = finishAction
        let succeeded = await enqueue { await action?(final) ?? false }.value
        if succeeded {
            lastFinishedSession = final
            onEvent?(.finished(final))
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
        if succeeded { session = nil; isRecovered = false; errorKey = nil; onEvent?(.discarded) }
        else { errorKey = "running.saveFailed" }
    }

    /// Called periodically and on lifecycle transitions; unsuccessful checkpoints remain retryable.
    func tick() async {
        if kind == .indoor {
            let access = motionSource.authorization
            if access != authorization { receiveMotion(.authorization(access)) }
        }
        locationReady = lastLocationAt.map { now().timeIntervalSince($0) <= 15 } ?? false
        guard !isBusy, session != nil, session?.phase != .finished else { return }
        if settings().autoPause, session?.phase == .running, let lastMovementAt,
           now().timeIntervalSince(lastMovementAt) >= 15 {
            session?.pause(at: now())
            isAutoPaused = true
            autoPausedAt = now()
            autoPausePoint = nil
            if let session { onEvent?(.paused(session, automatic: true)) }
        }
        await persistCheckpoint()
    }

    private func stopAndPause() {
        session?.pause(at: now())
        isAutoPaused = false
        autoPausedAt = nil
        autoPausePoint = nil
        wantsLocation = false
        source.stop()
        motionSource.stop()
        motionSubscriptionStart = nil
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
                if self.session?.phase == .running || self.isAutoPaused { await self.tick() }
                else { self.locationReady = self.lastLocationAt.map { self.now().timeIntervalSince($0) <= 15 } ?? false }
            }
        }
    }

    private func receive(_ event: RunningLocationEvent) {
        guard kind.usesGPS else { return }
        switch event {
        case .authorization(let access):
            authorization = access
            if access == .authorized, wantsLocation { source.start(background: session?.phase == .running || isAutoPaused); startTimer() }
            if access != .authorized {
                locationReady = false
                if session?.phase == .running || isAutoPaused {
                    stopAndPause()
                    if let session { onEvent?(.paused(session, automatic: false)) }
                    errorKey = "running.permissionRequired"
                    Task { [weak self] in await self?.persistCheckpoint() }
                }
            }
        case .points(let points):
            guard wantsLocation, authorization == .authorized else { return }
            let date = now()
            var distanceChanged = false
            for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
                guard point.isUsable(at: date) else { continue }
                if lastLocationAt == nil || point.timestamp > lastLocationAt! { lastLocationAt = point.timestamp }
                locationReady = true
                if isAutoPaused {
                    considerAutomaticGPSResume(point, now: date)
                    continue
                }
                let before = session?.distanceMeters ?? 0
                if session?.append(point, now: date) == true {
                    if errorKey == "running.locationFailed" { errorKey = nil }
                    if let session, session.distanceMeters > before {
                        lastMovementAt = min(date, point.timestamp)
                        distanceChanged = true
                    }
                }
            }
            if distanceChanged, let session { onEvent?(.updated(session)) }
        case .failed:
            locationReady = false
            errorKey = "running.locationFailed"
        }
    }

    private func activateSources() {
        wantsLocation = kind.usesGPS
        if kind.usesGPS {
            motionSource.stop()
            source.configure(kind: kind)
            source.start(background: true)
        } else if let start = session?.activeSince {
            source.stop()
            motionSubscriptionStart = start
            lastMotionAt = start
            lastMotionDistance = 0
            lastMotionSteps = 0
            motionReady = true
            motionSource.start(from: start)
        }
    }

    private func receiveMotion(_ event: RunningMotionEvent) {
        guard kind == .indoor else { return }
        switch event {
        case .authorization(let access):
            authorization = access
            motionReady = access == .authorized
            if access != .authorized, session?.phase == .running || isAutoPaused {
                stopAndPause()
                if let session { onEvent?(.paused(session, automatic: false)) }
                errorKey = "running.motionPermissionRequired"
                Task { [weak self] in await self?.persistCheckpoint() }
            }
        case .failed:
            motionReady = false
            errorKey = "running.motionFailed"
        case .reading(let reading):
            guard session?.phase == .running || isAutoPaused, authorization == .authorized,
                  let start = motionSubscriptionStart, reading.startedAt == start,
                  let previousTime = lastMotionAt, reading.measuredAt > previousTime,
                  reading.distanceMeters.isFinite, reading.distanceMeters >= lastMotionDistance,
                  reading.steps >= lastMotionSteps else { return }
            let delta = reading.distanceMeters - lastMotionDistance
            let steps = reading.steps - lastMotionSteps
            if isAutoPaused {
                guard reading.measuredAt <= now().addingTimeInterval(2),
                      delta <= 15 * reading.measuredAt.timeIntervalSince(previousTime) + 10 else { return }
                lastMotionAt = reading.measuredAt
                lastMotionDistance = reading.distanceMeters
                lastMotionSteps = reading.steps
                // Advance the cumulative baseline for delayed pre-pause delivery, but never use it as new movement.
                if let autoPausedAt, reading.measuredAt > autoPausedAt,
                   now().timeIntervalSince(reading.measuredAt) <= 15, delta > 0 || steps > 0 { automaticallyResume() }
                return
            }
            guard session?.appendIndoor(distance: delta, steps: steps, from: previousTime, to: reading.measuredAt, now: now()) == true else { return }
            lastMotionAt = reading.measuredAt
            lastMotionDistance = reading.distanceMeters
            lastMotionSteps = reading.steps
            motionReady = true
            if errorKey == "running.motionFailed" { errorKey = nil }
            if delta > 0 || steps > 0 { lastMovementAt = min(now(), reading.measuredAt) }
            if delta > 0, let session { onEvent?(.updated(session)) }
        }
    }

    private func considerAutomaticGPSResume(_ point: RunningPoint, now date: Date) {
        guard let pausedAt = autoPausedAt, point.timestamp > pausedAt else { return }
        guard let previous = autoPausePoint else { autoPausePoint = point; return }
        let interval = point.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return }
        if interval > 30 { autoPausePoint = point; return }
        let distance = previous.distance(to: point)
        guard distance <= kind.maximumSpeedMetersPerSecond * interval + max(10, previous.horizontalAccuracy + point.horizontalAccuracy) else { return }
        let movementThreshold = point.speed < 0 ? max(3, min(20, previous.horizontalAccuracy + point.horizontalAccuracy)) : 3
        if distance >= movementThreshold, point.speed < 0 || point.speed > 0.5 {
            automaticallyResume()
            // Resume opens a fresh segment, so this anchor never adds the paused displacement.
            _ = session?.append(point, now: date)
        } else if distance >= 3, point.speed >= 0 { autoPausePoint = point }
    }

    private func automaticallyResume() {
        guard isAutoPaused, !isBusy, settings().autoPause, authorization == .authorized else { return }
        session?.resume(at: now())
        isAutoPaused = false
        autoPausedAt = nil
        autoPausePoint = nil
        lastMovementAt = now()
        if let session { onEvent?(.resumed(session, automatic: true)) }
        if kind == .indoor { activateSources() }
        startTimer()
        Task { [weak self] in await self?.persistCheckpoint() }
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
