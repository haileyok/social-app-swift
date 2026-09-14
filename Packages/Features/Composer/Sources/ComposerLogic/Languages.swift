import Foundation

/// A language a post can be tagged with.
///
/// The RN app passes bare BCP-47 strings around and slices them to three at
/// publish time; this wrapper keeps the cap and the "auto" concept in one place
/// while still writing plain strings into the record.
public struct PostLanguage: Hashable, Sendable {
  /// The BCP-47 tag, e.g. `en` or `pt-BR`.
  public var code: String

  public init(_ code: String) {
    self.code = code
  }

  /// Whether the code looks like a BCP-47 tag (`xx` with optional subtags).
  ///
  /// Deliberately loose: the RN app accepts whatever its language picker
  /// produces and lets the server validate. The check exists so a user-typed
  /// value cannot inject an empty or whitespace-only tag.
  public var isPlausible: Bool {
    let pattern = #"^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$"#
    return code.range(of: pattern, options: .regularExpression) != nil
  }
}

/// How the post's language list is being chosen.
///
/// Ported from the interaction between the language picker and the
/// language-suggestion nudge (`select-language/*.tsx`): the user's preference
/// supplies a default set, and detection may propose one more.
public enum LanguageSelectionMode: String, Hashable, Sendable, CaseIterable {
  /// The list comes from the user's post-language preference.
  case automatic
  /// The user has edited the list by hand.
  case manual
}

/// The post-language list, with the cap and the auto/manual distinction.
///
/// The RN composer stores the language list as a comma-joined string in
/// preferences and re-splits it with `toPostLanguages`/`fromPostLanguages`. The
/// cap is applied at publish (`langs.slice(0, 3)` in `lib/api/index.ts`); this
/// type applies it on every mutation instead, so `languages` is always what will
/// be written.
public struct LanguageSelection: Hashable, Sendable {
  /// The number of languages that will be written to the record.
  public static let maxLanguages = ComposerConstants.maxLanguages

  /// The selected languages, capped at ``maxLanguages``.
  public private(set) var languages: [PostLanguage]
  /// Whether the user has overridden the automatic list.
  public private(set) var mode: LanguageSelectionMode

  /// Builds a selection from the user's preference string (`"en,pt-BR"`).
  ///
  /// Ported from `toPostLanguages`, which splits on commas; empty entries are
  /// dropped here rather than producing an empty language.
  public init(preferenceString: String) {
    let codes = preferenceString
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    self.languages = codes.prefix(Self.maxLanguages).map(PostLanguage.init)
    self.mode = .automatic
  }

  /// Builds a selection from an explicit list, as the reply flow does when it
  /// adopts the languages of the post being replied to.
  public init(languages: [String], mode: LanguageSelectionMode = .manual) {
    self.languages = languages.prefix(Self.maxLanguages).map(PostLanguage.init)
    self.mode = mode
  }

  /// The codes that will be written to the record.
  public var codes: [String] { languages.map(\.code) }

  /// Whether the selection is empty (which the publish path treats as
  /// "no langs field").
  public var isEmpty: Bool { languages.isEmpty }

  /// Whether `code` is already selected.
  public func contains(_ code: String) -> Bool {
    languages.contains { $0.code == code }
  }

  /// Replaces the list wholesale, marking the selection manual.
  ///
  /// Mirrors `onSelectLanguages` in `PostLanguageSelect.tsx`, including its
  /// fallback: an empty list falls back to the user's primary language.
  public mutating func set(_ codes: [String], fallback: String? = nil) {
    var next = codes.filter { !$0.isEmpty }
    if next.isEmpty, let fallback, !fallback.isEmpty {
      next = [fallback]
    }
    languages = next.prefix(Self.maxLanguages).map(PostLanguage.init)
    mode = .manual
  }

  /// Appends a language if it is not present and there is room.
  ///
  /// The RN picker refuses to add a fourth language; this returns whether it
  /// was added so the caller can surface that.
  @discardableResult
  public mutating func add(_ code: String) -> Bool {
    guard !contains(code), languages.count < Self.maxLanguages else { return false }
    languages.append(PostLanguage(code))
    mode = .manual
    return true
  }

  /// Removes a language.
  public mutating func remove(_ code: String) {
    languages.removeAll { $0.code == code }
    mode = .manual
  }

  /// Adopts a reply target's languages, unless the user has already chosen.
  ///
  /// Ported from the reply-language adoption in `SuggestedLanguage.tsx`: the
  /// prompt is only offered when the composer's languages do not already
  /// include the target's, and accepting it replaces the list.
  public mutating func adopt(languagesOfReplyTarget codes: [String]) {
    let next = codes.filter { !contains($0) }
    guard !next.isEmpty else { return }
    set(next)
  }
}
