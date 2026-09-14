/// The app's grapheme limits, mirroring `src/lib/constants.ts` in the RN app.
///
/// These are *grapheme cluster* counts - what ``RichText/graphemeLength``
/// reports, and what the character counter displays. They are neither UTF-8 byte
/// counts nor UTF-16 code-unit counts.
public enum RichTextLimits {
  /// `MAX_GRAPHEME_LENGTH` - the post limit the composer enforces, measured
  /// after ``shortenLinks(_:)`` has run.
  public static let post = 300

  /// `MAX_DRAFT_GRAPHEME_LENGTH` - the looser limit for text held in drafts.
  public static let draft = 1000

  /// `MAX_DM_GRAPHEME_LENGTH` - direct message length.
  public static let directMessage = 1000

  /// `MAX_DISPLAY_NAME` - list and profile display names.
  public static let displayName = 64

  /// `MAX_DESCRIPTION` - list descriptions.
  public static let description = 256

  /// `MAX_GROUP_NAME_GRAPHEME_LENGTH` - chat group names.
  public static let groupName = 50

  /// `MAX_ALT_TEXT` - image alt text.
  public static let altText = 2000
}

/// Whether `text` exceeds `maxCount` graphemes.
///
/// Ported from `isOverMaxGraphemeCount` in the RN app's
/// `src/lib/strings/helpers.ts`, where a plain string is counted directly. The
/// `RichText` overload counts after link shortening, because shortening is what
/// the character counter and the server ultimately see.
public func isOverMaxGraphemeCount(_ text: String, maxCount: Int) -> Bool {
  text.count > maxCount
}

/// Variant of ``isOverMaxGraphemeCount(_:maxCount:)`` for rich text.
public func isOverMaxGraphemeCount(_ text: RichText, maxCount: Int) -> Bool {
  shortenLinks(text).graphemeLength > maxCount
}
