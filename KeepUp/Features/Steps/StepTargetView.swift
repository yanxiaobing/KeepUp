import SwiftUI

struct StepTargetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Default(.stepGoalChanges) private var changes
    @State private var selection = 5_000
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("steps.dailyGoal").font(.system(size: 18)).padding(.top, 20)
                    ZStack {
                        Picker("steps.dailyGoal", selection: $selection) {
                            ForEach(StepsGoal.choices, id: \.self) { value in
                                Text(value.formatted(.number.grouping(.never))).tag(value)
                            }
                        }.pickerStyle(.wheel).accessibilityIdentifier("stepsTarget.picker")
                        Text("unit.steps").font(.system(size: 16)).minimumScaleFactor(0.7)
                            .frame(width: 36, height: 36).background(Color(hex: 0xFFDE00), in: Circle())
                            .offset(x: 78).allowsHitTesting(false).accessibilityHidden(true)
                    }.frame(height: 240)
                }.frame(maxWidth: .infinity).background(.white).padding(.top, 20)
                Text(changes.isEmpty ? "steps.goalFirst" : "steps.goalTomorrow")
                    .font(.system(size: 14)).foregroundStyle(Color(hex: 0x69696F))
                    .multilineTextAlignment(.center).padding(.horizontal, 20)
                Text("steps.syncHelp").font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            }.background(Color(white: 246/255))
                .navigationTitle("steps.targetSettings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { dismiss() }.disabled(saving).accessibilityIdentifier("stepsTarget.close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("action.save") { Task { await save() } }.disabled(saving).accessibilityIdentifier("stepsTarget.save")
                    }
                }
                .onAppear { selection = changes.keys.max().flatMap { changes[$0] } ?? 5_000 }
                .alert("error.title", isPresented: $failed) { Button("action.ok") {} } message: { Text("error.storage") }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var target = model.snapshot.targets.first { $0.cardID == "punchcard.1" } ?? CardTarget(cardID: "punchcard.1")
        target.isPinned = true
        guard await model.saveTarget(target) else { failed = true; return }
        changes = StepsGoal.updated(changes, value: selection, now: .now, timeZone: .current)
        dismiss()
    }
}
