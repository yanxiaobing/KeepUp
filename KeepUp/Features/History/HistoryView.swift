import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var detail: CheckInEntry?
    @State private var editing: CheckInEntry?
    private var days: [LocalDay] { Array(Set(model.snapshot.entries.map(\.day))).sorted(by: >) }

    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: KeepUpStyle.theme, location: 0),
                .init(color: .white, location: 0.55)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            Group {
                if days.isEmpty {
                    VStack(spacing: 15) {
                        Spacer()
                        Image("pc_no_feed").resizable().scaledToFit().frame(width: 200, height: 200).accessibilityHidden(true)
                        Text("history.emptySubtitle").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Spacer().frame(height: 40)
                    }.frame(maxWidth: .infinity).accessibilityIdentifier("history.empty")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                Section {
                                    ForEach(model.entries(on: day)) { entry in
                                        if let card = model.card(for: entry) {
                                            EntryRowView(entry: entry, card: card,
                                                         steps: model.snapshot.steps[entry.day.rawValue],
                                                         stepGoal: StepsGoal.value(on: entry.day),
                                                         content: model.snapshot.publishedContent(for: entry),
                                                         hasDraft: model.snapshot.content[entry.id]?.draft != nil) {
                                                detail = entry
                                            }
                                                .contextMenu {
                                                    Button("entry.viewCard") { detail = entry }.accessibilityIdentifier("entry.viewCard")
                                                    Button("content.edit") { editing = entry }.accessibilityIdentifier("entry.editContent")
                                                }
                                                .padding(.horizontal, 15)
                                                .padding(.bottom, 10)
                                        }
                                    }
                                } header: {
                                    VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(day.date(), format: .dateTime.year().month().day())
                                            .font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        ForEach(Array(Set(model.entries(on: day).map(\.cardID))).sorted().prefix(5), id: \.self) { id in
                                            if let card = model.snapshot.cards.first(where: { $0.id == id }) {
                                                CardSymbol(card: card, size: 24)
                                            }
                                        }
                                    }
                                    let calories = model.entries(on: day).reduce(0) { total, entry in
                                        total + (model.card(for: entry).flatMap { ActivityEnergy.calories(entry: entry, card: $0) } ?? 0)
                                    }
                                    if calories > 0 {
                                        Text(String(format: localized("energy.burnedShort", locale), calories.formatted(.number.locale(locale))))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .accessibilityIdentifier("energy.dailyTotal")
                                    }
                                    }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .fullScreenCover(item: $detail) { entry in
                if entry.cardID == "punchcard.1" { StepsView(day: entry.day, followsToday: false) }
                else if let card = model.card(for: entry) {
                    if ["punchcard.2", "punchcard.96"].contains(entry.cardID) { RunningRecordView(entry: entry, card: card) }
                    else { EntryDetailView(entry: entry, card: card) }
                }
            }
            .fullScreenCover(item: $editing) { entry in
                if let card = model.card(for: entry) { EntryContentEditor(entry: entry, card: card) }
            }
        }
        .navigationTitle("nav.history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
