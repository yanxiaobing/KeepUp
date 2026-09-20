import SwiftUI

/// Layout and carousel transforms follow BCCreateCustomCardViewController and BCCustomCardUnitsViewController.
struct CustomCardView: View {
    var onCreated: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var imageIndex = 0
    @State private var selectingUnit = false
    @State private var unitIndex = 0
    @State private var error: String?
    @State private var confirming = false
    @State private var saving = false
    @FocusState private var editingName: Bool
    @State private var draftID = "custom." + UUID().uuidString
    private let ink = Color(red: 72/255, green: 72/255, blue: 77/255)
    private var chosenUnit: CardUnit? { unitIndex > 0 ? CustomCardDraft.units[unitIndex-1] : nil }
    private var restoring: Bool {
        model.snapshot.cards.contains { $0.isCustom && $0.titleKey == name && $0.symbol == CustomCardDraft.artworks[imageIndex] && $0.unit == chosenUnit && model.snapshot.archivedCardIDs.contains($0.id) }
    }
    private var draft: CustomCardDraft { .init(id: draftID, name: name, artwork: CustomCardDraft.artworks[imageIndex], unit: chosenUnit ?? .none) }

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width/375
            ZStack(alignment: .top) {
                Color(white: 246/255).ignoresSafeArea()
                Button { if selectingUnit { selectingUnit = false } else { dismiss() } } label: {
                    Image("ic_back").resizable().frame(width: 24*s, height: 24*s).frame(width: 44, height: 44)
                }.position(x: 27*s, y: 19*s).accessibilityLabel(Text("action.back")).accessibilityIdentifier("custom.back")
                Text(LocalizedStringKey(selectingUnit ? "custom.chooseUnit" : "custom.chooseName"))
                    .font(.custom("PingFangSC-Light", size: selectingUnit ? 20*s : 21)).multilineTextAlignment(.center)
                    .frame(width: locale.identifier.hasPrefix("zh") ? 165*s : 230*s, height: 60*s)
                    .position(x: geometry.size.width/2, y: 44 + 30 + 30*s)
                if selectingUnit {
                    unitCarousel(width: geometry.size.width, scale: s).offset(y: 44+30+60*s+76*s)
                    Button { confirming = true } label: {
                        Text("action.done").font(.system(size: 18*s)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 55*s)
                            .background(chosenUnit != nil ? KeepUpStyle.accent : Color(white: 0.78), in: RoundedRectangle(cornerRadius: 10*s))
                    }.disabled(chosenUnit == nil || saving).padding(.horizontal, 15*s)
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 15*s).accessibilityIdentifier("custom.finish")
                } else {
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.white.frame(height: 195*s)
                            HStack(spacing: 9*s) {
                                Image("punch_custom_card_write").resizable().frame(width: 13*s, height: 15*s)
                                TextField("", text: $name, prompt: Text("custom.namePlaceholder").foregroundStyle(.white.opacity(0.6)))
                                    .font(.system(size: 13)).foregroundStyle(.white).tint(.white).focused($editingName)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done)
                                    .onSubmit { validateName(next: false) }.accessibilityIdentifier("custom.name")
                            }.padding(.leading, 18*s).frame(height: 30*s).background(KeepUpStyle.card)
                        }.frame(width: 165*s).overlay(Rectangle().stroke(.black.opacity(0.1), lineWidth: 0.5))
                            .shadow(color: Color(red: 193/255, green: 200/255, blue: 228/255).opacity(0.1), radius: 2, y: 3)
                        artworkCarousel(width: geometry.size.width, scale: s)
                    }.offset(y: 44+30+60*s+32*s)
                    Button { validateName(next: true) } label: { Image("diycard_next").resizable().frame(width: 44*s, height: 44*s) }
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 50*s)
                        .accessibilityLabel(Text("action.next")).accessibilityIdentifier("custom.next")
                }
            }.foregroundStyle(ink)
        }
        .onAppear { editingName = true }
        .alert("error.title", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("action.ok") {}
        } message: { Text(LocalizedStringKey(error ?? "error.storage")) }
        .confirmationDialog(restoring ? "custom.restoreTitle" : "custom.confirmTitle", isPresented: $confirming, titleVisibility: .visible) {
            Button(restoring ? "action.restore" : "action.done") { Task { await save() } }.accessibilityIdentifier("custom.confirm")
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "\(name) · \(localized(chosenUnit == CardUnit.none ? "custom.unitNone" : chosenUnit?.titleKey ?? "custom.unitNone", locale))")
        }
    }
    private func artworkCarousel(width: CGFloat, scale s: CGFloat) -> some View {
        ZStack {
            ForEach(CustomCardDraft.artworks.indices, id: \.self) { index in
                let offset = CGFloat(index-imageIndex)
                let scale: CGFloat = index == imageIndex ? 1 : 0.6
                let radius = 165*s*1.18/2/tan(.pi/4/7)
                Image(CustomCardDraft.artworks[index]).resizable().frame(width: 165*s, height: 195*s)
                    .scaleEffect(scale).offset(x: radius*sin(offset/7 * .pi/2)*1.18*scale)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { imageIndex = index } }
                    .accessibilityLabel(Text(verbatim: String(format: localized("custom.artwork %lld", locale), Int64(index + 1)))).accessibilityIdentifier("custom.artwork.\(index)")
            }
        }.frame(width: width, height: 195*s).clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 15).onEnded { value in
                withAnimation(.easeOut(duration: 0.2)) { imageIndex = min(6, max(0, imageIndex + (value.translation.width < 0 ? 1 : -1))) }
            }).accessibilityElement(children: .contain).accessibilityIdentifier("custom.carousel")
    }
    private func unitCarousel(width: CGFloat, scale s: CGFloat) -> some View {
        ZStack {
            Color.white.frame(height: 62*s).overlay(Rectangle().stroke(.black.opacity(0.1), lineWidth: 0.5))
            RoundedRectangle(cornerRadius: 4).fill(KeepUpStyle.accent).frame(width: 44*s, height: 74*s)
            ForEach((unitIndex == 0 ? 0 : 1)...CustomCardDraft.units.count, id: \.self) { index in
                let offset = CGFloat(index-unitIndex)
                let scale: CGFloat = index == unitIndex ? 1 : 0.85
                let count: CGFloat = unitIndex == 0 ? 7 : 6
                let radius: CGFloat = 50*1.2/2/tan(CGFloat.pi/4/count)
                Text(index == 0 ? "" : localized(CustomCardDraft.units[index-1] == .none ? "custom.unitNone" : CustomCardDraft.units[index-1].titleKey, locale))
                    .font(.system(size: locale.identifier.hasPrefix("zh") ? 16 : 12)).lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(index == unitIndex ? .white : ink.opacity(0.4))
                    .frame(width: 50, height: 62*s).scaleEffect(scale)
                    .offset(x: radius*sin(offset/count * .pi/2)*1.2*scale)
                    .onTapGesture { withAnimation { unitIndex = index } }
                    .accessibilityIdentifier(index == 0 ? "custom.unit.blank" : "custom.unit.\(CustomCardDraft.units[index-1].rawValue)")
            }
        }.frame(width: width, height: 74*s).clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                withAnimation { unitIndex = min(6, max(unitIndex == 0 ? 0 : 1, unitIndex + (value.translation.width < 0 ? 1 : -1))) }
            }).accessibilityElement(children: .contain).accessibilityIdentifier("custom.units")
    }
    private func validateName(next: Bool) {
        do { _ = try draft.validated(); editingName = false; if next { selectingUnit = true } }
        catch { self.error = "custom.invalidName" }
    }
    private func save() async {
        guard chosenUnit != nil, !saving else { return }
        saving = true
        if let id = await model.createCustomCard(draft) { onCreated(id); dismiss() }
        else { error = model.actionError; model.actionError = nil }
        saving = false
    }
}
