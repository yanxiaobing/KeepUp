import Foundation
import Testing
import Defaults
@testable import KeepUp

@Test func legacyPreferencesSurviveMigrationAndReopen() throws {
    let name = "KeepUpPreferencesTests-\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: name))
    defer { store.removePersistentDomain(forName: name) }
    store.set("zh-Hans", forKey: "appLanguage")
    store.set(true, forKey: "preference.monthMode")
    store.set(7, forKey: "preference.themeID")
    store.set("unrelated", forKey: "other")

    store.register(defaults: ["themeID": 0, "monthMode": false])
    AppPreferences.migrateLegacyKeys(in: store, domainName: name)
    let reopened = try #require(UserDefaults(suiteName: name))
    let language = Defaults.Key<String>(Defaults.Keys.appLanguage.name, default: "system", suite: reopened)
    let month = Defaults.Key<Bool>(Defaults.Keys.monthMode.name, default: false, suite: reopened)
    let theme = Defaults.Key<Int>(Defaults.Keys.themeID.name, default: 0, suite: reopened)
    #expect(Defaults[language] == "zh-Hans")
    #expect(Defaults[month])
    #expect(Defaults[theme] == 7)
    #expect(reopened.object(forKey: "preference.themeID") == nil)
    #expect(reopened.object(forKey: "preference.monthMode") == nil)

    Defaults[theme] = 9
    #expect(store.integer(forKey: "themeID") == 9)
    Defaults.reset(language, month, theme)
    AppPreferences.migrateLegacyKeys(in: reopened, domainName: name)
    #expect(Defaults[language] == "system")
    #expect(!Defaults[month])
    #expect(Defaults[theme] == 0)
    #expect(store.string(forKey: "other") == "unrelated")
}

@Test func migrationDoesNotOverwriteNewerPreferences() throws {
    let name = "KeepUpPreferencesTests-\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: name))
    defer { store.removePersistentDomain(forName: name) }
    store.set(3, forKey: "preference.themeID")
    store.set(8, forKey: "themeID")
    store.set(true, forKey: "preference.monthMode")
    store.set(false, forKey: "monthMode")
    AppPreferences.migrateLegacyKeys(in: store, domainName: name)
    AppPreferences.migrateLegacyKeys(in: store, domainName: name)
    #expect(store.integer(forKey: "themeID") == 8)
    #expect(!store.bool(forKey: "monthMode"))
}
