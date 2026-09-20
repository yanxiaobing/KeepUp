import Foundation
@_exported import Defaults

extension Defaults.Keys {
    static let privacyAccepted = Key<Bool>("privacyAccepted", default: false, suite: AppPreferences.store)
    static let appLanguage = Key<String>("appLanguage", default: "system", suite: AppPreferences.store)
    static let monthMode = Key<Bool>("monthMode", default: false, suite: AppPreferences.store)
    static let themeID = Key<Int>("themeID", default: 0, suite: AppPreferences.store)
}

enum AppPreferences {
    // Retain the existing suite. App Group entitlement alone does not migrate data.
    private static let migration: Void = {
        guard let domainName = Bundle.main.bundleIdentifier else { return }
        migrateLegacyKeys(in: .standard, domainName: domainName)
    }()

    static var store: UserDefaults {
        _ = migration
        return .standard
    }

    // Defaults observes key paths, so legacy names containing dots must be migrated
    // before Key initialization registers fallback values in this suite.
    static func migrateLegacyKeys(in store: UserDefaults, domainName: String) {
        // Registered fallback values are not saved user choices and must not block migration.
        let saved = store.persistentDomain(forName: domainName) ?? [:]
        for (legacy, current) in [("preference.monthMode", "monthMode"), ("preference.themeID", "themeID")] {
            guard let value = saved[legacy] else { continue }
            if saved[current] == nil {
                store.set(value, forKey: current)
            }
            store.removeObject(forKey: legacy)
        }
    }

    static func reset() {
        Defaults.reset(.privacyAccepted, .appLanguage, .monthMode, .themeID, .stepGoalChanges, .runningSettings)
    }
}
