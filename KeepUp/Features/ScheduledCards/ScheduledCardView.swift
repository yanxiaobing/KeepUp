import SwiftUI

/// PunchCard's PCScheduleViewController: 20pt inset, 274pt note panel, 140 UTF-16 units.
struct ScheduledCardView: View {
    let card: HabitCard
    let day: LocalDay
    let existing: ScheduledCard?
    var onSaved: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var note = ""
    @State private var busy = false
    @State private var deleting = false
    @State private var discarding = false
    @State private var error: String?
    private var future: Bool { day > LocalDay(date: .now) }
    private var summaryPrefix: String {
        let date = day.date().formatted(.dateTime.month().day().locale(locale))
        return locale.identifier.hasPrefix("zh") ? "将在\(date)添加一张 " : "On \(date), add a "
    }
    private var changed: Bool { note != (existing?.note ?? "") }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let s = geometry.size.width / 375
                VStack(alignment: .leading, spacing: 15*s) {
                    let prefix = Text(summaryPrefix).foregroundStyle(Color(white: 0.7))
                    let name = Text(localized(card.titleKey, locale) + (locale.identifier.hasPrefix("zh") ? " 卡" : " card")).font(.system(size: 18, weight: .bold)).foregroundStyle(Color(white: 0.13))
                    Text("\(prefix)\(name)")
                        .font(.system(size: 16*s)).padding(.top, 15*s)
                    ZStack(alignment: .topLeading) {
                        if note.isEmpty { Text("schedule.placeholder").foregroundStyle(Color(white: 0.8)).padding(.horizontal, 15*s).padding(.top, 18*s) }
                        TextEditor(text: $note).scrollContentBackground(.hidden).padding(10*s)
                            .accessibilityIdentifier("schedule.note").disabled(!future)
                    }.font(.system(size: 17)).frame(height: 274*s)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.91), lineWidth: 1))
                    if !future { Text(day < LocalDay(date: .now) ? "schedule.expired" : "feature.pending").font(.footnote).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(.horizontal, 20*s)
            }.background(.white).navigationTitle("schedule.title").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button { if changed { discarding = true } else { dismiss() } } label: { Image(systemName: "chevron.left") }.accessibilityIdentifier("schedule.close").tint(KeepUpStyle.navigationTint) }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if future {
                            Button { Task { await save() } } label: { Image(systemName: "checkmark") }
                                .disabled(busy || !changed || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.utf16.count > 140)
                                .accessibilityLabel(Text(LocalizedStringKey(existing == nil ? "action.save" : "schedule.update")))
                                .accessibilityIdentifier("schedule.save").tint(KeepUpStyle.navigationTint)
                        }
                        if existing != nil { Button(role: .destructive) { deleting = true } label: { Image(systemName: "trash") }.disabled(busy).accessibilityIdentifier("schedule.delete") }
                    }
                }
                .onAppear { note = existing?.note ?? "" }
                .onChange(of: note) { _, value in
                    if value.utf16.count > 140 {
                        var trimmed = value
                        while trimmed.utf16.count > 140 { trimmed.removeLast() }
                        note = trimmed
                    }
                }
                .confirmationDialog("schedule.deleteQuestion", isPresented: $deleting, titleVisibility: .visible) {
                    Button("action.delete", role: .destructive) { Task { busy = true; if let existing { if await model.deleteSchedule(id: existing.id) { dismiss() } else { error = model.actionError; model.actionError = nil } }; busy = false } }.accessibilityIdentifier("schedule.confirmDelete")
                }
                .confirmationDialog("schedule.discardQuestion", isPresented: $discarding, titleVisibility: .visible) {
                    Button("action.discard", role: .destructive) { dismiss() }.accessibilityIdentifier("schedule.discard")
                    Button("action.cancel", role: .cancel) {}
                }
                .alert("error.title", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("action.ok") {} } message: { Text(LocalizedStringKey(error ?? "error.storage")) }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        if await model.saveSchedule(ScheduledCard(cardID: card.id, day: day, note: note)) { dismiss(); onSaved() }
        else { error = model.actionError; model.actionError = nil }
    }
}
