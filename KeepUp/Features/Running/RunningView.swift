import SwiftUI

struct RunningView: View {
    var kind: RunningKind = .outdoor
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingFinish = false
    @State private var result: RunningSession?
    @State private var showingSettings = false
    @State private var shareRequest: RunningShareRequest?
    @State private var resultPage = 1
    @State private var resultMapPresentation = RunningMapPresentation()
    @State private var showingLiveMap = false
    @State private var settingsKindAtOpen: RunningKind?
    @State private var visible = false
    @State private var automaticStartAttempted = false
    @State private var controlsLocked = false
    @GestureState(resetTransaction: Transaction(animation: .smooth(duration: 0.2))) private var unlockDrag: CGFloat = 0
    @State private var lockInitializedSessionID: String?
    @State private var screenAwake = RunningScreenAwake()
    @Default(.runningSettings) private var settings
    private var controller: RunningController { model.running }
    private var currentKind: RunningKind { controller.session?.kind ?? controller.selectedKind }
    private var readyToStart: Bool {
        controller.authorization == .authorized && (currentKind.usesGPS ? controller.locationReady : controller.motionReady)
    }
    private var canStartManually: Bool {
        controller.authorization == .authorized && (currentKind.usesGPS || controller.motionReady)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    RunningResultPages(session: result, page: $resultPage,
                                       mapPresentation: $resultMapPresentation)
                }
                else if let session = controller.session { activeSession(session) }
                else { preparation }
            }
            .background(.white)
            .accessibilityHidden(controller.countdownRemaining != nil)
            .navigationTitle(LocalizedStringKey(result == nil ? currentKind.titleKey : "running.result"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(result != nil ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if result != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { controller.cancelCountdown(); dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text("action.close")).accessibilityIdentifier("running.close")
                    }
                }
                if result != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            shareRequest = RunningShareRequest(style: RunningShareStyle(page: resultPage),
                                                                 presentation: resultMapPresentation)
                        } label: { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(Text("entry.share")).accessibilityIdentifier("running.result.share")
                    }
                }
            }
            .sheet(item: $shareRequest) { request in
                if let result {
                    RunningShareView(session: result, style: request.style, presentation: request.presentation)
                }
            }
            .fullScreenCover(isPresented: $showingLiveMap) {
                if let session = controller.session, session.kind.usesGPS {
                    liveMap(session)
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
                Button("running.finish") { Task { await finish() } }.accessibilityIdentifier("running.confirmFinish")
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey(sessionIsTooShort
                    ? (currentKind == .cycling ? "running.cyclingTooShort" : "running.tooShort")
                    : "running.finishMessage"))
            }
            .onAppear {
                visible = true
                if let session = controller.session, session.phase == .running,
                   lockInitializedSessionID != session.id {
                    controlsLocked = settings.autoLock
                    lockInitializedSessionID = session.id
                }
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
            .onChange(of: showingLiveMap) { _, _ in updateScreenAwake() }
            .onChange(of: showingSettings) { _, _ in updateScreenAwake() }
            .onChange(of: settings) { old, new in
                model.refreshRunningSettings()
                if new.autoLock != old.autoLock { controlsLocked = new.autoLock && controller.session?.phase == .running }
                updateScreenAwake()
            }
            .onChange(of: controller.session?.phase) { _, phase in
                if phase == .running {
                    controlsLocked = settings.autoLock
                    lockInitializedSessionID = controller.session?.id
                } else if phase == nil || phase == .finished {
                    controlsLocked = false
                    lockInitializedSessionID = nil
                }
                updateScreenAwake()
            }
        }.tint(Color(hex: 0x222222))
    }

    private var preparation: some View {
        VStack(spacing: 0) {
            Group {
                if currentKind.usesGPS {
                    ZStack(alignment: .top) {
                        RunningRouteMap(segments: [], showsUser: controller.authorization == .authorized,
                                        currentPoint: controller.latestLocationPoint,
                                        followsUser: controller.authorization == .authorized,
                                        isPreparation: true, avatarData: model.snapshot.profile?.avatar)
                            .ignoresSafeArea(edges: .top)
                        if controller.authorization == .authorized {
                            gpsStatus.padding(.top, 80)
                        } else {
                            permissionStatus.padding(18).frame(maxWidth: .infinity)
                                .background(.regularMaterial).padding(.horizontal, 16).padding(.top, 80)
                        }
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
                        }.padding(24).padding(.top, 64).frame(maxWidth: .infinity)
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
                    .disabled(!canStartManually || controller.isBusy || controller.countdownRemaining != nil)
                    .opacity(canStartManually ? 1 : 0.45)
                modeSelector
                Text(LocalizedStringKey(currentKind.usesGPS ? "running.prepareHint" : "running.indoorDistanceHint")).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: .infinity)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                        .fill(.white)
                        .ignoresSafeArea(edges: .bottom)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: -4)
        }
        .overlay(alignment: .top) {
            preparationTopBar.padding(.horizontal, 16).padding(.top, 8)
        }
    }

    private var preparationTopBar: some View {
        ZStack {
            Text(LocalizedStringKey(currentKind.titleKey))
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 92)
            HStack {
                Button { controller.cancelCountdown(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel(Text("action.close"))
                .accessibilityIdentifier("running.close")
                Spacer()
                Button {
                    automaticStartAttempted = true
                    controller.cancelCountdown()
                    settingsKindAtOpen = settings.defaultRunningKind
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel(Text("runningSettings.title"))
                .accessibilityIdentifier("running.openSettings")
            }
        }
        .frame(height: 48)
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
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("GPS").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x222222).opacity(0.8))
                Image(controller.preparationGPSQuality.imageName)
                    .resizable().scaledToFit().frame(width: 12, height: 12)
            }
            .frame(width: 60, height: 21)
            .background(Color(hex: 0xFFD838), in: Capsule())
            .padding(.leading, 3)
            Text(LocalizedStringKey(controller.preparationGPSQuality.messageKey))
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(minWidth: 107)
                .accessibilityIdentifier(controller.locationReady ? "running.gpsReady" : "running.gpsWaiting")
        }
        .frame(height: 27)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color(hex: 0x222222).opacity(0.4), in: Capsule())
    }

    private var showsWeakGPSTip: Bool {
        currentKind.usesGPS && controller.authorization == .authorized && !controller.locationReady
            && (controller.session?.phase == .running || controller.isAutoPaused)
    }

    private var weakGPSTip: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.up.fill")
                .resizable().frame(width: 11, height: 7)
                .foregroundStyle(.white.opacity(0.8))
            Text("running.gpsWeakHint")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x222222).opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("running.gpsWeakHint")
        .allowsHitTesting(false)
    }

    private func activeSession(_ session: RunningSession) -> some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 375, 1.15)
            VStack(spacing: 0) {
                activeTopBar(session)
                    .frame(height: 44)
                    .padding(.horizontal, 15 * scale)
                    .overlay(alignment: .top) {
                        if showsWeakGPSTip {
                            weakGPSTip.padding(.horizontal, 16).padding(.top, 44)
                        }
                    }
                    .zIndex(1)
                if controller.isRecovered {
                    Text("running.recovered")
                        .font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.white.opacity(0.75), in: Capsule())
                        .accessibilityIdentifier("running.recovered")
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    activeMetrics(session, date: context.date, scale: scale)
                }
                .padding(.top, controller.isRecovered ? 42 * scale : 70 * scale)
                Spacer(minLength: 12)
                if controller.authorization != .authorized || controller.errorKey != nil {
                    VStack(spacing: 8) {
                        if controller.authorization != .authorized { permissionStatus }
                        errorStatus
                    }
                    .padding(12).frame(maxWidth: .infinity)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20).padding(.bottom, 10)
                }
                controls(session)
                    .frame(height: 116)
                    .frame(maxWidth: .infinity)
                Color.clear
                    .frame(height: geometry.size.width * 272 / 750)
                    .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                CardDetailThemeBackground()
                    .ignoresSafeArea(edges: .bottom)
            }
            .background { CalendarTheme.selected.color.ignoresSafeArea(edges: .top) }
        }
    }

    private func activeTopBar(_ session: RunningSession) -> some View {
        HStack {
            if session.kind.usesGPS {
                Button { showingLiveMap = true } label: {
                    Image(systemName: "map")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel(Text("running.openMap"))
                .accessibilityIdentifier("running.openMap")
            } else {
                Text(LocalizedStringKey(session.phase == .running ? "running.sensorRecording" : "running.paused"))
                    .font(.system(size: 13)).padding(.horizontal, 15).frame(height: 28)
                    .background(.white.opacity(0.4), in: Capsule())
            }
            Spacer()
            if session.kind.usesGPS {
                HStack(spacing: 5) {
                    Text("GPS").font(.system(size: 12, weight: .bold))
                    Image(controller.locationReady ? "gps_3" : "gps_1")
                        .resizable().frame(width: 12, height: 11)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Button {
                settingsKindAtOpen = settings.defaultRunningKind
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(Text("runningSettings.title"))
            .accessibilityIdentifier("running.openSettings")
        }
        .foregroundStyle(Color(hex: 0x222222))
    }

    private func activeMetrics(_ session: RunningSession, date: Date, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            activeDuration(session.elapsed(at: date), scale: scale)
            Text("running.time")
                .font(.system(size: 16 * scale))
                .foregroundStyle(Color(hex: 0x222222).opacity(0.6))
                .padding(.top, 4)
            HStack(spacing: 0) {
                activeMetric(RunningDisplay.distance(session.distanceMeters, locale: locale), label: "running.kilometers", identifier: "running.distance", scale: scale)
                Rectangle().fill(Color(hex: 0x222222).opacity(0.8)).frame(width: 2, height: 19)
                if session.kind == .cycling {
                    activeMetric(RunningDisplay.speed(distance: session.distanceMeters, seconds: session.elapsed(at: date), locale: locale), label: "running.speedUnit", identifier: "running.speed", scale: scale)
                } else {
                    activeMetric(RunningDisplay.pace(distance: session.distanceMeters, seconds: session.elapsed(at: date)), label: "running.paceUnit", identifier: "running.pace", scale: scale)
                }
            }
            .padding(.top, 51 * scale)
            if !session.kind.usesGPS {
                Text(session.steps.formatted(.number.locale(locale)))
                    .font(.system(size: 16, weight: .medium)).accessibilityIdentifier("running.steps")
                    .padding(.top, 28)
            }
            if session.phase != .running {
                Text(LocalizedStringKey(session.phase == .paused ? (controller.isAutoPaused ? "runningSettings.autoPaused" : "running.paused") : "running.pendingSave"))
                    .font(.system(size: 13)).accessibilityIdentifier("running.state")
                    .padding(.top, 16)
            }
        }
        .foregroundStyle(Color(hex: 0x222222).opacity(0.8))
    }

    private func activeDuration(_ seconds: TimeInterval, scale: CGFloat) -> some View {
        let value = max(0, Int(seconds))
        return HStack(spacing: 0) {
            durationNumber(value / 3_600, scale: scale)
            durationSeparator(scale: scale)
            durationNumber(value / 60 % 60, scale: scale)
            durationSeparator(scale: scale)
            durationNumber(value % 60, scale: scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: RunningDisplay.duration(seconds)))
        .accessibilityIdentifier("running.duration")
    }

    private func durationNumber(_ value: Int, scale: CGFloat) -> some View {
        Text(String(format: "%02d", value))
            .font(.custom("DINCondensedC", size: 70 * scale))
            .frame(width: 80 * scale, height: 70 * scale)
            .minimumScaleFactor(0.7)
    }

    private func durationSeparator(scale: CGFloat) -> some View {
        VStack(spacing: 11 * scale) {
            Rectangle().frame(width: 8 * scale, height: 8 * scale)
            Rectangle().frame(width: 8 * scale, height: 8 * scale)
        }
        .frame(width: 8 * scale, height: 70 * scale)
    }

    private func activeMetric(_ value: String, label: LocalizedStringKey, identifier: String, scale: CGFloat) -> some View {
        VStack(spacing: 9) {
            Text(verbatim: value)
                .font(.custom("DINCondensedC", size: 35 * scale))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityIdentifier(identifier)
            Text(label).font(.system(size: 11 * scale))
                .foregroundStyle(Color(hex: 0x222222).opacity(0.6))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func liveMap(_ session: RunningSession) -> some View {
        ZStack(alignment: .bottom) {
            RunningRouteMap(segments: session.segments, showsUser: controller.authorization == .authorized,
                            currentPoint: controller.latestLocationPoint,
                            followsUser: controller.authorization == .authorized,
                            avatarData: model.snapshot.profile?.avatar)
                .ignoresSafeArea()
            Button { showingLiveMap = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 77, height: 77)
                    .background(Color(hex: 0xFC626F), in: Circle())
            }
            .accessibilityLabel(Text("action.close"))
            .accessibilityIdentifier("running.closeMap")
            .padding(.bottom, 35)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Text("GPS")
                    Image(controller.locationReady ? "gps_3" : "gps_1")
                        .resizable().scaledToFit().frame(width: 14, height: 14)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 25)
                .background(Color(hex: 0xFEC254).opacity(0.9), in: Capsule())
                if showsWeakGPSTip { weakGPSTip.padding(.horizontal, 16) }
            }
            .padding(.top, 12)
        }
    }

    private var controlsTransition: AnyTransition {
        let effect: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92))
        return .asymmetric(
            insertion: effect.animation(.easeInOut(duration: 0.3)),
            removal: effect.animation(.easeOut(duration: 0.15))
        )
    }

    private var controlsFadeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeInOut(duration: 0.3)),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        )
    }

    private func controls(_ session: RunningSession) -> some View {
        ZStack {
            if controlsLocked {
                HStack(spacing: 0) {
                    Image("lockScreen_monkey").resizable().frame(width: 52, height: 58)
                        .offset(x: -10 + unlockDrag)
                        .zIndex(1)
                    Text("running.swipeToUnlock")
                        .font(.system(size: 15)).foregroundStyle(Color(hex: 0x69696F))
                        .frame(maxWidth: .infinity)
                        .opacity(1 - min(unlockDrag / 100, 1))
                    Image("lockScreen_banana").resizable().frame(width: 43, height: 43)
                        .padding(.trailing, 4)
                }.frame(width: 215, height: 50)
                    .background(Color(hex: 0xE6E6E6), in: Capsule())
                    .contentShape(Capsule())
                    .gesture(DragGesture(minimumDistance: 3)
                        .updating($unlockDrag) { value, offset, transaction in
                            transaction.animation = nil
                            offset = min(173, max(0, value.translation.width))
                        }
                        .onEnded { value in
                            if value.translation.width >= 100, abs(value.translation.height) < 80 {
                                controlsLocked = false
                            }
                        })
                    .onLongPressGesture(minimumDuration: 1) { controlsLocked = false }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("running.swipeToUnlock"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: Text("runningSettings.unlock")) { controlsLocked = false }
                    .accessibilityIdentifier("running.unlock")
                    .transition(controlsTransition)
            } else {
                ZStack {
                    if session.phase == .running || session.phase == .paused {
                        HStack(spacing: 50) {
                            ZStack {
                                if session.phase == .running {
                                    imageButton("running_puase", label: "running.pause", identifier: "running.pause") { await controller.pause() }
                                        .transition(controlsFadeTransition)
                                } else {
                                    imageButton("running_start", label: "running.resume", identifier: "running.resume") { await controller.resume() }
                                        .transition(controlsFadeTransition)
                                }
                            }
                            .frame(width: 107, height: 107)
                            if session.phase == .paused {
                                imageButton("running_stop", label: "running.finish", identifier: "running.finish") { confirmingFinish = true }
                                    .transition(controlsTransition)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) {
                            if session.phase == .running {
                                Button { controlsLocked = true } label: {
                                    Image("running_lock").resizable().scaledToFit().frame(width: 22, height: 27)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("running.lock"))
                                .accessibilityIdentifier("running.lock")
                                .padding(.trailing, 46)
                                .transition(controlsFadeTransition)
                            }
                        }
                    } else {
                        Button("running.retrySave") { Task { await finish() } }.buttonStyle(.borderedProminent)
                            .tint(Color(hex: 0xFFD838)).accessibilityIdentifier("running.retrySave")
                            .transition(controlsTransition)
                    }
                }
                .transition(controlsTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 107)
        .disabled(controller.isBusy)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.3), value: session.phase)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.3), value: controlsLocked)
    }

    private func imageButton(_ image: String, label: LocalizedStringKey, identifier: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(image).resizable().scaledToFit().frame(width: 107, height: 107)
        }.buttonStyle(.plain).accessibilityLabel(Text(label)).accessibilityIdentifier(identifier)
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
        screenAwake.update(active: (visible || showingLiveMap) && !showingSettings && scenePhase == .active
                           && controller.session?.phase == .running && settings.keepScreenOn)
    }

    private var sessionIsTooShort: Bool {
        guard let session = controller.session else { return false }
        return session.distanceMeters < session.kind.minimumDistanceMeters
    }

    private func finish() async {
        if sessionIsTooShort {
            await controller.discard()
            if controller.session == nil { dismiss() }
            return
        }
        await controller.finish()
        if controller.session == nil, controller.errorKey == nil {
            resultMapPresentation = .init()
            result = controller.lastFinishedSession
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
