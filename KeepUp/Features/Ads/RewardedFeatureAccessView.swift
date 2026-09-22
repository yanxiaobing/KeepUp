import SwiftUI

struct RewardedFeatureAccessView: View {
    enum Decision {
        case reward(RewardedFeatureAccess.Outcome)
        case bypass, premium, cancelled
    }
    let feature: RewardedFeatureAccess.FeatureID
    let complete: (Decision) -> Void
    @Environment(AppAdvertising.self) private var advertising
    @Environment(MembershipStore.self) private var membership
    @State private var showMembership = false
    @State private var status: String?
    @State private var allowUnavailableBypass = false
    @State private var completed = false

    private var titleKey: String {
        switch feature {
        case .stepGoal: "profile.stepTarget"
        case .weightTarget: "profile.weightTarget"
        case .reminders: "profile.alarms"
        }
    }
    private var busy: Bool { advertising.features.isBusy }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "play.rectangle").font(.system(size: 52)).foregroundStyle(KeepUpStyle.accent)
                Text(LocalizedStringKey(titleKey)).font(.title2.bold())
                Text("ads.reward.description").multilineTextAlignment(.center).foregroundStyle(.secondary)
                if advertising.configuration.rewardCount > 1 {
                    Text("\(advertising.features.completedCount) / \(advertising.configuration.rewardCount)")
                        .monospacedDigit().accessibilityIdentifier("reward.progress")
                }
                if busy { ProgressView("ads.reward.loading") }
                if let status { Text(LocalizedStringKey(status)).multilineTextAlignment(.center).foregroundStyle(.secondary) }
                if membership.isPremium {
                    Button("info.continue") { finish(.premium) }.buttonStyle(.borderedProminent)
                } else if (allowUnavailableBypass && !advertising.configuration.hideGiveUpWhenNoAd) || !advertising.requiresReward(for: feature) {
                    Button("ads.reward.continueOnce") { finish(.bypass) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("reward.continueOnce")
                } else {
                    Button("ads.reward.watch", action: watch)
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("reward.watch")
                }
                Button("ads.reward.membership") { showMembership = true }
                    .buttonStyle(.bordered).accessibilityIdentifier("reward.membership")
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(busy || completed)
                .navigationTitle("ads.reward.title").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { finish(.cancelled) }.disabled(false).accessibilityIdentifier("reward.close")
                    }
                }
                .fullScreenCover(isPresented: $showMembership, onDismiss: {
                    if membership.isPremium { finish(.premium) }
                }) { MembershipView(onClose: { showMembership = false }, entryPoint: "limited") }
        }.interactiveDismissDisabled()
            .task(id: advertising.configuration.rewardedAdUnitID) {
                guard advertising.requiresReward(for: feature) else { return }
                let loaded = await advertising.features.controller.preload()
                guard !Task.isCancelled, !completed, !busy else { return }
                if !loaded {
                    allowUnavailableBypass = !advertising.configuration.hideGiveUpWhenNoAd
                    status = allowUnavailableBypass ? "ads.reward.unavailable" : "ads.reward.unavailableRetry"
                }
            }
    }

    private func watch() {
        guard !busy, !completed else { return }
        guard advertising.requiresReward(for: feature) else { return }
        status = nil
        allowUnavailableBypass = false
        advertising.features.request(featureID: feature, requiredCount: advertising.configuration.rewardCount) { outcome in
            guard !completed else { return }
            if outcome.didDismiss, !outcome.granted, case .closed(true) = outcome.terminal {
                // A verified video advances progress; the next watch remains user initiated.
                status = nil
                Task { _ = await advertising.features.controller.preload() }
            } else if outcome.didDismiss && !outcome.granted {
                status = "ads.reward.cancelled"
            } else if outcome.didDismiss {
                // Profile waits for this gate's actual dismissal before chaining another ad.
                finish(.reward(outcome))
            } else {
                switch outcome.terminal {
                case .unavailable:
                    allowUnavailableBypass = !advertising.configuration.hideGiveUpWhenNoAd
                    status = allowUnavailableBypass ? "ads.reward.unavailable" : "ads.reward.unavailableRetry"
                case .cancelled: status = "ads.reward.cancelled"
                default: status = "ads.reward.failed"
                }
            }
        }
    }

    private func finish(_ decision: Decision) {
        guard !completed else { return }
        completed = true
        // A successful closed reward must keep its permit until Profile consumes it.
        if case .reward = decision {} else { advertising.features.cancel() }
        complete(decision)
    }
}
