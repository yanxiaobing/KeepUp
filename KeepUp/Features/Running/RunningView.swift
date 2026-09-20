import SwiftUI

struct RunningView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingFinish = false
    @State private var confirmingDiscard = false
    @State private var result: RunningSession?
    private var controller: RunningController { model.running }

    var body: some View {
        NavigationStack {
            Group {
                if let result { RunningSessionSummary(session: result) }
                else if let session = controller.session { activeSession(session) }
                else { preparation }
            }
            .background(.white)
            .navigationTitle(LocalizedStringKey(result == nil ? "running.outdoor" : "running.result"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }.accessibilityIdentifier("running.close")
                }
            }
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
            .task { controller.prepare() }
            .onDisappear { controller.stopPreparing() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { controller.prepare() }
                else { controller.stopPreparing() }
            }
        }.tint(Color(hex: 0x222222))
    }

    private var preparation: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RunningRouteMap(segments: [], showsUser: controller.authorization == .authorized)
                permissionStatus.padding(18).frame(maxWidth: .infinity)
                    .background(.regularMaterial).padding(16)
            }.frame(maxHeight: .infinity)
            VStack(spacing: 14) {
                errorStatus
                Button { Task { await controller.start() } } label: {
                    Text("running.start").font(.system(size: 18, weight: .bold))
                        .frame(width: 84, height: 84)
                        .background(Color(hex: 0xFFD838), in: Circle())
                        .background(Image("run_prepare_oval_shadow").resizable().frame(width: 100, height: 100))
                }.buttonStyle(.plain).accessibilityIdentifier("running.start")
                    .disabled(controller.authorization != .authorized || !controller.locationReady || controller.isBusy)
                    .opacity(controller.authorization == .authorized && controller.locationReady ? 1 : 0.45)
                Text("running.outdoor").font(.system(size: 16, weight: .medium))
                Text("running.prepareHint").font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.padding(24).frame(maxWidth: .infinity)
                .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 8, y: -4)
        }
    }

    @ViewBuilder private var permissionStatus: some View {
        VStack(spacing: 10) {
            switch controller.authorization {
            case .notDetermined:
                Text("running.permission")
                Button("running.authorize") { controller.requestPermission() }.fontWeight(.semibold)
                    .accessibilityIdentifier("running.authorize")
            case .denied, .restricted:
                Text("running.denied").accessibilityIdentifier("running.denied")
                Button("running.settings") { openSettings() }.fontWeight(.semibold)
                    .accessibilityIdentifier("running.settings")
            case .unavailable:
                Text("running.unavailable").accessibilityIdentifier("running.unavailable")
                Button("running.settings") { openSettings() }
            case .authorized:
                gpsStatus
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
                Text(LocalizedStringKey(session.phase == .running ? "running.inProgress" : session.phase == .paused ? "running.paused" : "running.pendingSave"))
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
                            metric(RunningDisplay.pace(distance: session.distanceMeters, seconds: session.elapsed(at: context.date)), label: "running.paceUnit")
                        }
                    }
                }
                RunningRouteMap(segments: session.segments, showsUser: controller.authorization == .authorized)
                    .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 8))
                errorStatus
                controls(session)
                Text("running.closeHint").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24)
        }
    }

    @ViewBuilder private func controls(_ session: RunningSession) -> some View {
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
                Text(LocalizedStringKey(key)).font(.system(size: 14)).foregroundStyle(.red).multilineTextAlignment(.center)
                    .accessibilityIdentifier("running.error")
                if key == "running.saveFailed", controller.session?.phase != .finished {
                    Button("running.retrySave") { Task { await controller.tick() } }
                        .accessibilityIdentifier("running.retrySave").disabled(controller.isBusy)
                } else if key == "running.locationFailed" {
                    Button("running.retryLocation") { controller.prepare() }
                        .accessibilityIdentifier("running.retryLocation").disabled(controller.isBusy)
                }
            }
        }
    }

    private func finish() async {
        await controller.finish()
        if controller.session == nil, controller.errorKey == nil { result = controller.lastFinishedSession }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
