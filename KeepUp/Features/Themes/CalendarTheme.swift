import SwiftUI

struct CalendarTheme: Decodable, Identifiable, Equatable {
    let id: Int
    let city_image: String
    let calendar_background_color: String
    let day_color: String
    let month_color: String
    var transparentCityImage: String { id == 0 ? city_image : city_image + "_transparent" }
    var color: Color { Color(hex: UInt32(calendar_background_color, radix: 16) ?? 0x006db7) }
    var dayColor: Color { Color(hex: UInt32(day_color, radix: 16) ?? 0x5abcff) }
    var detailTextColor: Color {
        let value = UInt32(calendar_background_color, radix: 16) ?? 0x006db7
        func linear(_ component: UInt32) -> Double {
            let color = Double(component) / 255
            return color <= 0.04045 ? color / 12.92 : pow((color + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((value >> 16) & 0xff)
            + 0.7152 * linear((value >> 8) & 0xff)
            + 0.0722 * linear(value & 0xff)
        return luminance >= 0.18 ? .black : .white
    }
    static let all = BundledJSON.required([CalendarTheme].self, named: "themes") { items in
        func validColor(_ value: String) -> Bool { value.count == 6 && UInt32(value, radix: 16) != nil }
        guard !items.isEmpty, Set(items.map(\.id)).count == items.count,
              items.contains(where: { $0.id == 0 }),
              items.allSatisfy({ !$0.city_image.isEmpty && validColor($0.calendar_background_color) && validColor($0.day_color) && validColor($0.month_color) }) else {
            throw BundledJSON.ConfigurationError.invalid("themes: IDs, images or colors")
        }
    }
    static var selected: CalendarTheme {
        all.first { $0.id == Defaults[.themeID] } ?? all[0]
    }
}

struct CardDetailThemeBackground: View {
    private var theme: CalendarTheme { CalendarTheme.selected }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                LinearGradient(stops: [
                    .init(color: theme.color, location: 0),
                    .init(color: .white, location: 0.72)
                ], startPoint: .top, endPoint: .bottom)
                Image(theme.transparentCityImage)
                    .resizable().scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.width * 272 / 750)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

struct ThemeListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var selected: CalendarTheme?
    private var current: CalendarTheme { CalendarTheme.selected }
    private var alternatives: [CalendarTheme] { CalendarTheme.all.filter { $0.id != current.id } }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let s = geometry.size.width/375
                let cityHeight = geometry.size.width * 272/750
                ZStack(alignment: .bottom) {
                    LinearGradient(stops: [
                        .init(color: current.color, location: 0),
                        .init(color: .white, location: 0.72)
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12*s), count: 2), spacing: 18*s) {
                            ForEach(alternatives) { theme in
                                Button { selected = theme } label: {
                                    VStack(spacing: 7*s) {
                                        ThemePageThumbnail(theme: theme, width: (geometry.size.width - 42*s)/2)
                                        Text(verbatim: localized("theme.city.\(theme.id)", locale))
                                            .font(.system(size: 14*s, weight: .medium))
                                            .foregroundStyle(Color(white: 0.2))
                                            .lineLimit(1)
                                    }
                                }.buttonStyle(.plain).accessibilityIdentifier("theme.\(theme.id)")
                                    .accessibilityLabel(Text(verbatim: localized("theme.city.\(theme.id)", locale)))
                            }
                        }
                        .padding(.horizontal, 15*s)
                        .padding(.top, 16*s)
                        .padding(.bottom, cityHeight + 16*s)
                    }
                    .scrollIndicators(.hidden)

                    LinearGradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.25),
                        .init(color: .white.opacity(0.3), location: 0.55),
                        .init(color: .white.opacity(0.7), location: 0.8),
                        .init(color: .white, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                        .frame(height: cityHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Image(current.transparentCityImage)
                        .resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: cityHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea(edges: .bottom)
            }.navigationTitle("theme.list").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text("action.close"))
                        .accessibilityIdentifier("theme.close")
                    }
                }
                .tint(Color(white: 0.2))
                .alert(Text(verbatim: selected.map { localized("theme.city.\($0.id)", locale) } ?? ""),
                       isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
                       presenting: selected) { theme in
                    Button("theme.use") {
                        Defaults[.themeID] = theme.id
                        dismiss()
                    }
                    .tint(KeepUpStyle.accent)
                    .accessibilityIdentifier("theme.apply")
                    Button("action.cancel", role: .cancel) { selected = nil }
                        .accessibilityIdentifier("theme.cancel")
                } message: { theme in
                    Text(verbatim: localized("theme.description.\(theme.id)", locale))
                }
        }
    }
}

struct ThemeCalendarMonth {
    let firstWeekday: Int
    let weekdaySymbols: [String]
    let leadingDayCount: Int
    let dayCount: Int
    let cellCount: Int

    init(date: Date, locale: Locale) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = locale.identifier.hasPrefix("zh") ? 2 : 1
        let weekStart = calendar.firstWeekday
        firstWeekday = weekStart
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        weekdaySymbols = (0..<7).map { symbols[($0 + weekStart - 1) % 7] }
        let monthStart = calendar.dateInterval(of: .month, for: date)!.start
        let offset = (calendar.component(.weekday, from: monthStart) - weekStart + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: date)!.count
        leadingDayCount = offset
        dayCount = days
        cellCount = ((offset + days + 6) / 7) * 7
    }

    func day(at index: Int) -> Int? {
        let day = index - leadingDayCount + 1
        return (0..<cellCount).contains(index) && (1...dayCount).contains(day) ? day : nil
    }
}

private struct ThemePageThumbnail: View {
    let theme: CalendarTheme
    let width: CGFloat
    @Environment(\.locale) private var locale

    var body: some View {
        let monthDate = Date.now
        let month = ThemeCalendarMonth(date: monthDate, locale: locale)
        let height = width * 1.42
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [
                .init(color: theme.color, location: 0),
                .init(color: .white, location: 0.78)
            ], startPoint: .top, endPoint: .bottom)
            Image(theme.transparentCityImage)
                .resizable().scaledToFit()
                .frame(width: width, height: width * 272/750)
            VStack(spacing: width * 0.06) {
                HStack {
                    Text(monthDate.formatted(.dateTime.year().month(.abbreviated).locale(locale)))
                        .font(.system(size: width * 0.085, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Image(systemName: "tshirt.fill")
                        .font(.system(size: width * 0.075))
                }
                HStack(spacing: 0) {
                    ForEach(0..<7) { day in
                        Text(month.weekdaySymbols[day]).frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: width * 0.05))
                .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: width * 0.05) {
                    ForEach(0..<month.cellCount, id: \.self) { index in
                        Text(month.day(at: index).map { String(format: "%02d", $0) } ?? "")
                            .font(.system(size: width * 0.055, weight: .light))
                            .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(Color(white: 0.3))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, width * 0.075)
            .padding(.top, width * 0.08)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.7)) }
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        .accessibilityHidden(true)
    }
}
