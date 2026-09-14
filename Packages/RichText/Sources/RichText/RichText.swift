/// A slice of post text, optionally carrying the facet that applies to it.
///
/// Ported from `RichTextSegment`. The TS engine's convenience accessors are
/// exposed here as ``link``, ``mention`` and ``tag``, reading the first matching
/// feature out of ``facet``.
public struct RichTextSegment: Hashable, Sendable {
  public let text: String
  public let facet: Facet?

  public init(text: String, facet: Facet? = nil) {
    self.text = text
    self.facet = facet
  }

  /// The destination URI, when the facet is a link.
  public var link: String? { facet?.link }

  /// Whether the facet is a link.
  public var isLink: Bool { link != nil }

  /// The resolved (or, without resolution, raw) handle, when the facet is a mention.
  public var mention: String? { facet?.mention }

  /// Whether the facet is a mention.
  public var isMention: Bool { mention != nil }

  /// The tag text, when the facet is a tag.
  public var tag: String? { facet?.tag }

  /// Whether the facet is a tag.
  public var isTag: Bool { tag != nil }
}

/// Text with a facet list, and the machinery to keep the two consistent as the
/// text is edited.
///
/// Ported from `RichText` in `@bsky/sdk/richtext/rich-text.js`.
///
/// ``length`` is the UTF-8 byte length and ``graphemeLength`` the grapheme count;
/// the composer's 300-unit limit uses the latter (see ``RichTextLimits``). Facet
/// `byteStart`/`byteEnd` are UTF-8 byte offsets into ``text``.
public final class RichText {
  /// The text and its index views.
  public internal(set) var unicodeText: UnicodeString

  /// Detected or supplied facets, sorted by `byteStart`.
  public internal(set) var facets: [Facet]?

  /// Builds a `RichText` from text, with optional facets or entities.
  ///
  /// - Parameters:
  ///   - text: the post text.
  ///   - facets: facets to use as-is. Only consulted when `entities` produced
  ///     nothing, matching the original's `if (!this.facets?.length && ...)`.
  ///   - entities: UTF-16-indexed link/mention ranges, converted to facets.
  ///   - cleanNewlines: collapse runs of three or more newlines, as the TS
  ///     constructor does when `opts.cleanNewlines` is set.
  public init(
    text: String,
    facets: [Facet]? = nil,
    entities: [RichTextEntity]? = nil,
    cleanNewlines: Bool = false
  ) {
    self.unicodeText = UnicodeString(text)
    self.facets = facets
    if self.facets?.isEmpty != false, let entities, !entities.isEmpty {
      self.facets = Self.entitiesToFacets(unicodeText, entities: entities)
    }
    if let current = self.facets {
      // Negative-length facets are discarded; zero-length facets are valid.
      self.facets = current.filter { $0.index.byteStart <= $0.index.byteEnd }
        .sorted { $0.index.byteStart < $1.index.byteStart }
    }
    if cleanNewlines {
      sanitize(cleanNewlines: true).copyInto(self)
    }
  }

  /// The post text.
  public var text: String { unicodeText.toString() }

  /// UTF-8 byte length of the text.
  public var length: Int { unicodeText.length }

  /// Grapheme cluster count of the text.
  public var graphemeLength: Int { unicodeText.graphemeLength }

  /// A copy of this value, with facets deep-copied.
  public func clone() -> RichText {
    RichText(text: unicodeText.utf16, facets: facets)
  }

  /// Replaces `target`'s text and facets with this value's.
  ///
  /// Ported from `copyInto`; the TS version also mutates the source, so the
  /// in-place variant is kept for that use.
  public func copyInto(_ target: RichText) {
    target.unicodeText = unicodeText
    target.facets = facets
  }

  /// Iterates the text as alternating plain and faceted runs.
  ///
  /// Ported from `RichText#segments`. Facets are assumed sorted by `byteStart`,
  /// which the initializer and ``detectFacetsWithoutResolution()`` guarantee.
  /// Two behaviours are easy to miss:
  ///
  /// - A facet whose range is empty is skipped entirely (`byteStart < byteEnd`),
  ///   but text between facets is still emitted.
  /// - A facet covering only whitespace yields a segment with a `nil` facet, so
  ///   that trailing empty entities render as plain text.
  public func segments() -> [RichTextSegment] {
    guard let facets, !facets.isEmpty else {
      return [RichTextSegment(text: unicodeText.utf16)]
    }

    var result: [RichTextSegment] = []
    var textCursor = 0
    var facetCursor = 0
    repeat {
      let current = facets[facetCursor]
      if textCursor < current.index.byteStart {
        result.append(
          RichTextSegment(text: unicodeText.slice(textCursor, current.index.byteStart))
        )
      } else if textCursor > current.index.byteStart {
        // This facet starts before a facet already emitted; skip it.
        facetCursor += 1
        continue
      }
      if current.index.byteStart < current.index.byteEnd {
        let subtext = unicodeText.slice(current.index.byteStart, current.index.byteEnd)
        if subtext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          result.append(RichTextSegment(text: subtext))
        } else {
          result.append(RichTextSegment(text: subtext, facet: current))
        }
      }
      textCursor = current.index.byteEnd
      facetCursor += 1
    } while facetCursor < facets.count

    if textCursor < unicodeText.length {
      result.append(RichTextSegment(text: unicodeText.slice(textCursor, unicodeText.length)))
    }
    return result
  }

  /// Inserts `insertText` at `insertIndex`, shifting facets as needed.
  ///
  /// Ported from `RichText#insert`. `insertText` is measured in UTF-8 bytes for
  /// the shift, since facet indices are byte offsets.
  @discardableResult
  public func insert(_ insertIndex: Int, _ insertText: String) -> RichText {
    unicodeText = UnicodeString(
      unicodeText.slice(0, insertIndex) + insertText + unicodeText.slice(insertIndex)
    )
    guard var current = facets, !current.isEmpty else { return self }
    let added = insertText.utf8.count
    for i in current.indices {
      if insertIndex <= current[i].index.byteStart {
        // A: before - move both.
        current[i].index.byteStart += added
        current[i].index.byteEnd += added
      } else if insertIndex >= current[i].index.byteStart && insertIndex < current[i].index.byteEnd {
        // B: inner - move the end.
        current[i].index.byteEnd += added
      }
      // C: after - noop.
    }
    facets = current
    return self
  }

  /// Deletes the byte range `removeStartIndex..<removeEndIndex`, shifting facets
  /// as needed, and drops any facet left empty.
  ///
  /// Ported from `RichText#delete`.
  @discardableResult
  public func delete(_ removeStartIndex: Int, _ removeEndIndex: Int) -> RichText {
    unicodeText = UnicodeString(
      unicodeText.slice(0, removeStartIndex) + unicodeText.slice(removeEndIndex)
    )
    guard var current = facets, !current.isEmpty else { return self }
    let removed = removeEndIndex - removeStartIndex
    for i in current.indices {
      if removeStartIndex <= current[i].index.byteStart
        && removeEndIndex >= current[i].index.byteEnd {
        // A: entirely outer - delete.
        current[i].index.byteStart = 0
        current[i].index.byteEnd = 0
      } else if removeStartIndex > current[i].index.byteEnd {
        // B: entirely after - noop.
        continue
      } else if removeStartIndex > current[i].index.byteStart
        && removeStartIndex <= current[i].index.byteEnd
        && removeEndIndex > current[i].index.byteEnd {
        // C: partially after - move the end to the removal start.
        current[i].index.byteEnd = removeStartIndex
      } else if removeStartIndex >= current[i].index.byteStart
        && removeEndIndex <= current[i].index.byteEnd {
        // D: entirely inner - move the end in by the removed length.
        current[i].index.byteEnd -= removed
      } else if removeStartIndex < current[i].index.byteStart
        && removeEndIndex >= current[i].index.byteStart
        && removeEndIndex <= current[i].index.byteEnd {
        // E: partially before - move the start to the removal start.
        current[i].index.byteStart = removeStartIndex
        current[i].index.byteEnd -= removed
      } else if removeEndIndex < current[i].index.byteStart {
        // F: entirely before - move both.
        current[i].index.byteStart -= removed
        current[i].index.byteEnd -= removed
      }
    }
    // Facets that ended up empty are no longer relevant.
    facets = current.filter { $0.index.byteStart < $0.index.byteEnd }
    return self
  }

  /// Detects facets locally, overwriting any existing ones.
  ///
  /// Ported from `detectFacetsWithoutResolution`. Mentions are left with the raw
  /// matched handle in `did` rather than a resolved DID, so the result is only
  /// valid once every mention has been resolved or stripped - see
  /// ``stripInvalidMentions(_:)``.
  public func detectFacetsWithoutResolution() {
    facets = detectFacets(unicodeText)
    if facets != nil {
      facets?.sort { $0.index.byteStart < $1.index.byteStart }
    }
  }

  /// Converts UTF-16-indexed link/mention entities into facets.
  private static func entitiesToFacets(
    _ text: UnicodeString,
    entities: [RichTextEntity]
  ) -> [Facet] {
    entities.map { entity in
      let feature: FacetFeature =
        switch entity.type {
        case .link: .link(uri: entity.value)
        case .mention: .mention(did: entity.value)
        }
      return Facet(
        byteStart: text.utf16IndexToUTF8Index(entity.start),
        byteEnd: text.utf16IndexToUTF8Index(entity.end),
        feature: feature
      )
    }
  }
}
