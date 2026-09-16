import Foundation

/// Regexes shared by facet detection, ported from `@bsky/sdk/richtext/util.js`.
///
/// Every pattern except ``url`` and ``linkable`` is used verbatim: JavaScript's
/// RegExp is specified against the same Unicode/ICU semantics that
/// `NSRegularExpression` implements, so the two engines agree on these patterns.
/// The two exceptions differ only in the spelling of a named group - see ``url``.
///
/// All patterns work in UTF-16 code-unit offsets, which is both what
/// `NSRegularExpression` reports and what the TS engine's `match.index` gives.
enum RichTextRegex {
  /// `(^|\s|\()(@)([a-zA-Z0-9.-]+)(\b)` - mentions.
  ///
  /// Capture 3 is the handle; capture 1 is the leading separator the match
  /// absorbed, which is why the facet start is derived from group 1 rather than
  /// the match start.
  static let mention: NSRegularExpression = regex(
    "(^|\\s|\\()(@)([a-zA-Z0-9.-]+)(\\b)"
  )

  /// The URL pattern, matching the TS original except for the spelling of one
  /// construct.
  ///
  /// The original is:
  ///
  /// ```js
  /// /(^|\s|\()((https?:\/\/[\S]+)|((?<domain>[a-z][a-z0-9]*(\.[a-z0-9]+)+)[\S]*))/gim
  /// ```
  ///
  /// Group numbering is preserved exactly (2 = the whole candidate, 3 = the
  /// schemeless alternative, 4/5 = the domain inside it), because detection reads
  /// group 2 positionally and the domain by name.
  ///
  /// The one deliberate change is `(\.[a-z0-9]+)+` inside the named `domain`
  /// group becoming `(?:\.[a-z0-9]+)+`. ICU rejects a quantifier around a
  /// *capturing* group inside a named group, and the original nests exactly that,
  /// so the pattern as written is a hard `NSRegularExpression` error. The inner
  /// group's capture is never read - only the outer `domain` group is - so making
  /// it non-capturing is invisible to every consumer, and all group numbers used
  /// by detection (1, 2, 3) are unchanged.
  static let url: NSRegularExpression = regex(
    "(^|\\s|\\()((https?://\\S+)|((?<domain>[a-z][a-z0-9]*(?:\\.[a-z0-9]+)+)\\S*))",
    options: [.caseInsensitive, .anchorsMatchLines]
  )

  /// `\p{P}+$` - trailing punctuation, stripped from hashtags.
  static let trailingPunctuation: NSRegularExpression = regex("\\p{P}+$")

  /// `(^|\s)[#＃](...)?` - hashtags, full-width `#` included.
  ///
  /// The negative lookahead and the zero-width character classes are verbatim
  /// from the original. Note its "modifier" character class is shaped like a
  /// character class but is used as a negative lookahead, so it consumes nothing
  /// and its contents are inert - reproduced as-is.
  static let tag: NSRegularExpression = regex(
    "(^|\\s)[#\u{FF03}]"
      + "((?!\u{FE0F})"
      + "[^\\s\u{00AD}\u{2060}\u{200A}\u{200B}\u{200C}\u{200D}\u{20E2}]*"
      + "[^\\d\\s\\p{P}\u{00AD}\u{2060}\u{200A}\u{200B}\u{200C}\u{200D}\u{20E2}]+"
      + "[^\\s\u{00AD}\u{2060}\u{200A}\u{200B}\u{200C}\u{200D}\u{20E2}]*)?"
  )

  /// `(^|\s|\()\$([A-Za-z][A-Za-z0-9]{0,4})(?=\s|$|[.,;:!?)"'\u{2019}])` - cashtags.
  static let cashtag: NSRegularExpression = regex(
    "(^|\\s|\\()\\$([A-Za-z][A-Za-z0-9]{0,4})(?=\\s|$|[.,;:!?)\"'\u{2019}])"
  )

  /// The RN app's looser pattern for ``detectLinkables``, which unifies mentions,
  /// URLs and bare domains into a single scan.
  ///
  /// The original is:
  ///
  /// ```js
  /// /((^|\s|\()@[a-z0-9.-]*)|((^|\s|\()https?:\/\/[\S]+)|((^|\s|\()(?<domain>[a-z][a-z0-9]*(\.[a-z0-9]+)+)[\S]*)/gi
  /// ```
  ///
  /// Same non-capturing-group substitution as ``url``; the group numbers the
  /// consumer reads (`domain`) are unaffected.
  static let linkable: NSRegularExpression = regex(
    "((^|\\s|\\()@[a-z0-9.-]*)"
      + "|((^|\\s|\\()https?://\\S+)"
      + "|((^|\\s|\\()(?<domain>[a-z][a-z0-9]*(?:\\.[a-z0-9]+)+)\\S*)",
    options: [.caseInsensitive]
  )

  /// `[\r\n]([\u00AD\u2060\u200D\u200C\u200B\s]*[\r\n]){2,}` - three or more line
  /// breaks separated only by whitespace/zero-width characters.
  static let excessSpace: NSRegularExpression = regex(
    "[\\r\\n]([\u{00AD}\u{2060}\u{200D}\u{200C}\u{200B}\\s]*[\\r\\n]){2,}"
  )

  private static func regex(
    _ pattern: String,
    options: NSRegularExpression.Options = []
  ) -> NSRegularExpression {
    // Patterns are compile-time constants; a failure is a programming error.
    // swiftlint:disable:next force_try
    try! NSRegularExpression(pattern: pattern, options: options)
  }
}

extension NSTextCheckingResult {
  /// The substring captured by `group`, or `nil` when it did not participate.
  func group(_ group: Int, in string: NSString) -> String? {
    let range = range(at: group)
    guard range.location != NSNotFound else { return nil }
    return string.substring(with: range)
  }

  /// The substring captured by a named group, or `nil` when it did not participate.
  func namedGroup(_ name: String, in string: NSString) -> String? {
    let range = range(withName: name)
    guard range.location != NSNotFound else { return nil }
    return string.substring(with: range)
  }
}

/// Detects facets in `text` without resolving mentions to DIDs.
///
/// Ported from `detectFacets` (`@bsky/sdk/richtext/detection.js`). Detection runs
/// four independent scans - mentions, links, hashtags, cashtags - and returns
/// everything they find without resolving overlaps: a later scan's facet may sit
/// on top of an earlier one. ``RichText`` sorts by `byteStart` and ``RichText``'s
/// segment iteration skips past whichever of two overlapping facets ends first.
///
/// Returns `nil` rather than an empty array when nothing matched, matching the
/// original's `facets.length > 0 ? facets : undefined`.
public func detectFacets(_ text: UnicodeString) -> [Facet]? {
  let string = text.utf16 as NSString
  var facets: [Facet] = []

  detectMentions(string, text, &facets)
  detectLinks(string, text, &facets)
  detectTags(string, text, &facets)
  detectCashtags(string, text, &facets)

  return facets.isEmpty ? nil : facets
}

/// Every match of `regex` over the whole of `string`.
private func matches(_ regex: NSRegularExpression, in string: NSString) -> [NSTextCheckingResult] {
  regex.matches(in: string as String, range: NSRange(0..<string.length))
}

/// UTF-8 byte index for a UTF-16 offset, or `nil` when the offset is out of range.
///
/// The TS engine derives these offsets by slicing with `String#slice`, which
/// clamps; the guard reproduces the effect of that invariant (a matched range's
/// end is always in range) rather than converting a nonsense offset into a
/// nonsense facet.
private func byteIndex(_ text: UnicodeString, _ utf16Index: Int) -> Int? {
  guard utf16Index >= 0, utf16Index <= text.utf16Length else { return nil }
  return text.utf16IndexToUTF8Index(utf16Index)
}

private func detectMentions(_ string: NSString, _ text: UnicodeString, _ facets: inout [Facet]) {
  for match in matches(RichTextRegex.mention, in: string) {
    guard let handle = match.group(3, in: string) else { continue }
    // Anything outside the TLD list is probably not a handle; ".test" is
    // accepted explicitly for development and tests.
    let normalizedHandle = handle.lowercased()
    guard isValidDomain(normalizedHandle) || normalizedHandle.hasSuffix(".test") else { continue }
    let leading = match.group(1, in: string) ?? ""
    // The match absorbs the separator before the "@", so the facet starts at the
    // "@" itself: match start + separator length. (The original re-finds the
    // handle with `indexOf` and subtracts 1, which lands on the same offset.)
    let start = match.range.location + (leading as NSString).length
    guard let byteStart = byteIndex(text, start),
      // +1 for the "@".
      let byteEnd = byteIndex(text, start + (handle as NSString).length + 1)
    else { continue }
    facets.append(Facet(byteStart: byteStart, byteEnd: byteEnd, feature: .mention(did: handle)))
  }
}

private func detectLinks(_ string: NSString, _ text: UnicodeString, _ facets: inout [Facet]) {
  for match in matches(RichTextRegex.url, in: string) {
    guard let candidate = match.group(2, in: string) else { continue }
    var uri = candidate
    if !uri.hasPrefix("http") {
      guard let domain = match.namedGroup("domain", in: string), isValidDomain(domain) else {
        continue
      }
      uri = "https://" + uri
    }
    let start = match.range.location + match.range(at: 1).length
    var end = start + (candidate as NSString).length
    // A sentence-ending character, then an unbalanced ")".
    if let last = uri.last, ".,;:!?".contains(last) {
      uri.removeLast()
      end -= 1
    }
    if uri.hasSuffix(")") && !uri.contains("(") {
      uri.removeLast()
      end -= 1
    }
    guard let byteStart = byteIndex(text, start), let byteEnd = byteIndex(text, end) else {
      continue
    }
    facets.append(Facet(byteStart: byteStart, byteEnd: byteEnd, feature: .link(uri: uri)))
  }
}

private func detectTags(_ string: NSString, _ text: UnicodeString, _ facets: inout [Facet]) {
  for match in matches(RichTextRegex.tag, in: string) {
    guard let raw = match.group(2, in: string) else { continue }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let tag = RichTextRegex.trailingPunctuation.stringByReplacingMatches(
      in: trimmed,
      range: NSRange(0..<(trimmed as NSString).length),
      withTemplate: ""
    )
    // A tag's UTF-16 length is always >= its grapheme count, so only pay for the
    // grapheme count when the UTF-16 length already exceeds the limit.
    // (upstream atproto#2657)
    if tag.isEmpty || (tag.utf16.count > 64 && tag.count > 64) { continue }
    let leading = match.group(1, in: string) ?? ""
    let start = match.range.location + (leading as NSString).length
    guard let byteStart = byteIndex(text, start),
      // +1 for the leading "#".
      let byteEnd = byteIndex(text, start + 1 + (tag as NSString).length)
    else { continue }
    facets.append(Facet(byteStart: byteStart, byteEnd: byteEnd, feature: .tag(tag: tag)))
  }
}

private func detectCashtags(_ string: NSString, _ text: UnicodeString, _ facets: inout [Facet]) {
  for match in matches(RichTextRegex.cashtag, in: string) {
    guard let raw = match.group(2, in: string), !raw.isEmpty else { continue }
    let ticker = raw.uppercased()
    let leading = match.group(1, in: string) ?? ""
    let start = match.range.location + (leading as NSString).length
    guard let byteStart = byteIndex(text, start),
      // +1 for the leading "$".
      let byteEnd = byteIndex(text, start + 1 + (ticker as NSString).length)
    else { continue }
    // Cashtags are stored as tags with the "$" retained.
    facets.append(Facet(byteStart: byteStart, byteEnd: byteEnd, feature: .tag(tag: "$" + ticker)))
  }
}
