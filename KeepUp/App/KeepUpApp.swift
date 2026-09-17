import SwiftUI
import UserNotifications

enum AppLanguage: String, CaseIterable {
    case system, english = "en", simplifiedChinese = "zh-Hans"
    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        default: Locale(identifier: rawValue)
        }
    }
    var titleKey: String {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .simplifiedChinese: "language.chinese"
        }
    }
}

@main
struct KeepUpApp: App {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("preference.themeID") private var themeID = 0
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.calendar

    init() {
        UNUserNotificationCenter.current().delegate = ReminderNotificationDelegate.shared
        let support = URL.applicationSupportDirectory.appendingPathComponent("KeepUp", isDirectory: true)
        var databaseURL = support.appendingPathComponent("keepup.sqlite")
        #if DEBUG
        // UI tests use an isolated file and never reset a developer's normal app data.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            databaseURL = support.appendingPathComponent("ui-tests/keepup.sqlite")
            if ProcessInfo.processInfo.arguments.contains("-reset-test-data") {
                try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
                UserDefaults.standard.removeObject(forKey: "appLanguage")
                UserDefaults.standard.removeObject(forKey: "preference.monthMode")
                UserDefaults.standard.removeObject(forKey: "preference.themeID")
            }
        }
        #endif
        _model = State(initialValue: AppModel(repository: LocalStore(fileURL: databaseURL)))
    }

    var body: some Scene {
        WindowGroup {
            RootView(selectedTab: $selectedTab)
                .environment(model)
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
                // Rebuild navigation titles as well as content after an in-app language change.
                .id("\(language)-\(themeID)-\(ReminderRoute.shared.requestID)")
                .tint(KeepUpStyle.accent)
                .task(id: "\(model.revision)-\(language)-\(scenePhase)") {
                    if scenePhase == .active && model.isReady {
                        await ReminderScheduler.shared.synchronize(model.snapshot, locale: (AppLanguage(rawValue: language) ?? .system).locale)
                    }
                }
                #if DEBUG
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if ProcessInfo.processInfo.arguments.contains("-ui-testing-large-type") { size = .accessibility3 }
                }
                .preferredColorScheme(.light)
                #endif
        }
    }
}
