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

                    LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
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
                .fullScreenCover(item: $selected) { theme in
                    ThemePreviewView(theme: theme) { Defaults[.themeID] = theme.id; selected = nil; dismiss() }
                        .presentationBackground(.ultraThinMaterial)
                }
        }
    }
}

private struct ThemePageThumbnail: View {
    let theme: CalendarTheme
    let width: CGFloat
    @Environment(\.locale) private var locale

    var body: some View {
        let height = width * 1.42
        let weekdays = locale.identifier.hasPrefix("zh")
            ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["M", "T", "W", "T", "F", "S", "S"]
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [
                .init(color: theme.color, location: 0),
                .init(color: .white, location: 0.78)
            ], startPoint: .top, endPoint: .bottom)
            Image(theme.transparentCityImage)
                .resizable().scaledToFit()
                .frame(width: width, height: width * 272/750)
            VStack(spacing: width * 0.08) {
                HStack {
                    Text(Date.now.formatted(.dateTime.year().month(.abbreviated).locale(locale)))
                        .font(.system(size: width * 0.085, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Image(systemName: "tshirt.fill")
                        .font(.system(size: width * 0.075))
                }
                HStack(spacing: 0) {
                    ForEach(0..<7) { day in
                        Text(weekdays[day]).frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: width * 0.05))
                .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: width * 0.07) {
                    ForEach(1...35, id: \.self) { day in
                        Text(day <= 31 ? String(format: "%02d", day) : "")
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

private struct ThemePreviewView: View {
    let theme: CalendarTheme
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private var isCurrent: Bool { theme.id == CalendarTheme.selected.id }
    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width/375
            let width = geometry.size.width-60*s
            ZStack {
                Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.6)).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        theme.color
                        Image(theme.city_image).resizable().frame(height: width*272/750)
                        if locale.identifier.hasPrefix("zh") {
                            Image("skin_preview_calendar").resizable()
                        } else { englishCalendar(width: width) }
                        Text(verbatim: localized("theme.city.\(theme.id)", locale)).font(.system(size: 18*s, weight: .bold)).foregroundStyle(Color(white: 34/255).opacity(0.8)).padding(15*s)
                    }.frame(width: width, height: width).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(verbatim: localized("theme.description.\(theme.id)", locale)).font(.system(size: 15*s)).lineSpacing(8).foregroundStyle(theme.color).padding(.top, 15*s)
                    Button(isCurrent ? "theme.using" : "theme.use") {
                        apply()
                    }.font(.system(size: 15*s)).foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 15*s).frame(height: 40*s)
                        .background(theme.color.opacity(0.3), in: RoundedRectangle(cornerRadius: 8*s))
                        .frame(maxWidth: .infinity).padding(.top, 50*s).disabled(isCurrent).accessibilityIdentifier("theme.apply")
                }.frame(width: width).frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack {
                    HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 22)).foregroundStyle(.white.opacity(0.7)).frame(width: 44, height: 44) }.accessibilityLabel(Text("action.close")).accessibilityIdentifier("theme.previewClose") }
                    Spacer()
                }.padding(.horizontal, 10*s)
            }
        }
    }
    private func englishCalendar(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: width*272/750)
            HStack { Text("theme.previewDate"); Spacer(); Image(systemName: "tshirt.fill"); Image(systemName: "globe.europe.africa.fill") }
                .font(.system(size: width*0.043)).foregroundStyle(.white).padding(.horizontal, width*0.04).frame(height: width*0.116).background(.black)
            VStack(spacing: width*0.025) {
                HStack { ForEach(["S", "M", "T", "W", "T", "F", "S"].indices, id: \.self) { index in
                    Text(["S", "M", "T", "W", "T", "F", "S"][index]).frame(maxWidth: .infinity)
                } }.font(.system(size: width*0.025)).foregroundStyle(.gray)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: width*0.035) {
                    ForEach(0..<28) { day in Text(day == 0 ? "" : String(format: "%02d", day)).font(.system(size: width*0.035, weight: .light)).foregroundStyle(.gray).frame(maxWidth: .infinity) }
                }
            }.padding(width*0.04).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
        }.padding(.horizontal, width*16/750).padding(.bottom, width*16/750)
    }
}
