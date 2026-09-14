/// Post-processing on detected rich text, ported from the RN app's
/// `src/lib/strings/rich-text-manip.ts`.
///
/// Both functions operate on a copy and return it, matching the originals'
/// `rt = rt.clone()`.
extension RichText {
  /// Replaces each link facet's text with ``toShortUrl(_:)`` of its URI, keeping
  /// the facet covering the shortened text.
  ///
  /// Ported from `shortenLinks`. Facets that sit inside a link being shortened
  /// have their offsets fixed up by the surrounding insert and delete, which is
  /// the point of going through ``RichText/insert(_:_:)`` and
  /// ``RichText/delete(_:_:)`` rather than rebuilding the string.
  public func shortenLinks() -> RichText {
    guard let facets, !facets.isEmpty else { return self }
    let result = clone()

    // Facet offsets must be re-read on every iteration, because each insert and
    // delete shifts the facets that follow. The original iterates its live facet
    // array and does not compensate when a delete removes the facet it is
    // standing on, so the cursor here advances the same way.
    var cursor = 0
    while cursor < (result.facets?.count ?? 0) {
      guard let facet = result.facets?[cursor] else { break }
      guard facet.link != nil else {
        cursor += 1
        continue
      }

      let byteStart = facet.index.byteStart
      let byteEnd = facet.index.byteEnd
      let url = result.unicodeText.slice(byteStart, byteEnd)
      let shortened = UnicodeString(toShortUrl(url))

      // Insert the shortened URL. This shifts every facet at or after
      // `byteStart` by the inserted length, including this one.
      result.insert(byteStart, shortened.utf16)
      // Pin this facet back over the shortened text before deleting the original.
      // This is load-bearing: without it the link facet spans exactly the delete
      // range, which delete would treat as "entirely outer" and drop.
      result.facets?[cursor].index.byteStart = byteStart
      result.facets?[cursor].index.byteEnd = byteStart + shortened.length
      // Remove the original URL that now follows the shortened one.
      result.delete(byteStart + shortened.length, byteEnd + shortened.length)
      cursor += 1
    }
    return result
  }

  /// Drops mention facets that were never resolved to a DID.
  ///
  /// Ported from `stripInvalidMentions`. Facets with no mention feature are kept;
  /// an empty `did` means the resolver did not find the handle.
  public func stripInvalidMentions() -> RichText {
    guard let facets, !facets.isEmpty else { return self }
    let result = clone()
    result.facets = result.facets?.filter { facet in
      guard let did = facet.mention else { return true }
      return !did.isEmpty
    }
    return result
  }
}

/// `shortenLinks(rt)` in free-function form, for call sites that read better that way.
public func shortenLinks(_ richText: RichText) -> RichText {
  richText.shortenLinks()
}

/// `stripInvalidMentions(rt)` in free-function form.
public func stripInvalidMentions(_ richText: RichText) -> RichText {
  richText.stripInvalidMentions()
}
