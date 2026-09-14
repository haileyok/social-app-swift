import Foundation
import Testing

@testable import RichText

/// Byte-level math for ``UnicodeString``.
///
/// These assertions pin the numbers that matter and are easy to get wrong: that
/// ``UnicodeString/length`` is a UTF-8 byte count rather than a grapheme count,
/// and that ``UnicodeString/graphemeLength`` is the cluster count. Both are
/// needed by different callers - facet offsets use bytes, the composer counter
/// uses graphemes - so a port that conflates them passes visual inspection and
/// then misplaces every facet on an emoji post.
///
/// Expected grapheme counts were verified against `Intl.Segmenter` with
/// `granularity: "grapheme"` (the same segmentation `graphemeLen` in
/// `@atproto/lex` performs) and against the TS engine directly.
@Suite("UnicodeString byte math")
struct UnicodeStringTests {
  @Test(
    "byte, utf16 and grapheme counts",
    arguments: [
      // text, graphemes, utf16 units, utf8 bytes
      ("a", 1, 1, 1),
      ("", 0, 0, 0),
      // A ZWJ family is one grapheme, 11 UTF-16 units, 25 bytes.
      ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", 1, 11, 25),
      // Two regional-indicator pairs: two graphemes, 8 units, 16 bytes.
      ("\u{1F1FA}\u{1F1F8}\u{1F1EF}\u{1F1F8}", 2, 8, 16),
      ("\u{1F1FA}\u{1F1F8}", 1, 4, 8),
      // BMP CJK: one unit per grapheme, three bytes each.
      ("\u{4E2D}\u{6587}\u{6D4B}\u{8BD5}", 4, 4, 12),
      // Combining diacritic fuses into the base grapheme.
      ("cafe\u{301}", 4, 5, 6),
      ("e\u{301}", 1, 2, 3),
      // Skin tone is part of the cluster.
      ("\u{1F44D}\u{1F3FD}", 1, 4, 8),
      // ZWJ + skin tone: still one cluster, 7 units, 15 bytes.
      ("\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}", 1, 7, 15),
    ]
  )
  func counts(
    _ text: String,
    _ graphemes: Int,
    _ utf16Units: Int,
    _ utf8Bytes: Int
  ) {
    let string = UnicodeString(text)
    #expect(string.length == utf8Bytes, "length is the UTF-8 byte count")
    #expect(string.utf8.count == utf8Bytes)
    #expect(string.utf16Length == utf16Units)
    #expect(string.graphemeLength == graphemes)
    #expect(string.toString() == text)
  }

  @Test("length is UTF-8 bytes, not graphemes, for a multi-scalar cluster")
  func lengthIsNotGraphemeCount() {
    // The case that makes the distinction concrete: one visible character, 44 bytes.
    let text = "just \u{1F44D}\u{1F3FD}"
    let string = UnicodeString(text)
    #expect(string.graphemeLength == 6)
    #expect(string.length == 13)
    #expect(string.length != string.graphemeLength)
  }

  /// Expected values are the TS engine's `utf16IndexToUtf8Index` output verbatim.
  ///
  /// Note that these are *not* simply "the byte offset of each grapheme": the
  /// conversion counts UTF-8 bytes over a UTF-16 prefix, so an index landing
  /// inside a surrogate pair encodes that half as U+FFFD and three bytes. That is
  /// why `\u{1F44D}\u{1F3FD} x` maps index 1 to 3 (a lone high surrogate, not
  /// half of the emoji) and index 2 to 4.
  @Test(
    "utf16 index to utf8 index at every cluster boundary",
    arguments: [
      ("a", [0, 1]),
      ("\u{1F44D}\u{1F3FD} x", [0, 3, 4, 7, 8, 9]),
      // BMP CJK at 3 bytes per scalar.
      ("\u{4E2D}\u{6587}\u{6D4B}\u{8BD5}", [0, 3, 6, 9, 12]),
      // Trailing indices clamp to the full length once the cluster is complete.
      ("cafe\u{301}", [0, 1, 2, 3, 4, 6, 6]),
      // ZWJ sequence: each code unit boundary is converted independently.
      ("\u{1F468}\u{200D}\u{1F469}", [0, 3, 4, 7, 10, 11]),
    ]
  )
  func utf16ToUTF8(_ text: String, _ expected: [Int]) {
    let string = UnicodeString(text)
    let actual = (0..<expected.count).map { string.utf16IndexToUTF8Index($0) }
    #expect(actual == expected)
  }

  @Test("utf16 index conversion clamps out-of-range indices")
  func utf16ConversionClamps() {
    let string = UnicodeString("abc")
    #expect(string.utf16IndexToUTF8Index(-5) == 0)
    #expect(string.utf16IndexToUTF8Index(3) == 3)
    #expect(string.utf16IndexToUTF8Index(99) == 3)
  }

  @Test("a prefix ending mid-surrogate encodes as a replacement character")
  func midSurrogatePrefix() {
    // TextEncoder encodes a lone surrogate as U+FFFD, which is 3 bytes (not 4),
    // so a prefix ending mid-pair measures shorter than the byte offset of the
    // following cluster. TS gives [0, 3, 4, 7, 8, 9] for this input.
    let string = UnicodeString("\u{1F44D}\u{1F3FD}!")
    #expect(string.utf16IndexToUTF8Index(0) == 0)
    #expect(string.utf16IndexToUTF8Index(1) == 3)
    #expect(string.utf16IndexToUTF8Index(2) == 4)
    #expect(string.utf16IndexToUTF8Index(3) == 7)
    #expect(string.utf16IndexToUTF8Index(4) == 8)
    #expect(string.utf16IndexToUTF8Index(5) == 9)
  }

  @Test("slice decodes the requested byte range")
  func slice() {
    let string = UnicodeString("a\u{1F44D}\u{1F3FD}b")
    // "a" is 1 byte, the emoji 8 ("\u{1F44D}" = 4, "\u{1F3FD}" = 4), "b" 1.
    #expect(string.slice(0, 1) == "a")
    #expect(string.slice(1, 9) == "\u{1F44D}\u{1F3FD}")
    #expect(string.slice(9, 10) == "b")
    #expect(string.slice(0, 10) == "a\u{1F44D}\u{1F3FD}b")
    #expect(string.slice(1) == "\u{1F44D}\u{1F3FD}b")
  }

  @Test("slice clamps out-of-range bounds")
  func sliceClamps() {
    let string = UnicodeString("abc")
    #expect(string.slice(-2, 2) == "ab")
    #expect(string.slice(1, 99) == "bc")
    #expect(string.slice(5, 2) == "")
    #expect(string.slice(99) == "")
  }

  @Test("a slice splitting a multi-byte scalar decodes as U+FFFD")
  func sliceMidScalar() {
    // TextDecoder is not fatal: a partial scalar becomes U+FFFD rather than
    // throwing, which is what the TS engine's `decoder.decode` does too.
    let string = UnicodeString("\u{1F44D}")
    #expect(string.slice(0, 1) == "\u{FFFD}")
  }

  @Test("graphemeLength equals String.count for every fixture input")
  func graphemesMatchSwift() {
    for testCase in goldenDocument.cases {
      let string = UnicodeString(testCase.input.text)
      #expect(
        string.graphemeLength == testCase.input.text.count,
        "\(testCase.name): grapheme clusters"
      )
    }
  }
}
