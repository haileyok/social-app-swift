import Foundation

/// A string carrying both its UTF-16 and UTF-8 views, with index math between them.
///
/// Ported from `UnicodeString` in `@bsky/sdk/richtext` (`unicode.js`). The name and
/// the many "utf8"/"utf16" members are kept because the type exists for exactly one
/// reason: JavaScript strings are UTF-16 code-unit sequences, but AT Protocol
/// richtext facets address **UTF-8 bytes**. Every index conversion in the engine
/// goes through here, so the semantics are reproduced exactly rather than
/// "improved" into Swift-native grapheme indices.
///
/// Two details are easy to get wrong when porting:
///
/// - ``length`` is the **UTF-8 byte count**, not a character or grapheme count.
///   The TS engine's `UnicodeString.length` is `utf8.byteLength`. Grapheme
///   clusters are exposed separately as ``graphemeLength``.
/// - ``utf16IndexToUTF8Index(_:)`` counts UTF-8 bytes over the prefix measured in
///   **UTF-16 code units**, and an index that lands between the halves of a
///   surrogate pair encodes as a single replacement character (3 bytes), matching
///   what `TextEncoder` produces for a lone surrogate.
///
/// All offsets are unvalidated, matching the original: out-of-range values are
/// clamped rather than trapping, since the engine routinely probes the exact end
/// of the string.
public struct UnicodeString: Hashable, Sendable {
  /// The source text, named for the TS field whose strings are UTF-16 code-unit
  /// sequences. Swift's `String` is not UTF-16-backed in its API, but
  /// `String.UTF16View` gives the code-unit view the index math needs.
  public let utf16: String

  /// The UTF-8 encoding of ``utf16``.
  public let utf8: [UInt8]

  public init(_ utf16: String) {
    self.utf16 = utf16
    self.utf8 = Array(utf16.utf8)
  }

  /// UTF-8 byte length.
  ///
  /// This is `UnicodeString#length` in the TS engine - NOT a grapheme count.
  /// Facet `byteStart`/`byteEnd` values index into this space.
  public var length: Int { utf8.count }

  /// Grapheme cluster count, the number the composer enforces limits against.
  ///
  /// Mirrors `UnicodeString#graphemeLength`. Swift's `String` is grapheme-based,
  /// so this is simply `count`.
  public var graphemeLength: Int { utf16.count }

  /// The UTF-16 code-unit count, i.e. JavaScript's `String#length`.
  public var utf16Length: Int { utf16.utf16.count }

  /// Decodes the UTF-8 byte range `start..<end`.
  ///
  /// Slices are start-inclusive, end-exclusive. Bounds are clamped, and a range
  /// that would split a multi-byte scalar decodes that scalar as U+FFFD - both
  /// matching `TextDecoder`, which is not fatal by default.
  public func slice(_ start: Int, _ end: Int) -> String {
    let lower = min(max(start, 0), utf8.count)
    let upper = min(max(end, lower), utf8.count)
    // `String(decoding:)` is deliberate: it is the non-failing decoder, replacing
    // invalid sequences with U+FFFD, which is what TextDecoder does. The
    // failable `String(bytes:encoding:)` would return nil here instead.
    // swiftlint:disable:next optional_data_string_conversion
    return String(decoding: utf8[lower..<upper], as: UTF8.self)
  }

  /// Decodes the UTF-8 bytes from `start` to the end of the string.
  public func slice(_ start: Int) -> String {
    slice(start, utf8.count)
  }

  /// Converts a UTF-16 code-unit index into a UTF-8 byte index.
  ///
  /// Equivalent to `TextEncoder.encode(utf16.slice(0, i)).byteLength`. Because JS
  /// `slice` clamps, indices past the end measure the whole string. A prefix that
  /// ends mid-surrogate-pair encodes that half as U+FFFD, exactly as
  /// `TextEncoder` does.
  public func utf16IndexToUTF8Index(_ index: Int) -> Int {
    let clamped = min(max(index, 0), utf16Length)
    return String(decoding: utf16.utf16.prefix(clamped), as: UTF16.self).utf8.count
  }

  /// The source text, mirroring `UnicodeString#toString`.
  public func toString() -> String { utf16 }
}
