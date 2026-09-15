import Lexicons
import RichText

/// Projects wire facets into RichText runs.
///
/// `App.Bsky.RichtextFacet` is the lexicon wire shape; `RichText.Facet` is the
/// engine's. They are structurally identical (same byte-slice index, same three
/// feature kinds), so this conversion is explicit rather than relying on a cast:
/// a change in either stays a compile error here instead of a silent mismatch.
enum MessageFacets {
  /// The segment runs a message body renders: the text split at its facet
  /// boundaries, ready for `RichTextBody`.
  ///
  /// Unknown feature kinds are dropped, matching the RN renderer, which ignores
  /// a facet it has no representation for.
  static func segments(text: String, facets: [Lexicons.App.Bsky.RichtextFacet]?) -> [RichTextSegment] {
    RichText(text: text, facets: converted(facets)).segments()
  }

  /// The wire facets, converted to the engine's `Facet`.
  private static func converted(_ facets: [Lexicons.App.Bsky.RichtextFacet]?) -> [Facet]? {
    guard let facets, !facets.isEmpty else { return nil }
    let result = facets.compactMap(facet)
    return result.isEmpty ? nil : result
  }

  /// One wire facet, or `nil` when no feature converts.
  private static func facet(_ wire: Lexicons.App.Bsky.RichtextFacet) -> Facet? {
    let features: [FacetFeature] = wire.features.compactMap { element in
      switch element {
      case .richtextFacetLink(let link): return .link(uri: link.uri.rawValue)
      case .richtextFacetMention(let mention): return .mention(did: mention.did.rawValue)
      case .richtextFacetTag(let tag): return .tag(tag: tag.tag)
      case ._other: return nil
      }
    }
    guard !features.isEmpty else { return nil }
    return Facet(
      index: ByteSlice(byteStart: wire.index.byteStart, byteEnd: wire.index.byteEnd),
      features: features)
  }
}
