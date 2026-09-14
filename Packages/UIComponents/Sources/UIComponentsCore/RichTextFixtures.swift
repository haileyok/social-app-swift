import Foundation
import Moderation
import RichText

/// Fixture builders for the engine's byte-indexed facet types.
///
/// ``RichTextFacet`` and ``ByteIndex`` are `Codable` but have no public
/// memberwise initializer (the engine only decodes them), so fixtures build them
/// through the real decode path. The same approach as ``EmbedFixtures``.
public enum RichTextFixtures {
  /// A facet covering `[byteStart, byteEnd)` with one feature.
  public static func facet(
    byteStart: Int,
    byteEnd: Int,
    featureType: String,
    tag: String? = nil
  ) -> RichTextFacet? {
    let tagField = tag.map { #", "tag": "\#(EmbedFixtures.escape($0))""# } ?? ""
    let json = """
      {
        "index": {"byteStart": \(byteStart), "byteEnd": \(byteEnd)},
        "features": [{"$type": "\(featureType)"\(tagField)}]
      }
      """
    return try? JSONDecoder().decode(RichTextFacet.self, from: Data(json.utf8))
  }

  /// A tag facet, the only feature the engine's stand-in type can carry.
  public static func tag(_ value: String, byteStart: Int, byteEnd: Int) -> RichTextFacet? {
    facet(byteStart: byteStart, byteEnd: byteEnd, featureType: FacetType.tag, tag: value)
  }
}
