import Foundation
import RichText

/// A value-typed snapshot of rich text: the string plus its facets.
///
/// ``RichText`` is a mutable reference type (it mirrors the TS class, which the
/// editor mutates in place). Composer state needs to be `Sendable` and
/// `Hashable` so it can cross actor boundaries and be compared in tests, so the
/// state machine stores this snapshot instead and rebuilds a ``RichText`` only
/// where the detection and editing APIs are actually needed.
///
/// Facet byte offsets are UTF-8 offsets into ``text``, exactly as in ``RichText``.
public struct RichTextValue: Hashable, Sendable {
  /// The plain text.
  public var text: String
  /// Detected or supplied facets, sorted by `byteStart`.
  public var facets: [Facet]?

  public init(text: String, facets: [Facet]? = nil) {
    self.text = text
    self.facets = facets
  }

  /// Snapshots a ``RichText``, deep-copying its facets.
  public init(_ richText: RichText) {
    self.text = richText.text
    self.facets = richText.facets
  }

  /// An empty value.
  public static let empty = RichTextValue(text: "")

  /// Builds a ``RichText`` from this snapshot, for the detection and editing
  /// APIs.
  public func richText() -> RichText {
    RichText(text: text, facets: facets)
  }

  /// UTF-8 byte length of the text.
  public var byteLength: Int { text.utf8.count }

  /// Grapheme cluster count, which is what the composer's limits are measured in.
  public var graphemeLength: Int { text.count }

  /// The substring starting at a UTF-8 byte offset.
  ///
  /// Mirrors `UnicodeString.slice(_:)`: the offsets are byte offsets, and the
  /// result is decoded back to a `String`.
  public func text(afterByteOffset offset: Int) -> String {
    let bytes = Array(text.utf8)
    guard offset > 0 else { return text }
    guard offset < bytes.count else { return "" }
    guard let decoded = String(bytes: bytes[offset...], encoding: .utf8) else { return "" }
    return decoded
  }

  /// Whether this snapshot carries no facets.
  public var hasFacets: Bool {
    !(facets ?? []).isEmpty
  }

  /// Detects facets locally, leaving mentions unresolved.
  ///
  /// A convenience over constructing a ``RichText`` and calling
  /// ``RichText/detectFacetsWithoutResolution()``, for callers that only have a
  /// snapshot.
  public func detectingFacetsWithoutResolution() -> RichTextValue {
    let richText = richText()
    richText.detectFacetsWithoutResolution()
    return RichTextValue(richText)
  }

  /// The value with links shortened and unresolved mentions dropped, which is
  /// what the publish path and the character counter both measure.
  public func shortenedAndCleaned() -> RichTextValue {
    RichTextValue(stripInvalidMentions(shortenLinks(richText())))
  }
}
