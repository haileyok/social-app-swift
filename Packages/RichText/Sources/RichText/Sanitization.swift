import Foundation

/// Collapses runs of three or more line breaks into a single blank line.
///
/// Ported from `sanitizeRichText` (`@bsky/sdk/richtext/sanitization.js`). The
/// original's only option is `cleanNewlines`, and it returns the `RichText` it
/// was handed, so this returns `self` to allow chaining.
///
/// The loop is written the same way the original is, including its early exit:
/// each pass re-runs the regex against the newly shortened text, and stops as
/// soon as a delete fails to change the text.
@discardableResult
public func sanitizeRichText(_ richText: RichText, cleanNewlines: Bool = false) -> RichText {
  guard cleanNewlines else { return richText }
  return clean(richText, RichTextRegex.excessSpace, "\n\n")
}

private func clean(
  _ richText: RichText,
  _ target: NSRegularExpression,
  _ replacement: String
) -> RichText {
  let clone = richText.clone()
  var match = firstMatch(target, in: clone)
  while let current = match {
    let previousText = clone.unicodeText
    let removeStart = clone.unicodeText.utf16IndexToUTF8Index(current.range.location)
    let removeEnd = removeStart + UnicodeString(current.matched).length
    clone.delete(removeStart, removeEnd)
    if clone.unicodeText.utf16 == previousText.utf16 {
      // Sanity check: no progress, so the loop would not terminate.
      break
    }
    clone.insert(removeStart, replacement)
    match = firstMatch(target, in: clone)
  }
  return clone
}

private func firstMatch(
  _ target: NSRegularExpression,
  in richText: RichText
) -> (range: NSRange, matched: String)? {
  let string = richText.unicodeText.utf16 as NSString
  guard let match = target.firstMatch(in: string as String, range: NSRange(0..<string.length))
  else { return nil }
  return (match.range, string.substring(with: match.range))
}

extension RichText {
  /// In-place variant of ``sanitizeRichText(_:cleanNewlines:)``.
  @discardableResult
  public func sanitize(cleanNewlines: Bool = false) -> RichText {
    sanitizeRichText(self, cleanNewlines: cleanNewlines)
  }
}
