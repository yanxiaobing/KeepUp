import SwiftUI

/// Uses lightweight entry summaries; a full track is loaded only when its record is opened.
struct RunningStatisticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var kind: RunningKind?
    @State private var month: LocalDay?
    @State private var detail: CheckInEntry?

    var body: some View {
        let statistics = RunningStatistics(entries: model.snapshot.entries, kind: kind, month: month)
        let grouped = Dictionary(grouping: statistics.entries, by: \.day)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    filters(statistics)
                    if statistics.count == 0 {
                        emptyState(filtered: kind != nil || month != nil)
                    } else {
                        summary(statistics)
                        Text("runningStats.records").font(.headline)
                        ForEach(statistics.days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(dayLabel(day)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                    .padding(.bottom, 10)
                                ForEach(grouped[day] ?? []) { entry in
                                    if let card = model.card(for: entry) {
                                        Button { detail = entry } label: { record(entry, card: card) }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("running.stats.entry.\(entry.id)")
                                    }
                                }
                            }
                        }
                    }
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("runningStats.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("action.close")).accessibilityIdentifier("running.stats.close")
                        .tint(KeepUpStyle.navigationTint)
                }
            }
            .fullScreenCover(item: $detail) { entry in
                if let card = model.card(for: entry) { RunningRecordView(entry: entry, card: card) }
            }
        }
    }

    private func filters(_ statistics: RunningStatistics) -> some View {
        HStack(spacing: 12) {
            Menu {
                Button("runningStats.allModes") { kind = nil }.accessibilityIdentifier("running.stats.mode.all")
                ForEach(RunningKind.allCases, id: \.rawValue) { item in
                    Button(LocalizedStringKey(item.titleKey)) { kind = item }
                        .accessibilityIdentifier("running.stats.mode.\(item.rawValue)")
                }
            } label: {
                filterLabel(kind?.titleKey ?? "runningStats.allModes", localized: true)
            }.accessibilityIdentifier("running.stats.mode")
            Menu {
                Button("runningStats.allTime") { month = nil }.accessibilityIdentifier("running.stats.month.all")
                ForEach(statistics.availableMonths, id: \.self) { item in
                    Button(monthLabel(item)) { month = item }
                        .accessibilityIdentifier("running.stats.month.\(item.rawValue)")
                }
            } label: {
                filterLabel(month.map(monthLabel) ?? localized("runningStats.allTime", locale), localized: false)
            }.accessibilityIdentifier("running.stats.month")
        }.buttonStyle(.plain)
    }

    private func filterLabel(_ label: String, localized isLocalized: Bool) -> some View {
        HStack(spacing: 8) {
            if isLocalized { Text(LocalizedStringKey(label)) } else { Text(verbatim: label) }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
        }.font(.subheadline.weight(.medium)).foregroundStyle(.primary).padding(12)
            .frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func summary(_ statistics: RunningStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 22) {
                metric("runningStats.count", value: statistics.count.formatted(.number.locale(locale)), id: "count")
                metric("runningStats.days", value: statistics.dayCount.formatted(.number.locale(locale)), id: "days")
                metric("runningStats.distance", value: RunningDisplay.distance(statistics.distanceMeters, locale: locale), unit: "running.kilometers", id: "distance")
                metric("running.duration", value: statistics.missingDurationCount == statistics.count ? "—" : duration(statistics.elapsedSeconds), id: "duration")
                metric("runningStats.energy", value: statistics.missingEnergyCount == statistics.count ? "—" : statistics.kilocalories.formatted(.number.locale(locale)), unit: "runningStats.kcal", id: "energy")
                metric("runningStats.longest", value: statistics.longestDistanceMeters.map { RunningDisplay.distance($0, locale: locale) } ?? "—", unit: "running.kilometers", id: "longest")
                if let kind {
                    if kind == .cycling {
                        metric("running.averageSpeed", value: statistics.averageSpeedKilometersPerHour.map { $0.formatted(.number.precision(.fractionLength(1)).locale(locale)) } ?? "—", id: "speed")
                    } else {
                        metric("running.averagePace", value: statistics.averagePaceSecondsPerKilometer.map(pace) ?? "—", id: "pace")
                    }
                }
            }
            if statistics.missingDurationCount > 0 {
                Text("runningStats.durationMissing").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("running.stats.durationMissing")
            }
            if statistics.missingEnergyCount > 0 {
                Text("runningStats.energyMissing").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("running.stats.energyMissing")
            }
            Text("runningStats.scope").font(.footnote).foregroundStyle(.secondary)
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ title: String, value: String, unit: String? = nil, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit()
                    .accessibilityIdentifier("running.stats.\(id)")
                if let unit { Text(LocalizedStringKey(unit)).font(.caption).foregroundStyle(.secondary) }
            }.minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(filtered: Bool) -> some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(filtered ? "runningStats.filteredEmpty" : "runningStats.empty"), systemImage: "figure.run")
        } description: {
            Text(LocalizedStringKey(filtered ? "runningStats.filteredEmptyHint" : "runningStats.emptyHint"))
        }.padding(.top, 40).frame(maxWidth: .infinity).accessibilityIdentifier("running.stats.empty")
    }

    private func record(_ entry: CheckInEntry, card: HabitCard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.runningKind == .cycling ? "bicycle" : "figure.run")
                .font(.title3).foregroundStyle(RunningDetailStyle.color(entry.runningKind ?? .outdoor)).frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(entry.runningKind?.titleKey ?? card.titleKey)).font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(RunningDisplay.distance((entry.quantity ?? 0) * 1_000, locale: locale) + " " + localized("running.kilometers", locale))
                    Text(entry.runningElapsedSeconds.map(duration) ?? "—")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 8)
            .accessibilityElement(children: .combine)
    }

    private func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "—"
    }

    private func pace(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "%d′%02d″", locale: locale, rounded / 60, rounded % 60)
    }

    private func dayLabel(_ day: LocalDay) -> String {
        let formatter = dateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: day.date(in: formatter.timeZone))
    }

    private func monthLabel(_ day: LocalDay) -> String {
        let formatter = dateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: day.date(in: formatter.timeZone))
    }

    private func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        return formatter
    }
}
