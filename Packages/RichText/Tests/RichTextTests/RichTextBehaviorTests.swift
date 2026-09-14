import Foundation
import Testing

@testable import RichText

/// `segments()` iteration and the insert/delete offset bookkeeping that
/// `sanitizeRichText` and `shortenLinks` depend on.
///
/// The TS engine documents the insert/delete scenarios in a long comment at the
/// top of `rich-text.js`; the labels (`A` through `F`) are reused here so the
/// cases line up with that documentation.
@Suite("segments and edits")
struct SegmentTests {
  @Test("a facet-free string yields one segment")
  func noFacets() {
    let segments = RichText(text: "hello").segments()
    #expect(segments.count == 1)
    #expect(segments[0].text == "hello")
    #expect(segments[0].facet == nil)
  }

  @Test("segments alternate plain and faceted runs")
  func alternating() {
    let richText = RichText(text: "a #tag b")
    richText.detectFacetsWithoutResolution()
    let segments = richText.segments()
    #expect(segments.map(\.text) == ["a ", "#tag", " b"])
    #expect(segments.map(\.isTag) == [false, true, false])
  }

  @Test("segment accessors expose the feature payload")
  func accessors() {
    let richText = RichText(text: "#tag @alice.test https://example.com")
    richText.detectFacetsWithoutResolution()
    let segments = richText.segments()
    #expect(segments.first { $0.isTag }?.tag == "tag")
    #expect(segments.first { $0.isMention }?.mention == "alice.test")
    #expect(segments.first { $0.isLink }?.link == "https://example.com")
  }

  @Test("a whitespace-only facet yields a segment with no facet")
  func whitespaceFacet() {
    // Facets covering only whitespace are surfaced as plain text so an empty
    // entity does not render as a styled run.
    let richText = RichText(
      text: "a   b",
      facets: [Facet(byteStart: 1, byteEnd: 4, feature: .tag(tag: "   "))]
    )
    let segments = richText.segments()
    #expect(segments.map(\.text) == ["a", "   ", "b"])
    #expect(segments.allSatisfy { $0.facet == nil })
  }

  @Test("zero-length facets are skipped but do not drop surrounding text")
  func zeroLengthFacet() {
    // A zero-length facet produces no segment of its own, and the text around it
    // is emitted as separate plain runs. Verified against the TS engine.
    let richText = RichText(
      text: "ab",
      facets: [Facet(byteStart: 1, byteEnd: 1, feature: .tag(tag: "empty"))]
    )
    let segments = richText.segments()
    #expect(segments.map(\.text) == ["a", "b"])
    #expect(segments.allSatisfy { $0.facet == nil })
  }

  @Test("two facets at the same start: the later one is skipped")
  func overlappingSameStart() {
    // segment iteration advances the cursor past the first facet's end, so a
    // second facet starting at the same offset is unreachable and skipped.
    let richText = RichText(
      text: "abcdef",
      facets: [
        Facet(byteStart: 0, byteEnd: 3, feature: .tag(tag: "first")),
        Facet(byteStart: 0, byteEnd: 6, feature: .tag(tag: "second")),
      ]
    )
    let segments = richText.segments()
    #expect(segments.map(\.text) == ["abc", "def"])
    #expect(segments[0].tag == "first")
  }

  @Test("segments tile the whole string for every golden case")
  func tilesGoldenInputs() {
    for testCase in goldenDocument.cases {
      let richText = RichText(text: testCase.input.text)
      richText.detectFacetsWithoutResolution()
      #expect(
        richText.segments().map(\.text).joined() == testCase.input.text,
        "\(testCase.name): segments must reassemble the input"
      )
    }
  }

  @Test("insert shifts facet offsets per scenario")
  func insertScenarios() {
    // A: insert before the facet -> both ends move.
    let before = RichText(
      text: "hello world",
      facets: [Facet(byteStart: 2, byteEnd: 7, feature: .tag(tag: "x"))]
    )
    before.insert(0, "test")
    #expect(before.facets?.first?.index == ByteSlice(byteStart: 6, byteEnd: 11))

    // B: insert inside the facet -> the end moves.
    let inner = RichText(
      text: "hello world",
      facets: [Facet(byteStart: 2, byteEnd: 7, feature: .tag(tag: "x"))]
    )
    inner.insert(4, "test")
    #expect(inner.facets?.first?.index == ByteSlice(byteStart: 2, byteEnd: 11))

    // C: insert after the facet -> noop.
    let after = RichText(
      text: "hello world",
      facets: [Facet(byteStart: 2, byteEnd: 7, feature: .tag(tag: "x"))]
    )
    after.insert(8, "test")
    #expect(after.facets?.first?.index == ByteSlice(byteStart: 2, byteEnd: 7))
  }

  @Test("delete shifts facet offsets per scenario")
  func deleteScenarios() {
    func facet() -> Facet { Facet(byteStart: 2, byteEnd: 7, feature: .tag(tag: "x")) }

    // A: removal covers the facet entirely -> dropped.
    let outer = RichText(text: "hello world", facets: [facet()])
    outer.delete(0, 9)
    #expect(outer.facets?.isEmpty == true)

    // B: removal entirely after -> noop.
    let after = RichText(text: "hello world", facets: [facet()])
    after.delete(7, 11)
    #expect(after.facets?.first?.index == ByteSlice(byteStart: 2, byteEnd: 7))

    // C: removal partially after -> the end moves to the removal start.
    let partialAfter = RichText(text: "hello world", facets: [facet()])
    partialAfter.delete(4, 11)
    #expect(partialAfter.facets?.first?.index == ByteSlice(byteStart: 2, byteEnd: 4))

    // D: removal entirely inside -> the end moves in.
    let inner = RichText(text: "hello world", facets: [facet()])
    inner.delete(3, 5)
    #expect(inner.facets?.first?.index == ByteSlice(byteStart: 2, byteEnd: 5))

    // E: removal partially before -> the start moves to the removal start, the
    // end moves in.
    let partialBefore = RichText(text: "hello world", facets: [facet()])
    partialBefore.delete(1, 5)
    #expect(partialBefore.facets?.first?.index == ByteSlice(byteStart: 1, byteEnd: 3))

    // F: removal entirely before -> both move.
    let before = RichText(text: "hello world", facets: [facet()])
    before.delete(0, 2)
    #expect(before.facets?.first?.index == ByteSlice(byteStart: 0, byteEnd: 5))
  }

  @Test("delete removes facets left with no length")
  func deleteDropsEmptiedFacets() {
    let richText = RichText(
      text: "abc",
      facets: [Facet(byteStart: 1, byteEnd: 2, feature: .tag(tag: "x"))]
    )
    richText.delete(1, 2)
    #expect(richText.facets?.isEmpty == true)
    #expect(richText.text == "ac")
  }
}

/// `sanitizeRichText` newline collapsing.
@Suite("sanitization")
struct SanitizationTests {
  @Test("three or more newlines collapse to one blank line")
  func collapsesExcessNewlines() {
    let richText = RichText(text: "a\n\n\nb")
    let cleaned = sanitizeRichText(richText, cleanNewlines: true)
    #expect(cleaned.text == "a\n\nb")
    // The original is returned unchanged - the TS version clones before editing.
    #expect(richText.text == "a\n\n\nb")
  }

  @Test("longer runs collapse to exactly one blank line")
  func collapsesLongRuns() {
    #expect(sanitizeRichText(RichText(text: "a\n\n\n\n\n\nb"), cleanNewlines: true).text == "a\n\nb")
  }

  @Test("two newlines are left alone")
  func keepsSingleBlankLine() {
    #expect(sanitizeRichText(RichText(text: "a\n\nb"), cleanNewlines: true).text == "a\n\nb")
  }

  @Test("whitespace between newlines still counts as a run")
  func whitespaceBetweenNewlines() {
    // The regex allows whitespace and zero-width characters between the line
    // breaks; note that a *single* space between two newlines is only one line
    // break worth of content, so the run needs a third break to collapse.
    #expect(sanitizeRichText(RichText(text: "a\n \u{200B}\n\nb"), cleanNewlines: true).text == "a\n\nb")
    // Two newlines with whitespace between them are untouched.
    #expect(sanitizeRichText(RichText(text: "a\n \u{200B}\nb"), cleanNewlines: true).text == "a\n \u{200B}\nb")
  }

  @Test("cleanNewlines: false leaves the text untouched")
  func disabled() {
    let richText = RichText(text: "a\n\n\nb")
    #expect(sanitizeRichText(richText, cleanNewlines: false).text == "a\n\n\nb")
  }

  @Test("the RichText initializer applies it when asked")
  func viaInit() {
    let richText = RichText(text: "a\n\n\nb", cleanNewlines: true)
    #expect(richText.text == "a\n\nb")
  }

  @Test("sanitizing adjusts facet offsets with the text")
  func adjustsFacets() {
    let richText = RichText(text: "a\n\n\nb https://example.com")
    richText.detectFacetsWithoutResolution()
    let before = richText.facets?.first
    let cleaned = sanitizeRichText(richText, cleanNewlines: true)
    let after = cleaned.facets?.first
    // One byte was removed before the link, so the facet moved left by one.
    #expect(after?.index.byteStart == (before?.index.byteStart ?? 0) - 1)
    #expect(after?.link == "https://example.com")
    #expect(cleaned.text == "a\n\nb https://example.com")
  }
}

/// `toShortUrl`, `shortenLinks` and `stripInvalidMentions`.
@Suite("link shortening and mention filtering")
struct RichTextManipTests {
  /// Expected values were produced by running `toShortUrl` from the RN app's
  /// `src/lib/strings/url-helpers.ts` under node.
  @Test(
    "toShortUrl",
    arguments: [
      ("https://example.com", "example.com"),
      ("https://example.com/", "example.com"),
      ("https://example.com/a/b?x=1&y=2#frag", "example.com/a/b?x=1&y=2#..."),
      ("http://example.com/very/long/path/that/keeps/going", "example.com/very/long/pa..."),
      // 13 characters: not over the 15-char path budget, so kept whole.
      ("https://example.com/1234567890123", "example.com/1234567890123"),
      ("https://example.com/12345678901234", "example.com/12345678901234"),
      ("https://example.com/p?q=1", "example.com/p?q=1"),
      // Not http(s), or not a URL at all: returned unchanged.
      ("not a url", "not a url"),
      ("at://did:plc:x/app.bsky.feed.post/1", "at://did:plc:x/app.bsky.feed.post/1"),
    ]
  )
  func toShortUrlCases(_ input: String, _ expected: String) {
    #expect(toShortUrl(input) == expected)
  }

  @Test("shortenLinks rewrites link text and keeps the facet over the new text")
  func shortenLinks() {
    let richText = RichText(text: "see https://example.com/very/long/path/that/keeps/going end")
    richText.detectFacetsWithoutResolution()
    let shortened = richText.shortenLinks()

    #expect(shortened.text == "see example.com/very/long/pa... end")
    #expect(shortened.facets?.count == 1)
    #expect(shortened.facets?.first?.index == ByteSlice(byteStart: 4, byteEnd: 31))
    // The URI itself is untouched - only the visible text is shortened.
    #expect(shortened.facets?.first?.link == "https://example.com/very/long/path/that/keeps/going")
    // The original is not modified.
    #expect(richText.text.contains("https://example.com/very/long/path/that/keeps/going"))
  }

  @Test("shortenLinks handles several links and keeps segments tiling")
  func shortenMultipleLinks() {
    let richText = RichText(
      text: "multi https://example.com/aaaa/bbbbbbbbbbbbbbbb and https://example.org/cccc/dddddddddddddddd"
    )
    richText.detectFacetsWithoutResolution()
    let shortened = richText.shortenLinks()

    #expect(shortened.text == "multi example.com/aaaa/bbbbbbb... and example.org/cccc/ddddddd...")
    #expect(shortened.facets?.count == 2)
    #expect(shortened.facets?.map(\.index) == [
      ByteSlice(byteStart: 6, byteEnd: 33),
      ByteSlice(byteStart: 38, byteEnd: 65),
    ])
    #expect(shortened.segments().map(\.text).joined() == shortened.text)
  }

  @Test("shortenLinks leaves non-link facets alone")
  func shortenLeavesTags() {
    let richText = RichText(text: "#tag https://example.com/a/bbbbbbbbbbbbbbbbbb")
    richText.detectFacetsWithoutResolution()
    let shortened = richText.shortenLinks()
    #expect(shortened.facets?.first { $0.tag != nil }?.tag == "tag")
  }

  @Test("shortenLinks on a facet-free string is a no-op")
  func shortenNoFacets() {
    let richText = RichText(text: "plain text")
    #expect(richText.shortenLinks().text == "plain text")
  }

  @Test("stripInvalidMentions drops unresolved mentions and keeps the rest")
  func stripInvalidMentions() {
    let richText = RichText(
      text: "hi @alice.test and @bob.test #tag",
      facets: [
        Facet(byteStart: 3, byteEnd: 14, feature: .mention(did: "")),
        Facet(byteStart: 19, byteEnd: 28, feature: .mention(did: "did:plc:bob")),
        Facet(byteStart: 29, byteEnd: 33, feature: .tag(tag: "tag")),
      ]
    )
    let stripped = richText.stripInvalidMentions()
    #expect(stripped.facets?.count == 2)
    #expect(stripped.facets?.map(\.mention) == ["did:plc:bob", nil])
    #expect(stripped.facets?.last?.tag == "tag")
  }

  @Test("stripInvalidMentions keeps detection output with raw handles in did")
  func stripKeepsDetectedMentions() {
    // detectFacetsWithoutResolution writes the handle into `did`, which is
    // non-empty, so nothing is stripped here.
    let richText = RichText(text: "hi @alice.test")
    richText.detectFacetsWithoutResolution()
    #expect(richText.stripInvalidMentions().facets?.count == 1)
  }
}

/// The 300-grapheme post limit and its helpers.
@Suite("grapheme limits")
struct RichTextLimitsTests {
  @Test("the post limit is 300 graphemes")
  func constant() {
    #expect(RichTextLimits.post == 300)
    #expect(RichTextLimits.displayName == 64)
  }

  @Test("plain strings are counted in graphemes")
  func plainStrings() {
    #expect(!isOverMaxGraphemeCount("abc", maxCount: 3))
    #expect(isOverMaxGraphemeCount("abcd", maxCount: 3))
    // One grapheme, four UTF-16 units: not over a 1-grapheme limit.
    #expect(!isOverMaxGraphemeCount("\u{1F44D}\u{1F3FD}", maxCount: 1))
  }

  @Test("rich text is counted after link shortening")
  func richTextCountedShortened() {
    // The full URL pushes the text over the limit; its short form does not.
    let longUrl = "https://example.com/very/long/path/that/keeps/going/on/and/on"
    let richText = RichText(text: "x " + longUrl)
    richText.detectFacetsWithoutResolution()
    #expect(richText.graphemeLength > 40)
    #expect(!isOverMaxGraphemeCount(richText, maxCount: 40))
  }
}

/// `richTextToString` and the link-spoofing checks it is built on.
@Suite("string rendering")
struct RichTextStringTests {
  @Test("links whose label matches the host render as bare hrefs")
  func matchingLabels() {
    let richText = RichText(text: "see example.com")
    richText.detectFacetsWithoutResolution()
    let rendered = richTextToString(richText, isTrusted: { _ in false })
    #expect(rendered == "see https://example.com")
  }

  @Test("a misleading label collapses to the label, or to Markdown in loose mode")
  func mismatchedLabels() {
    let richText = RichText(
      text: "click evil.com",
      facets: [Facet(byteStart: 6, byteEnd: 14, feature: .link(uri: "https://good.com"))]
    )
    #expect(richTextToString(richText, isTrusted: { _ in false }) == "click evil.com")
    #expect(
      richTextToString(richText, loose: true, isTrusted: { _ in false })
        == "click [evil.com](https://good.com)"
    )
  }

  @Test("facet-free text is returned as-is")
  func noFacets() {
    #expect(richTextToString(RichText(text: "plain"), isTrusted: { _ in false }) == "plain")
  }

  @Test("relative URLs and bare # never warn")
  func internalLinks() {
    #expect(!linkRequiresWarning(href: "/profile/x", label: "anything", isTrusted: { _ in false }))
    #expect(!linkRequiresWarning(href: "#", label: "anything", isTrusted: { _ in false }))
  }

  @Test("an unparseable href always warns")
  func unparseable() {
    #expect(linkRequiresWarning(href: ":::", label: "x", isTrusted: { _ in false }))
  }

  @Test("external links warn when the label is or is not a URL")
  func externalLinks() {
    // Label is unrelated text: warn.
    #expect(
      linkRequiresWarning(href: "https://good.com", label: "hello", isTrusted: { _ in false })
    )
    // Label matches the host: no warning.
    #expect(
      !linkRequiresWarning(href: "https://good.com", label: "good.com", isTrusted: { _ in false })
    )
    // Label is a different host: warn.
    #expect(
      linkRequiresWarning(href: "https://good.com", label: "evil.com", isTrusted: { _ in false })
    )
  }

  @Test("trusted links only warn when the label claims another URL")
  func trustedLinks() {
    let trusted: (String) -> Bool = { $0.contains("bsky.app") }
    #expect(
      !linkRequiresWarning(href: "https://bsky.app/profile/x", label: "hi", isTrusted: trusted)
    )
    #expect(
      linkRequiresWarning(
        href: "https://bsky.app/profile/x",
        label: "evil.com",
        isTrusted: trusted
      )
    )
  }

  @Test("labelToDomain normalizes a bare host")
  func labelDomains() {
    #expect(labelToDomain("example.com") == "example.com")
    #expect(labelToDomain("EXAMPLE.com") == "example.com")
    #expect(labelToDomain("https://Example.com/path") == "example.com")
    #expect(labelToDomain("two words") == nil)
  }

  @Test("isRelativeUrl distinguishes in-app paths from protocol-relative URLs")
  func relativeUrls() {
    #expect(isRelativeUrl("/profile/x"))
    #expect(!isRelativeUrl("//example.com"))
    #expect(!isRelativeUrl("/"))
    #expect(!isRelativeUrl("https://example.com/x"))
  }
}
