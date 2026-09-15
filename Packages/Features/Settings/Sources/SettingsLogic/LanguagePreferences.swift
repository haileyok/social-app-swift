import Foundation
import Persistence

/// The language preferences, ported from `screens/Settings/LanguageSettings.tsx`
/// and `state/preferences/languages.tsx`.
///
/// RN stores five values in `persisted.languagePrefs`, all device scope:
/// `primaryLanguage` (the translate target), `contentLanguages` (the languages
/// fed to feed requests), `postLanguage`, `postLanguageHistory`, and
/// `appLanguage` (the UI translation language).
///
/// The picker's data shapes are here too: the deduped ISO table, the set of
/// languages the content picker should offer first, and the sanitizer that
/// repairs an `appLanguage` value.
public struct LanguagePreferences: Sendable, Equatable {
  /// The target language for translating posts.
  public var primaryLanguage: String
  /// The languages the user can read, sent to feeds.
  public var contentLanguages: [String]
  /// The posting language(s), comma-separated.
  public var postLanguage: String
  /// The recent posting languages.
  public var postLanguageHistory: [String]
  /// The UI translation language.
  public var appLanguage: String

  public init(
    primaryLanguage: String = "en",
    contentLanguages: [String] = ["en"],
    postLanguage: String = "en",
    postLanguageHistory: [String] = ["en"],
    appLanguage: String = "en"
  ) {
    self.primaryLanguage = primaryLanguage
    self.contentLanguages = contentLanguages
    self.postLanguage = postLanguage
    self.postLanguageHistory = postLanguageHistory
    self.appLanguage = appLanguage
  }

  /// Builds the model from the persisted slice.
  public init(from stored: Persistence.LanguagePrefs) {
    self.init(
      primaryLanguage: stored.primaryLanguage,
      contentLanguages: stored.contentLanguages,
      postLanguage: stored.postLanguage,
      postLanguageHistory: stored.postLanguageHistory,
      appLanguage: stored.appLanguage)
  }

  /// Writes the model back into the persisted slice.
  public func apply(to stored: inout Persistence.LanguagePrefs) {
    stored.primaryLanguage = primaryLanguage
    stored.contentLanguages = contentLanguages
    stored.postLanguage = postLanguage
    stored.postLanguageHistory = postLanguageHistory
    stored.appLanguage = appLanguage
  }

  /// The content-language options, in the order the picker shows them.
  ///
  /// Port of `possibleLanguages` in `LanguageSettings.tsx`: the recent
  /// languages, the selected ones, and the primary language, deduped and
  /// resolved against the ISO table. Order matters and is preserved.
  public func possibleContentLanguages() -> [Language] {
    var seen = Set<String>()
    var codes: [String] = []
    for code in postLanguageHistory + contentLanguages + [primaryLanguage] {
      let normalized = Languages.fixLegacyLanguageCode(code)
      guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
      seen.insert(normalized)
      codes.append(normalized)
    }
    return codes.compactMap { Languages.byCode2[$0] }
  }

  /// Sets the primary language, ignoring an empty value the way the screen's
  /// `onChangePrimaryLanguage` does.
  public mutating func setPrimaryLanguage(_ code: String) {
    guard !code.isEmpty else { return }
    primaryLanguage = code
  }

  /// Sets the app language, sanitized.
  public mutating func setAppLanguage(_ code: String) {
    guard !code.isEmpty else { return }
    appLanguage = LanguageRules.sanitizeAppLanguageSetting(code)
  }
}

/// Language-value repair, ported from `src/locale/helpers.ts`.
public enum LanguageRules {

  /// `sanitizeAppLanguageSetting`: recovers a valid `appLanguage` from an
  /// arbitrary string.
  ///
  /// Background (RN's own comment): a past refactor populated some users'
  /// `appLanguage` from `postLanguage`, which is comma-separated, breaking
  /// `appLanguage` handling. This parses the first recognized value out of the
  /// list and falls back to `en`.
  public static func sanitizeAppLanguageSetting(_ appLanguage: String) -> String {
    let parts = appLanguage.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    for part in parts {
      let fixed = Languages.fixLegacyLanguageCode(part)
      if let match = appLanguageMatch(fixed) { return match }
    }
    return "en"
  }

  /// Maps a stored language string onto an `AppLanguage` code.
  ///
  /// The multi-region cases are RN's: `zh-Hans-CN`, `zh-Hant-TW` and
  /// `zh-Hant-HK` are distinct UI languages, as are the two Portuguese and the
  /// two English variants.
  static func appLanguageMatch(_ code: String) -> String? {
    shippedAppLanguageCodes.contains(code) ? code : nil
  }

  /// The codes `sanitizeAppLanguageSetting` recognizes, matching the
  /// `AppLanguage` enum's cases.
  ///
  /// Held as a set rather than a 41-arm switch: the mapping is identity, so a
  /// switch would only restate the membership, and cyclomatic complexity counted
  /// each arm.
  static let shippedAppLanguageCodes: Set<String> = Set(
    Languages.appLanguages.map(\.code2))

  /// Normalizes a post-language value.
  ///
  /// `Persistence.LanguageNormalization` already ports this (it runs on every
  /// persisted-document write); delegating keeps one implementation rather than
  /// two that could drift.
  public static func normalizePostLanguage(_ value: String) -> String {
    LanguageNormalization.normalizePostLanguage(value)
  }

  /// `twoLetterCode`: reduces a BCP-47 tag to its primary subtag.
  ///
  /// Delegates to `Persistence` for the same reason as above.
  public static func twoLetterCode(_ tag: String) -> String {
    LanguageNormalization.twoLetterCode(tag)
  }
}
