import Foundation
import RichText

/// Text-level helpers the composer derives from rich text.
///
/// The RN app inlines these as `getShortenedLength` (in `state/composer.ts`)
/// and the `resolveRT` step in `lib/api/index.ts`. They are gathered here
/// because both the character counter and the publish path need the same
/// answer.
public enum ComposerText {
  /// The grapheme length of `richText` after link shortening.
  ///
  /// Ported from `getShortenedLength`, which is
  /// `shortenLinks(rt).graphemeLength`. Both the 300-grapheme counter and the
  /// publish-time limit check use this, not the raw length: a long URL counts
  /// as its shortened form.
  public static func shortenedGraphemeLength(_ richText: RichTextValue) -> Int {
    richText.shortenedAndCleaned().graphemeLength
  }

  /// The text as it will be published.
  ///
  /// Ported from `resolveRT`'s text handling in `lib/api/index.ts`: leading
  /// whitespace-only lines are stripped (without breaking ASCII art, hence the
  /// `\s*\n` rather than a plain trim), and trailing whitespace is removed.
  public static func publishText(_ text: String) -> String {
    var result = text
    if let range = result.range(of: #"^(\s*\n)+"#, options: .regularExpression) {
      result.removeSubrange(range)
    }
    return trimmingTrailingWhitespace(result)
  }

  /// Removes trailing whitespace, matching JS `String.prototype.trimEnd`.
  static func trimmingTrailingWhitespace(_ text: String) -> String {
    var end = text.endIndex
    while end > text.startIndex {
      let previous = text.index(before: end)
      guard text[previous].isWhitespace else { break }
      end = previous
    }
    return String(text[text.startIndex..<end])
  }

  /// Builds the rich text that will actually be published.
  ///
  /// Ported from `resolveRT`: the publish-time text is re-derived from the
  /// trimmed text with `cleanNewlines`, facets are (re)detected, links are
  /// shortened, and unresolved mentions are stripped. The publish path owns
  /// mention resolution; see ``ComposerRecordBuilder``.
  public static func publishRichText(
    _ richText: RichTextValue,
    resolvedMentions: [String: String] = [:]
  ) -> RichText {
    let text = publishText(richText.text)
    let result = RichText(text: text, cleanNewlines: true)
    result.detectFacetsWithoutResolution()
    let resolvedFacets = result.facets?.map { facet in
      var resolved = facet
      resolved.features = facet.features.map { feature in
        guard case .mention(let handle) = feature else { return feature }
        return resolvedMentions[handle.lowercased()].map { .mention(did: $0) } ?? feature
      }
      return resolved
    }
    let resolved = RichText(text: result.text, facets: resolvedFacets)
    return stripInvalidMentions(shortenLinks(resolved))
  }
}
