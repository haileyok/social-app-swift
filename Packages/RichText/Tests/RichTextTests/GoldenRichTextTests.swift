import Foundation
import Testing

@testable import RichText

/// The golden fixture emitted by `tools/golden-gen` from `@bsky/sdk@1.1.0`.
///
/// The nested types are flattened rather than nested inside `GoldenDocument` so
/// the fixture's shape stays readable and stays within the repo's one-level
/// nesting lint rule. Decoding goes through the real
/// ``Facet``/``FacetFeature``/``ByteSlice`` types, so the suite also pins the JSON
/// shape the ported model produces.
struct GoldenDocument: Decodable, Sendable {
  let version: Int
  let generator: String
  let cases: [GoldenCase]
}

struct GoldenCase: Decodable, Sendable {
  let name: String
  let input: GoldenInput
  let expected: GoldenExpected
}

struct GoldenInput: Decodable, Sendable {
  let text: String
}

struct GoldenExpected: Decodable, Sendable {
  /// The TS engine's `RichText#length`, which is `UnicodeString#length` - the
  /// UTF-8 byte count, despite the field name. ``unicode`` carries the byte
  /// lengths separately, and the true grapheme count has no golden coverage.
  let graphemeLength: Int
  let facets: [Facet]
  let segments: [GoldenSegment]
  let unicode: GoldenUnicode
}

struct GoldenSegment: Decodable, Sendable {
  let text: String
  let facet: Facet?
}

struct GoldenUnicode: Decodable, Sendable {
  /// NOTE: like ``GoldenExpected/graphemeLength``, this is generated from
  /// `UnicodeString#length`, which is the UTF-8 byte count - so it equals
  /// ``utf8ByteLength`` and is NOT a grapheme count. The engine's real grapheme
  /// count has no golden coverage; it is asserted against `Intl.Segmenter`-verified
  /// values in `UnicodeStringTests`.
  let graphemeLength: Int
  let utf16Length: Int
  let utf8ByteLength: Int
  /// `[utf16Index, utf8Index]` pairs probed at real grapheme boundaries.
  let utf16ToUtf8: [[Int]]
}

/// The fixture, loaded once. A decode failure is surfaced by
/// ``GoldenFixtureTests`` rather than crashing the whole run.
let goldenDocument: GoldenDocument = {
  // #filePath is .../Packages/RichText/Tests/RichTextTests/<this file>, so four
  // parent hops land on Packages/.
  let path =
    URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // RichTextTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // RichText
    .deletingLastPathComponent()  // Packages
    .appending(path: "TestSupport/Fixtures/Golden/richtext.json")
  do {
    return try JSONDecoder().decode(GoldenDocument.self, from: Data(contentsOf: path))
  } catch {
    return GoldenDocument(version: 0, generator: "unreadable at \(path.path): \(error)", cases: [])
  }
}()

@Suite("golden fixture")
struct GoldenFixtureTests {
  @Test("the richtext golden fixture decodes")
  func loadsCases() {
    #expect(
      goldenDocument.cases.count == 15,
      "expected 15 golden cases; loader said: \(goldenDocument.generator)"
    )
  }
}

/// The port must reproduce `@bsky/sdk@1.1.0`'s byte math exactly.
///
/// Every case runs the Swift engine over `input.text` and compares against the
/// recorded TS output: facet byte ranges and features, segment iteration,
/// `RichText#length`, and the `UnicodeString` conversions. Any divergence is a
/// real porting bug - a shifted facet offset, a mis-measured grapheme, or a
/// segment dropped at a boundary.
@Suite("richtext golden parity")
struct GoldenRichTextTests {
  @Test(
    "graphemeLength, detection, segments and unicode match the TS engine",
    arguments: goldenDocument.cases
  )
  func matchesGolden(_ testCase: GoldenCase) throws {
    let text = testCase.input.text
    let expected = testCase.expected

    let richText = RichText(text: text)
    richText.detectFacetsWithoutResolution()

    // Top-level `graphemeLength` is the TS engine's `RichText#length`, i.e. a
    // UTF-8 byte count despite the field name; see GoldenExpected.
    #expect(richText.length == expected.graphemeLength, "\(testCase.name): length")
    #expect(richText.text == text, "\(testCase.name): text round-trip")

    // Facets: byte ranges and feature payloads.
    let facets = try #require(
      richText.facets ?? (expected.facets.isEmpty ? [] : nil),
      "\(testCase.name): facets"
    )
    #expect(facets.count == expected.facets.count, "\(testCase.name): facet count")
    for (actual, want) in zip(facets, expected.facets) {
      #expect(actual.index == want.index, "\(testCase.name): facet index")
      #expect(actual.features == want.features, "\(testCase.name): facet features")
    }

    // Segments: text and attached facet, in order.
    let segments = richText.segments()
    #expect(segments.count == expected.segments.count, "\(testCase.name): segment count")
    for (actual, want) in zip(segments, expected.segments) {
      #expect(actual.text == want.text, "\(testCase.name): segment text")
      #expect(actual.facet == want.facet, "\(testCase.name): segment facet")
    }

    // Lengths and the utf16 -> utf8 probes. Both `graphemeLength` fields in the
    // fixture are `UnicodeString#length`, i.e. UTF-8 byte counts despite the name.
    let unicodeText = UnicodeString(text)
    #expect(unicodeText.length == expected.unicode.graphemeLength, "\(testCase.name): length")
    #expect(unicodeText.utf8.count == expected.unicode.utf8ByteLength, "\(testCase.name): utf8 view")
    #expect(unicodeText.utf16Length == expected.unicode.utf16Length, "\(testCase.name): utf16 units")
    #expect(unicodeText.length == unicodeText.utf8.count, "\(testCase.name): length is utf8 bytes")
    for probe in expected.unicode.utf16ToUtf8 {
      try #require(probe.count == 2, "\(testCase.name): probe shape")
      #expect(
        unicodeText.utf16IndexToUTF8Index(probe[0]) == probe[1],
        "\(testCase.name): utf16IndexToUTF8Index(\(probe[0]))"
      )
    }

    // Segment text must reassemble the whole string: the byte-sliced pieces have
    // to tile the input exactly, with nothing lost at facet boundaries.
    #expect(
      segments.map(\.text).joined() == text,
      "\(testCase.name): segments do not reassemble the input"
    )
  }
}
