import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var detail: CheckInEntry?
    @State private var editing: CheckInEntry?
    private var days: [LocalDay] { Array(Set(model.snapshot.entries.map(\.day))).sorted(by: >) }

    var body: some View {
        NavigationStack {
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
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(days, id: \.self) { day in
                                Section {
                                    ForEach(model.entries(on: day)) { entry in
                                        if let card = model.card(for: entry) {
                                            Button {
                                                if ["punchcard.1", "punchcard.2", "punchcard.96"].contains(entry.cardID) { detail = entry }
                                                else if model.snapshot.publishedContent(for: entry).isEmpty || model.snapshot.content[entry.id]?.draft != nil { editing = entry }
                                                else { detail = entry }
                                            } label: {
                                                EntryRowView(entry: entry, card: card, content: model.snapshot.publishedContent(for: entry), hasDraft: model.snapshot.content[entry.id]?.draft != nil)
                                            }.buttonStyle(.plain).accessibilityIdentifier("entry.\(entry.id)")
                                                .contextMenu {
                                                    Button("entry.viewCard") { detail = entry }.accessibilityIdentifier("entry.viewCard")
                                                    Button("content.edit") { editing = entry }.accessibilityIdentifier("entry.editContent")
                                                }
                                            Divider().padding(.leading, 73)
                                        }
                                    }
                                } header: {
                                    VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(day.date(), format: .dateTime.year().month().day()).font(.subheadline.weight(.medium))
                                        Spacer()
                                        ForEach(Array(Set(model.entries(on: day).map(\.cardID))).sorted().prefix(5), id: \.self) { id in
                                            if let card = model.snapshot.cards.first(where: { $0.id == id }) { CardSymbol(card: card, size: 24) }
                                        }
                                    }
                                    let calories = model.entries(on: day).reduce(0) { total, entry in
                                        total + (model.card(for: entry).flatMap { ActivityEnergy.calories(entry: entry, card: $0) } ?? 0)
                                    }
                                    if calories > 0 {
                                        Text(String(format: localized("energy.daily", locale), calories.formatted(.number.locale(locale))))
                                            .font(.system(size: 12)).foregroundStyle(.secondary)
                                            .accessibilityIdentifier("energy.dailyTotal")
                                    }
                                    }.padding(.horizontal, 15).padding(.vertical, 12).background(Color(white: 246/255))
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(white: 246/255))
            .fullScreenCover(item: $detail) { entry in
                if entry.cardID == "punchcard.1" { StepsView(day: entry.day) }
                else if let card = model.card(for: entry) {
                    if ["punchcard.2", "punchcard.96"].contains(entry.cardID) { RunningRecordView(entry: entry, card: card) }
                    else { EntryDetailView(entry: entry, card: card) }
                }
            }
            .fullScreenCover(item: $editing) { entry in
                if let card = model.card(for: entry) { EntryContentEditor(entry: entry, card: card) }
            }
            .navigationTitle("nav.history").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KeepUpStyle.theme, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
