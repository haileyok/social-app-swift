import Foundation
import Testing

import Persistence

@testable import SettingsLogic

/// The language tables and helpers, ported from `src/locale/languages.ts` and
/// `src/locale/helpers.ts`.
@Suite struct LanguagesTests {

  /// The app-language table is RN's `APP_LANGUAGES`, in source order.
  @Test func appLanguages() {
    #expect(Languages.appLanguages.count == 42)
    #expect(Languages.appLanguages.first?.code2 == "en")
    #expect(Languages.appLanguages.first?.name == "English")
    // The multi-region entries RN ships.
    #expect(Languages.appLanguage(for: "en-GB")?.name == "British English")
    #expect(Languages.appLanguage(for: "pt-BR")?.name.contains("Brazilian Portuguese") == true)
    #expect(Languages.appLanguage(for: "zh-Hans-CN")?.name.contains("Simplified Chinese") == true)
    #expect(Languages.appLanguage(for: "zh-Hant-HK")?.name.contains("Cantonese") == true)
    // An unshipped language is not offered.
    #expect(Languages.appLanguage(for: "xx") == nil)
  }

  /// Every app-language code is unique, so the picker cannot show a duplicate.
  @Test func appLanguageCodesUnique() {
    let codes = Languages.appLanguages.map(\.code2)
    #expect(Set(codes).count == codes.count)
  }

  /// The ISO table has one entry per `code2`, matching RN's dedupe.
  @Test func languageCodesUnique() {
    let codes = Languages.languages.map(\.code2)
    #expect(Set(codes).count == codes.count)
  }

  /// The table's shape is RN's `LANGUAGES` filtered to entries with a `code2`.
  @Test func languageTableShape() {
    #expect(Languages.languages.count == 184)
    // Spot checks across the alphabet.
    #expect(Languages.byCode2["en"]?.name == "English")
    #expect(Languages.byCode2["en"]?.code3 == "eng")
    #expect(Languages.byCode2["ja"]?.name == "Japanese")
    #expect(Languages.byCode2["de"]?.name == "German")
    #expect(Languages.byCode2["zu"]?.name == "Zulu")
    // Every entry is complete.
    #expect(Languages.languages.allSatisfy { !$0.code2.isEmpty && !$0.code3.isEmpty })
  }

  /// `code3ToCode2` and `code2ToCode3` are inverse for known codes and pass
  /// unknown ones through.
  @Test func codeConversion() {
    #expect(Languages.code3ToCode2("eng") == "en")
    #expect(Languages.code2ToCode3("en") == "eng")
    // A two-letter input is returned untouched by `code3ToCode2`.
    #expect(Languages.code3ToCode2("en") == "en")
    // An unknown code is returned unchanged.
    #expect(Languages.code3ToCode2("zzz") == "zzz")
    #expect(Languages.code2ToCode3("zz") == "zz")
  }

  /// `name(forCode:)` resolves through either code length.
  @Test func nameLookup() {
    #expect(Languages.name(forCode: "en") == "English")
    #expect(Languages.name(forCode: "eng") == "English")
    #expect(Languages.name(forCode: "ja") == "Japanese")
    // An unknown code falls back to itself.
    #expect(Languages.name(forCode: "zz") == "zz")
  }

  /// `fixLegacyLanguageCode` maps the Java-era codes.
  @Test func legacyCodes() {
    #expect(Languages.fixLegacyLanguageCode("in") == "id")
    #expect(Languages.fixLegacyLanguageCode("iw") == "he")
    #expect(Languages.fixLegacyLanguageCode("en") == "en")
  }
}

/// The app-language sanitizer, ported from `sanitizeAppLanguageSetting`.
@Suite struct AppLanguageSanitizerTests {

  /// A valid code passes through.
  @Test func validCode() {
    #expect(LanguageRules.sanitizeAppLanguageSetting("en") == "en")
    #expect(LanguageRules.sanitizeAppLanguageSetting("de") == "de")
    #expect(LanguageRules.sanitizeAppLanguageSetting("en-GB") == "en-GB")
    #expect(LanguageRules.sanitizeAppLanguageSetting("pt-BR") == "pt-BR")
    #expect(LanguageRules.sanitizeAppLanguageSetting("zh-Hans-CN") == "zh-Hans-CN")
    #expect(LanguageRules.sanitizeAppLanguageSetting("zh-Hant-TW") == "zh-Hant-TW")
  }

  /// A comma-separated post-language value yields its first shipped language.
  ///
  /// This is the bug the helper exists to repair: a past refactor wrote
  /// `postLanguage` (comma-separated) into `appLanguage`.
  @Test func commaSeparatedValue() {
    #expect(LanguageRules.sanitizeAppLanguageSetting("de,en") == "de")
    #expect(LanguageRules.sanitizeAppLanguageSetting("fr,es,de") == "fr")
  }

  /// An unshipped first value is skipped in favour of a shipped later one.
  @Test func unshippedFirstValue() {
    #expect(LanguageRules.sanitizeAppLanguageSetting("xx,ja") == "ja")
  }

  /// Nothing recognizable falls back to `en`.
  @Test func fallback() {
    #expect(LanguageRules.sanitizeAppLanguageSetting("") == "en")
    #expect(LanguageRules.sanitizeAppLanguageSetting("nonsense") == "en")
    #expect(LanguageRules.sanitizeAppLanguageSetting("xx,yy") == "en")
  }

  /// The Java-era codes are fixed before matching.
  @Test func legacyCodeRepaired() {
    // `in` is Indonesian; the app ships `id`.
    #expect(LanguageRules.sanitizeAppLanguageSetting("in") == "id")
  }

  /// Empty segments do not break the scan.
  @Test func emptySegments() {
    #expect(LanguageRules.sanitizeAppLanguageSetting(",de") == "de")
    #expect(LanguageRules.sanitizeAppLanguageSetting("de,") == "de")
  }
}

/// The language preferences model, ported from
/// `screens/Settings/LanguageSettings.tsx`.
@Suite struct LanguagePreferencesTests {

  /// Defaults match `LanguagePrefs`'s.
  @Test func defaults() {
    let prefs = LanguagePreferences()
    #expect(prefs.primaryLanguage == "en")
    #expect(prefs.contentLanguages == ["en"])
    #expect(prefs.appLanguage == "en")
  }

  /// The model round-trips through the persisted slice.
  @Test func persistedRoundTrip() {
    let stored = LanguagePrefs(
      primaryLanguage: "de",
      contentLanguages: ["de", "en"],
      postLanguage: "de",
      postLanguageHistory: ["de", "en"],
      appLanguage: "de")
    let prefs = LanguagePreferences(from: stored)

    var back = LanguagePrefs()
    prefs.apply(to: &back)

    #expect(back.primaryLanguage == "de")
    #expect(back.contentLanguages == ["de", "en"])
    #expect(back.postLanguage == "de")
    #expect(back.postLanguageHistory == ["de", "en"])
    #expect(back.appLanguage == "de")
  }

  /// `setPrimaryLanguage` ignores an empty value.
  @Test func setPrimaryIgnoresEmpty() {
    var prefs = LanguagePreferences()
    prefs.setPrimaryLanguage("")
    #expect(prefs.primaryLanguage == "en")
    prefs.setPrimaryLanguage("ja")
    #expect(prefs.primaryLanguage == "ja")
  }

  /// `setAppLanguage` sanitizes.
  @Test func setAppLanguageSanitizes() {
    var prefs = LanguagePreferences()
    prefs.setAppLanguage("de,en")
    #expect(prefs.appLanguage == "de")

    prefs.setAppLanguage("garbage")
    #expect(prefs.appLanguage == "en")

    // An empty value is ignored outright.
    prefs.setAppLanguage("fr")
    prefs.setAppLanguage("")
    #expect(prefs.appLanguage == "fr")
  }

  /// The content-language options are the recent, selected and primary
  /// languages deduped in that order.
  @Test func possibleContentLanguages() {
    let prefs = LanguagePreferences(
      primaryLanguage: "de",
      contentLanguages: ["en", "fr"],
      postLanguageHistory: ["fr", "es"])
    let options = prefs.possibleContentLanguages()
    // History first, then content languages, then primary.
    #expect(options.map(\.code2) == ["fr", "es", "en", "de"])
  }

  /// The option list skips codes the ISO table does not know.
  @Test func possibleLanguagesSkipUnknown() {
    let prefs = LanguagePreferences(
      primaryLanguage: "de", contentLanguages: ["zz"], postLanguageHistory: ["en"])
    #expect(prefs.possibleContentLanguages().map(\.code2) == ["en", "de"])
  }

  /// The legacy-code fix is applied when building the option list.
  @Test func possibleLanguagesFixLegacy() {
    let prefs = LanguagePreferences(
      primaryLanguage: "en", contentLanguages: ["in"], postLanguageHistory: [])
    // `in` becomes `id`, which resolves.
    #expect(prefs.possibleContentLanguages().map(\.code2) == ["id", "en"])
  }

  /// Normalizing a post-language value delegates to `Persistence`.
  @Test func normalizePostLanguage() {
    #expect(LanguageRules.normalizePostLanguage("de,en") == "de,en")
    #expect(LanguageRules.normalizePostLanguage("de-DE") == "de")
  }

  /// The two-letter reduction delegates to `Persistence`.
  @Test func twoLetterCode() {
    #expect(LanguageRules.twoLetterCode("en-GB") == "en")
    #expect(LanguageRules.twoLetterCode("zh-Hant-TW") == "zh")
  }
}

/// The store's language loading.
@Suite struct LanguageStoreTests {

  /// Languages load from the persisted slice through the store.
  @Test func loadLanguages() async {
    let harness = await StoreHarness(
      languagePrefs: LanguagePrefs(
        primaryLanguage: "de", contentLanguages: ["de"], postLanguage: "de",
        postLanguageHistory: ["de"], appLanguage: "de"))
    defer { harness.cleanUp() }

    await harness.store.loadLanguages()

    #expect(harness.store.state.languageStatus == .loaded)
    #expect(harness.store.state.languages.primaryLanguage == "de")
    #expect(harness.store.state.languages.appLanguage == "de")
  }

  /// The default slice yields the defaults.
  @Test func loadLanguagesDefaults() async {
    let harness = await StoreHarness()
    defer { harness.cleanUp() }

    await harness.store.loadLanguages()

    #expect(harness.store.state.languages.primaryLanguage == "en")
    #expect(harness.store.state.languages.contentLanguages == ["en"])
  }
}
