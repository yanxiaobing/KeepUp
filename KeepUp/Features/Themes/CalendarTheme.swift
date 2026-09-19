import SwiftUI

struct CalendarTheme: Decodable, Identifiable, Equatable {
    let id: Int
    let city_image: String
    let calendar_background_color: String
    let day_color: String
    let month_color: String
    var color: Color { Color(hex: UInt32(calendar_background_color, radix: 16) ?? 0x006db7) }
    var dayColor: Color { Color(hex: UInt32(day_color, radix: 16) ?? 0x5abcff) }
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

struct ThemeListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var selected: CalendarTheme?
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let s = geometry.size.width/375
                ScrollView {
                    LazyVStack(spacing: 10*s) {
                        ForEach(CalendarTheme.all) { theme in
                            Button { selected = theme } label: {
                                Image(theme.city_image).resizable().frame(height: 136*s).background(.white)
                                    .overlay(alignment: .topLeading) {
                                        Text(verbatim: localized("theme.city.\(theme.id)", locale)).font(.system(size: 18*s, weight: .bold)).foregroundStyle(Color(white: 34/255).opacity(0.8))
                                            .padding(.horizontal, 15*s).padding(.top, 10*s)
                                    }
                            }.buttonStyle(.plain).accessibilityIdentifier("theme.\(theme.id)")
                        }
                    }.padding(.vertical, 10*s)
                }.background(Color(white: 0.96))
            }.navigationTitle("theme.list").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(KeepUpStyle.theme, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() }.accessibilityIdentifier("theme.close") } }
                .fullScreenCover(item: $selected) { theme in
                    ThemePreviewView(theme: theme) { Defaults[.themeID] = theme.id; selected = nil; dismiss() }
                        .presentationBackground(.ultraThinMaterial)
                }
        }
    }
}

private struct ThemePreviewView: View {
    let theme: CalendarTheme
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var membership = MembershipStore()
    @State private var showMembership = false
    @State private var checking = false
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
                        checking = true
                        Task {
                            await membership.refreshEntitlements()
                            checking = false
                            if theme.id == 0 || membership.isPremium { apply() } else { showMembership = true }
                        }
                    }.font(.system(size: 15*s)).foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 15*s).frame(height: 40*s)
                        .background(theme.color.opacity(0.3), in: RoundedRectangle(cornerRadius: 8*s))
                        .frame(maxWidth: .infinity).padding(.top, 50*s).disabled(isCurrent || checking).accessibilityIdentifier("theme.apply")
                }.frame(width: width).frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack {
                    HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 22)).foregroundStyle(.white.opacity(0.7)).frame(width: 44, height: 44) }.accessibilityLabel(Text("action.close")).accessibilityIdentifier("theme.previewClose") }
                    Spacer()
                }.padding(.horizontal, 10*s)
            }
        }.fullScreenCover(isPresented: $showMembership, onDismiss: {
            Task { await membership.refreshEntitlements(); if membership.isPremium { apply() } }
        }) { MembershipView(onClose: { showMembership = false }) }
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
