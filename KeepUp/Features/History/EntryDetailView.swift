import SwiftUI
import Photos

struct EntryDetailView: View {
    let entry: CheckInEntry
    let card: HabitCard
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var showingDelete = false
    @State private var busy = false
    @State private var editing = false
    @State private var showingReminder = false
    @State private var shareImage: ShareImage?
    @State private var message: String?
    @State private var encouragementDay = LocalDay(date: .now)
    private var current: CheckInEntry { model.snapshot.entries.first { $0.id == entry.id } ?? entry }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                EntryPoster(entry: current, card: card, entries: model.snapshot.entries, locale: locale, wakes: model.snapshot.wakeUps, weights: model.snapshot.weights, profileHeight: model.snapshot.profile?.height, referenceDay: encouragementDay)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityIdentifier("entry.poster")
            }.ignoresSafeArea(edges: .bottom)
                .navigationTitle(Text(verbatim: String(format: localized("entry.detailTitle %@", locale), localized(card.titleKey, locale))))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(KeepUpStyle.theme, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(Text("action.close")).accessibilityIdentifier("entry.close")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if !model.snapshot.archivedCardIDs.contains(card.id) { Button("reminder.title", systemImage: "alarm") { showingReminder = true }.accessibilityIdentifier("entry.reminder") }
                            Button("content.edit", systemImage: "square.and.pencil") { editing = true }.accessibilityIdentifier("entry.editContent")
                            Button("action.delete", systemImage: "trash", role: .destructive) { showingDelete = true }.accessibilityIdentifier("entry.delete")
                        } label: { Image(systemName: "ellipsis") }.accessibilityLabel(Text("entry.actions")).accessibilityIdentifier("entry.actions")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { renderShare() } label: { Image("card_detail_ic_share").renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24) }
                            .accessibilityLabel(Text("entry.share")).accessibilityIdentifier("entry.share").disabled(busy)
                    }
                }
                .confirmationDialog("entry.deleteConfirmation", isPresented: $showingDelete, titleVisibility: .visible) {
                    Button("action.delete", role: .destructive) {
                        busy = true
                        Task { model.actionError = nil; await model.delete(current); busy = false; if model.actionError == nil { dismiss() } }
                    }.accessibilityIdentifier("entry.confirmDelete")
                    Button("action.cancel", role: .cancel) {}
                }
                .fullScreenCover(isPresented: $showingReminder) { ReminderSettingsView(card: card, target: model.snapshot.targets.first { $0.cardID == card.id }) }
                .fullScreenCover(isPresented: $editing) { EntryContentEditor(entry: current, card: card) }
                .sheet(item: $shareImage) { share in
                    EntrySharePreview(image: share.image)
                }
                .alert("error.title", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("action.ok") { message = nil }
                } message: { Text(LocalizedStringKey(message ?? "error.storage")) }
        }
    }
    @MainActor private func renderShare() {
        let poster = VStack(spacing: 0) {
            EntryPoster(entry: current, card: card, entries: model.snapshot.entries, locale: locale, wakes: model.snapshot.wakeUps, weights: model.snapshot.weights, profileHeight: model.snapshot.profile?.height, referenceDay: encouragementDay).frame(width: 375, height: 700)
            HStack { Text("KeepUp").font(.system(size: 24, weight: .bold)); Spacer(); Text(current.day.date(), format: .dateTime.year().month().day()).font(.system(size: 13)) }
                .padding(24).frame(width: 375, height: 80).background(.white)
        }.environment(\.locale, locale).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: poster); renderer.scale = 3
        guard let image = renderer.uiImage else { message = "entry.shareError"; return }
        shareImage = ShareImage(image: image)
    }
}
private struct ShareImage: Identifiable { let id = UUID(); let image: UIImage }

struct EntryPoster: View {
    let entry: CheckInEntry
    let card: HabitCard
    let entries: [CheckInEntry]
    let locale: Locale
    var wakes: [String: WakeUpRecord] = [:]
    var weights: [String: WeightRecord] = [:]
    var profileHeight: Double? = nil
    var referenceDay = LocalDay(date: .now)
    private var name: String { localized(card.titleKey, locale) }
    private var title: String {
        guard let quantity = entry.quantity else { return name }
        let value = quantity.formatted(.number.precision(.fractionLength(card.id == "punchcard.50" ? 1...1 : 0...1)).locale(locale))
        let unit = localized(entry.unit.titleKey, locale)
        return locale.identifier.hasPrefix("zh") ? "\(name)\(value)\(unit)" : "\(name) \(value) \(unit)"
    }
    private var encouragement: String {
        EntryEncouragement.selected(entry: entry, card: card, entries: entries, weight: weights[entry.id], today: referenceDay)
            .text(card: card, locale: locale)
    }
    var body: some View {
        if let wake = wakes[entry.id] { WakeUpPoster(entry: entry, record: wake, entries: entries, wakes: wakes, locale: locale) } else {
        GeometryReader { geometry in
            let s = geometry.size.width/375
            let cityHeight = geometry.size.width * 272 / 750
            let small = [16,49,51,55,57].contains(OriginalCatalog.item(card)?.number ?? 0)
            let artworkScale = (small ? 0.8 : 1) * (s > 1 ? 1.2 : s < 1 ? 0.9 : 1.05)
            ZStack(alignment: .top) {
                CardDetailThemeBackground()
                Circle().fill(CalendarTheme.selected.color.opacity(0.10)).frame(width: 272*s, height: 272*s).offset(y: 98)
                Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(CalendarTheme.selected.detailTextColor).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: max(0, geometry.size.width-20), height: 25).offset(y: 25)
                if let calories = ActivityEnergy.calories(entry: entry, card: card) {
                    Text(ActivityEnergy.description(calories: calories, locale: locale))
                        .font(.system(size: 13*s)).foregroundStyle(CalendarTheme.selected.detailTextColor).multilineTextAlignment(.center)
                        .frame(width: max(0, geometry.size.width-30*s)).offset(y: 60)
                        .accessibilityIdentifier("energy.poster")
                }
                if card.id == "punchcard.50", let quantity = entry.quantity {
                    WeightBMILabel(weight: quantity, height: weights[entry.id]?.height ?? profileHeight, locale: locale, highlight: false)
                        .font(.system(size: 13)).foregroundStyle(CalendarTheme.selected.detailTextColor).offset(y: 55)
                }
                Image(card.cardImage).resizable().frame(width: 330*artworkScale, height: 390*artworkScale)
                    .scaleEffect(0.8)
                    .position(x: geometry.size.width/2, y: (geometry.size.height-cityHeight)/2-10).accessibilityHidden(true)
            }.overlay(alignment: .bottom) {
                Text(encouragement).font(.system(size: 17*s, weight: .bold)).foregroundStyle(Color(white: 0.16)).multilineTextAlignment(.center).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: max(0, geometry.size.width-60*s)).padding(.bottom, cityHeight + 16*s)
            }.clipped()
        }
        }
    }
}

struct EntrySharePreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView { Image(uiImage: image).resizable().scaledToFit().padding(16) }
                .background(Color(white: 0.94)).navigationTitle("entry.share").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { dismiss() }.accessibilityIdentifier("entry.shareClose")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button("entry.saveImage", systemImage: "square.and.arrow.down") { savePhoto() }.accessibilityIdentifier("entry.saveImage")
                        Spacer()
                        Button("entry.share", systemImage: "square.and.arrow.up") { sharing = true }.accessibilityIdentifier("entry.shareSystem")
                    }.padding(20).background(.regularMaterial).disabled(saving)
                }
                .sheet(isPresented: $sharing) { SystemImageShare(image: image) }
                .alert("entry.share", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    if message == "entry.photoDenied" {
                        Button("steps.settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.accessibilityIdentifier("entry.photoSettings")
                    }
                    Button("action.ok") { message = nil }
                } message: { Text(LocalizedStringKey(message ?? "entry.shareError")) }
        }
    }
    private func savePhoto() {
        saving = true
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { message = "entry.photoDenied"; saving = false; return }
            do {
                guard let data = image.pngData() else { message = "entry.shareError"; saving = false; return }
                // Photos executes changes on its own queue; do not inherit the view's MainActor.
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
                message = "entry.imageSaved"
            } catch { message = "entry.shareError" }
            saving = false
        }
    }
}
struct SystemImageShare: UIViewControllerRepresentable {
    let items: [Any]
    init(image: UIImage) { items = [image] }
    init(images: [UIImage]) { items = images }
    init(files: [URL]) { items = files }
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
