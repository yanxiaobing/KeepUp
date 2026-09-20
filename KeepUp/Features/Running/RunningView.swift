import SwiftUI

struct RunningView: View {
    var kind: RunningKind = .outdoor
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingFinish = false
    @State private var confirmingDiscard = false
    @State private var result: RunningSession?
    @State private var showingSettings = false
    @State private var settingsKindAtOpen: RunningKind?
    @State private var visible = false
    @State private var automaticStartAttempted = false
    @State private var controlsLocked = false
    @State private var screenAwake = RunningScreenAwake()
    @Default(.runningSettings) private var settings
    private var controller: RunningController { model.running }
    private var currentKind: RunningKind { controller.session?.kind ?? controller.selectedKind }
    private var readyToStart: Bool {
        controller.authorization == .authorized && (currentKind.usesGPS ? controller.locationReady : controller.motionReady)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result { RunningSessionSummary(session: result) }
                else if let session = controller.session { activeSession(session) }
                else { preparation }
            }
            .background(.white)
            .accessibilityHidden(controller.countdownRemaining != nil)
            .navigationTitle(LocalizedStringKey(result == nil ? currentKind.titleKey : "running.result"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { controller.cancelCountdown(); dismiss() }.accessibilityIdentifier("running.close")
                }
                if result == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            automaticStartAttempted = true
                            controller.cancelCountdown()
                            settingsKindAtOpen = settings.defaultRunningKind
                            showingSettings = true
                        } label: { Image("running_setting").resizable().scaledToFit().frame(width: 22, height: 22) }
                            .accessibilityLabel(Text("runningSettings.title")).accessibilityIdentifier("running.openSettings")
                    }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                model.refreshRunningSettings()
                if controller.session == nil, settingsKindAtOpen != settings.defaultRunningKind {
                    controller.selectKind(kind == .cycling ? .cycling : settings.defaultRunningKind)
                }
                if result == nil { controller.prepare() }
                updateScreenAwake()
            }) { RunningSettingsView() }
            .overlay { countdownOverlay }
            .confirmationDialog("running.finishConfirmation", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("running.save") { Task { await finish() } }.accessibilityIdentifier("running.confirmFinish")
                Button("action.cancel", role: .cancel) {}
            } message: { Text("running.finishMessage") }
            .confirmationDialog("running.discardConfirmation", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("running.discard", role: .destructive) {
                    Task {
                        await controller.discard()
                        if controller.session == nil { controller.prepare() }
                    }
                }
                    .accessibilityIdentifier("running.confirmDiscard")
                Button("action.cancel", role: .cancel) {}
            }
            .onAppear {
                visible = true
                if controller.session?.phase == .running { controlsLocked = settings.autoLock }
                updateScreenAwake()
            }
            .task {
                controller.selectKind(kind == .cycling ? .cycling : settings.defaultRunningKind)
                controller.prepare()
                attemptAutomaticStart()
            }
            .onDisappear {
                visible = false
                controller.cancelCountdown()
                controller.stopPreparing()
                updateScreenAwake()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, result == nil {
                    controller.prepare()
                    attemptAutomaticStart()
                } else {
                    controller.cancelCountdown()
                    controller.stopPreparing()
                }
                updateScreenAwake()
            }
            .onChange(of: readyToStart) { _, ready in if ready { attemptAutomaticStart() } }
            .onChange(of: showingSettings) { _, _ in updateScreenAwake() }
            .onChange(of: settings) { old, new in
                model.refreshRunningSettings()
                if new.autoLock != old.autoLock { controlsLocked = new.autoLock && controller.session?.phase == .running }
                updateScreenAwake()
            }
            .onChange(of: controller.session?.phase) { _, phase in
                if phase == .running { controlsLocked = settings.autoLock }
                else if phase == nil || phase == .finished { controlsLocked = false }
                updateScreenAwake()
            }
        }.tint(Color(hex: 0x222222))
    }

    private var preparation: some View {
        VStack(spacing: 0) {
            Group {
                if currentKind.usesGPS {
                    ZStack(alignment: .top) {
                        RunningRouteMap(segments: [], showsUser: controller.authorization == .authorized)
                        permissionStatus.padding(18).frame(maxWidth: .infinity)
                            .background(.regularMaterial).padding(16)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            permissionStatus.padding(18).frame(maxWidth: .infinity)
                            indoorArtwork
                            Text("running.indoorPrepare").font(.system(size: 16, weight: .semibold))
                                .multilineTextAlignment(.center)
                            Text("running.indoorCarryPhone").font(.system(size: 13)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }.padding(24).frame(maxWidth: .infinity)
                    }.background(Color(hex: 0xF6F6F6))
                }
            }.frame(maxHeight: .infinity)
            VStack(spacing: 14) {
                errorStatus
                Button { automaticStartAttempted = true; Task { await controller.start() } } label: {
                    Text("running.start").font(.system(size: 18, weight: .bold))
                        .frame(width: 84, height: 84)
                        .background(Color(hex: 0xFFD838), in: Circle())
                        .background(Image("run_prepare_oval_shadow").resizable().frame(width: 100, height: 100))
                }.buttonStyle(.plain).accessibilityIdentifier("running.start")
                    .disabled(!readyToStart || controller.isBusy || controller.countdownRemaining != nil)
                    .opacity(readyToStart ? 1 : 0.45)
                modeSelector
                Text(LocalizedStringKey(currentKind.usesGPS ? "running.prepareHint" : "running.indoorDistanceHint")).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: .infinity)
                .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 8, y: -4)
        }
    }

    private var indoorArtwork: some View {
        // The source artwork contains Chinese lettering. Cover only the lettering inside
        // its original speech bubble so every locale keeps the same illustration.
        Image("running_pre_indoor_des").resizable().aspectRatio(528.0 / 374.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let scale = geometry.size.width / 528
                    Text("running.indoorArtworkTip")
                        .font(.system(size: 25 * scale, weight: .medium))
                        .foregroundStyle(.white).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .frame(width: 210 * scale, height: 67 * scale)
                        .background(Color(.sRGB, red: 53 / 255.0, green: 184 / 255.0, blue: 207 / 255.0))
                        .position(x: 397 * scale, y: 41.5 * scale)
                }
            }.frame(width: 220, height: 220 * 374 / 528).accessibilityHidden(true)
    }

    private var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(RunningKind.allCases, id: \.self) { mode in
                Button { automaticStartAttempted = true; controller.selectKind(mode); controller.prepare() } label: {
                    Text(LocalizedStringKey(mode.titleKey)).font(.system(size: 14, weight: currentKind == mode ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(currentKind == mode ? Color(hex: 0xFFCB11) : .clear, in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier(mode == .indoor ? "running.mode.indoor" : mode == .cycling ? "running.mode.cycling" : "running.mode.outdoor")
                    .accessibilityAddTraits(currentKind == mode ? .isSelected : [])
            }
        }.padding(2).overlay(Capsule().stroke(Color(hex: 0xDCDCE4), lineWidth: 0.5))
            .disabled(controller.isBusy)
    }

    @ViewBuilder private var permissionStatus: some View {
        VStack(spacing: 10) {
            switch controller.authorization {
            case .notDetermined:
                Text(LocalizedStringKey(currentKind.usesGPS ? "running.permission" : "running.motionPermission"))
                Button(LocalizedStringKey(currentKind.usesGPS ? "running.authorize" : "running.motionAuthorize")) { controller.requestPermission() }.fontWeight(.semibold)
                    .accessibilityIdentifier("running.authorize")
            case .denied, .restricted:
                Text(LocalizedStringKey(currentKind.usesGPS ? "running.denied" : "running.motionDenied")).accessibilityIdentifier("running.denied")
                Button("running.settings") { openSettings() }.fontWeight(.semibold)
                    .accessibilityIdentifier("running.settings")
            case .unavailable:
                Text(LocalizedStringKey(currentKind.usesGPS ? "running.unavailable" : "running.motionUnavailable")).accessibilityIdentifier("running.unavailable")
                Button("running.settings") { openSettings() }
            case .authorized:
                if currentKind.usesGPS { gpsStatus }
                else { Text(LocalizedStringKey(controller.motionReady ? "running.motionReady" : "running.motionUnavailable")).accessibilityIdentifier("running.motionStatus") }
            }
        }.font(.system(size: 14)).multilineTextAlignment(.center)
    }

    private var gpsStatus: some View {
        HStack(spacing: 8) {
            Image(controller.locationReady ? "gps_3" : "gps_1").resizable().scaledToFit().frame(width: 16, height: 16)
            Text(LocalizedStringKey(controller.locationReady ? "running.gpsReady" : "running.gpsWaiting"))
                .accessibilityIdentifier(controller.locationReady ? "running.gpsReady" : "running.gpsWaiting")
        }.font(.system(size: 13))
    }

    private func activeSession(_ session: RunningSession) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                if controller.isRecovered {
                    Text("running.recovered").font(.system(size: 14)).multilineTextAlignment(.center)
                        .padding(14).frame(maxWidth: .infinity).background(Color(hex: 0xFFD838).opacity(0.22))
                        .accessibilityIdentifier("running.recovered")
                }
                if session.phase == .running || controller.authorization != .authorized { permissionStatus }
                Text(LocalizedStringKey(session.phase == .running ? "running.inProgress" : session.phase == .paused ? (controller.isAutoPaused ? "runningSettings.autoPaused" : "running.paused") : "running.pendingSave"))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("running.state")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 25) {
                        VStack(spacing: 8) {
                            Text(RunningDisplay.duration(session.elapsed(at: context.date)))
                                .font(.system(size: 58, weight: .light, design: .rounded)).monospacedDigit()
                                .minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("running.duration")
                            Text("running.duration").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        HStack {
                            metric(RunningDisplay.distance(session.distanceMeters, locale: locale), label: "running.kilometers", identifier: "running.distance")
                            Rectangle().fill(.black.opacity(0.15)).frame(width: 1, height: 42)
                            if session.kind == .cycling {
                                metric(RunningDisplay.speed(distance: session.distanceMeters, seconds: session.elapsed(at: context.date), locale: locale), label: "running.speedUnit", identifier: "running.speed")
                            } else {
                                metric(RunningDisplay.pace(distance: session.distanceMeters, seconds: session.elapsed(at: context.date)), label: "running.paceUnit")
                            }
                        }
                    }
                }
                if session.kind.usesGPS {
                    RunningRouteMap(segments: session.segments, showsUser: controller.authorization == .authorized)
                        .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    metric(session.steps.formatted(.number.locale(locale)), label: "running.steps", identifier: "running.steps")
                        .padding(.vertical, 20)
                    Text("running.indoorDistanceHint").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                errorStatus
                controls(session)
                Text("running.closeHint").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24)
        }
    }

    @ViewBuilder private func controls(_ session: RunningSession) -> some View {
        if controlsLocked {
            VStack(spacing: 10) {
                Image("running_lock").resizable().scaledToFit().frame(width: 26, height: 30)
                Text("runningSettings.holdToUnlock").font(.system(size: 14, weight: .medium))
            }.padding(22).frame(maxWidth: .infinity)
                .background(Color(hex: 0xE6E6E6), in: Capsule())
                .contentShape(Capsule())
                .onLongPressGesture(minimumDuration: 1) { controlsLocked = false }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("runningSettings.holdToUnlock"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("runningSettings.unlock")) { controlsLocked = false }
                .accessibilityIdentifier("running.unlock")
        } else {
        VStack(spacing: 16) {
            HStack(spacing: 42) {
                if session.phase == .running {
                    imageButton("running_puase", label: "running.pause", identifier: "running.pause") { await controller.pause() }
                } else if session.phase == .paused {
                    imageButton("running_start", label: "running.resume", identifier: "running.resume") { await controller.resume() }
                    imageButton("running_stop", label: "running.finish", identifier: "running.finish") { confirmingFinish = true }
                } else {
                    Button("running.retrySave") { Task { await finish() } }.buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0xFFD838)).accessibilityIdentifier("running.retrySave")
                }
            }
            if session.phase != .running {
                Button("running.discard", role: .destructive) { confirmingDiscard = true }
                    .font(.system(size: 13)).accessibilityIdentifier("running.discard")
            }
            if controller.isBusy { ProgressView() }
        }.disabled(controller.isBusy)
        }
    }

    private func imageButton(_ image: String, label: LocalizedStringKey, identifier: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            VStack(spacing: 8) {
                Image(image).resizable().scaledToFit().frame(width: 90, height: 90)
                Text(label).font(.system(size: 13))
            }
        }.buttonStyle(.plain).accessibilityLabel(Text(label)).accessibilityIdentifier(identifier)
    }

    private func metric(_ value: String, label: LocalizedStringKey, identifier: String = "running.pace") -> some View {
        VStack(spacing: 8) {
            Text(verbatim: value).font(.system(size: 32, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier(identifier)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private var errorStatus: some View {
        if let key = controller.errorKey {
            VStack(spacing: 10) {
                Text(LocalizedStringKey(key == "running.tooShort" && currentKind == .cycling ? "running.cyclingTooShort" : key)).font(.system(size: 14)).foregroundStyle(.red).multilineTextAlignment(.center)
                    .accessibilityIdentifier("running.error")
                if key == "running.saveFailed", controller.session?.phase != .finished {
                    Button("running.retrySave") { Task { await controller.tick() } }
                        .accessibilityIdentifier("running.retrySave").disabled(controller.isBusy)
                } else if key == "running.motionFailed" {
                    Button("running.retryMotion") { controller.prepare() }
                        .accessibilityIdentifier("running.retryMotion").disabled(controller.isBusy)
                } else if key == "running.locationFailed" {
                    Button("running.retryLocation") { controller.prepare() }
                        .accessibilityIdentifier("running.retryLocation").disabled(controller.isBusy)
                }
            }
        }
    }

    @ViewBuilder private var countdownOverlay: some View {
        if let remaining = controller.countdownRemaining {
            VStack(spacing: 28) {
                Text(remaining.formatted(.number.locale(locale)))
                    .font(.system(size: 110, weight: .light, design: .rounded)).monospacedDigit()
                    .accessibilityIdentifier("running.countdown")
                Text("runningSettings.ready").font(.system(size: 20, weight: .medium))
                Button("action.cancel") {
                    automaticStartAttempted = true
                    controller.cancelCountdown()
                }.font(.system(size: 17)).accessibilityIdentifier("running.cancelCountdown")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: 0xFFD838).opacity(0.98))
                .accessibilityElement(children: .contain)
        }
    }

    private func attemptAutomaticStart() {
        guard visible, scenePhase == .active, !showingSettings, !settings.confirmBeforeStart,
              !automaticStartAttempted, controller.session == nil, result == nil,
              controller.countdownRemaining == nil, readyToStart else { return }
        automaticStartAttempted = true
        Task { await controller.start() }
    }

    private func updateScreenAwake() {
        screenAwake.update(active: visible && !showingSettings && scenePhase == .active
                           && controller.session?.phase == .running && settings.keepScreenOn)
    }

    private func finish() async {
        await controller.finish()
        if controller.session == nil, controller.errorKey == nil { result = controller.lastFinishedSession }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
