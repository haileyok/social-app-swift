import Foundation
import Testing

@testable import RichText

/// Local facet detection beyond the golden corpus.
///
/// The golden suite pins the exact TS output for 15 inputs; these cases cover the
/// behaviours that are implied by the ported regexes but not present in the
/// fixture: schemeless URLs, trailing-punctuation trimming, mention validity,
/// hashtag edge cases, cashtags, and how overlapping facets from different scans
/// survive detection.
@Suite("facet detection")
struct FacetDetectionTests {
  /// Detects facets and returns `text`'s facets as `(byteStart, byteEnd, feature)`.
  private func detect(_ text: String) -> [(Int, Int, FacetFeature)] {
    let richText = RichText(text: text)
    richText.detectFacetsWithoutResolution()
    return (richText.facets ?? []).map { ($0.index.byteStart, $0.index.byteEnd, $0.features[0]) }
  }

  @Test("no facets for plain text")
  func plainText() {
    #expect(detect("just a normal sentence").isEmpty)
    #expect(detect("").isEmpty)
  }

  @Test("scheme-less domains get https prepended, and are only accepted for real TLDs")
  func schemelessDomains() {
    let facets = detect("see example.com here")
    #expect(facets.count == 1)
    #expect(facets.first?.2 == .link(uri: "https://example.com"))
    #expect(facets.first?.0 == 4)
    #expect(facets.first?.1 == 15)

    // "foo.bar" matches the domain shape, but ".bar" is a real TLD...
    let tldFacet = detect("go to foo.bar now")
    #expect(tldFacet.first?.2 == .link(uri: "https://foo.bar"))

    // ...while an unknown TLD must not produce a facet.
    #expect(detect("go to foo.zzzz now").isEmpty)
  }

  @Test("a scheme-less domain at the very start of the text is detected")
  func schemelessAtStart() {
    // The leading alternative of the URL pattern is `(^|\s|\()`, so position 0 is
    // a valid start even though the URL scan itself edits nothing.
    let facets = detect("a.com")
    #expect(facets.first?.2 == .link(uri: "https://a.com"))
    #expect(facets.first?.0 == 0)
    #expect(facets.first?.1 == 5)
  }

  @Test("trailing sentence punctuation is trimmed from the link, not the facet text")
  func trailingPunctuation() {
    let facets = detect("see https://example.com/path.")
    #expect(facets.first?.2 == .link(uri: "https://example.com/path"))
    // The facet range excludes the period.
    #expect(facets.first?.1 == 4 + "https://example.com/path".utf8.count)

    // Unbalanced ")" is trimmed; balanced parentheses are kept.
    #expect(detect("(https://example.com)").first?.2 == .link(uri: "https://example.com"))
    #expect(
      detect("https://en.wikipedia.org/wiki/Foo_(bar)")
        .first?.2 == .link(uri: "https://en.wikipedia.org/wiki/Foo_(bar)")
    )
  }

  @Test("mentions require a valid TLD or .test")
  func mentions() {
    #expect(detect("hi @alice.com").first?.2 == .mention(did: "alice.com"))
    #expect(detect("hi @alice.test").first?.2 == .mention(did: "alice.test"))
    // Not a TLD, and not .test: no facet.
    #expect(detect("hi @alice.zzzz").isEmpty)
    // No dot at all.
    #expect(detect("hi @alicewonderland").isEmpty)
  }

  @Test("mention facet covers the @ and the handle")
  func mentionRange() {
    let facets = detect("hi @alice.test")
    #expect(facets.first?.0 == 3)
    #expect(facets.first?.1 == 14)
  }

  @Test("hashtags strip trailing punctuation and reject leading digits")
  func hashtags() {
    #expect(detect("#about").first?.2 == .tag(tag: "about"))
    #expect(detect("#about!").first?.2 == .tag(tag: "about"))
    // The tag must not be all digits/punctuation - the regex requires one
    // non-digit, non-punctuation character.
    #expect(detect("#123").isEmpty)
    #expect(detect("#").isEmpty)
    // A leading digit is fine as long as a non-digit follows.
    #expect(detect("#1abc").first?.2 == .tag(tag: "1abc"))
    // Full-width "#" is accepted.
    #expect(detect("\u{FF03}tag").first?.2 == .tag(tag: "tag"))
  }

  @Test("cashtags are uppercased and keep the $")
  func cashtags() {
    let facets = detect("buy $aapl now")
    #expect(facets.first?.2 == .tag(tag: "$AAPL"))
    // Cashtags have their own exclusive leading boundary, including ")".
    #expect(detect("($tsla)").first?.2 == .tag(tag: "$TSLA"))
    // The ticker is capped at 5 characters; a 5-letter run followed by end-of-text
    // still matches (the lookahead accepts `$`, which ICU honors as end-of-input).
    #expect(detect("$tslax").first?.2 == .tag(tag: "$TSLAX"))
    // A 6-letter ticker cannot match at all: the extra character fails the
    // lookahead, and no shorter prefix is followed by a valid boundary.
    #expect(detect("$tslaxx").isEmpty)
  }

  @Test("overlapping facets from different scans are all reported")
  func overlappingFacets() {
    // A bare domain inside a mention-like run: both the mention scan and the URL
    // scan can match. Detection does not deduplicate, and RichText sorts by
    // byteStart only - the segment loop skips whichever ends first.
    let richText = RichText(text: "x @a.com https://b.com")
    richText.detectFacetsWithoutResolution()
    let facets = richText.facets ?? []
    #expect(facets.count == 2)
    #expect(facets[0].index.byteStart <= facets[1].index.byteStart, "facets are sorted")

    // Segment iteration must still tile the whole string.
    #expect(richText.segments().map(\.text).joined() == richText.text)
  }

  @Test("facets are returned as nil when nothing matched")
  func nilWhenEmpty() {
    #expect(detectFacets(UnicodeString("plain")) == nil)
    #expect(detectFacets(UnicodeString("a.com"))?.isEmpty == false)
  }

  @Test("detection overwrites existing facets")
  func overwrites() {
    let richText = RichText(text: "see https://example.com")
    richText.facets = [Facet(byteStart: 0, byteEnd: 3, feature: .tag(tag: "stale"))]
    richText.detectFacetsWithoutResolution()
    #expect(richText.facets?.count == 1)
    #expect(richText.facets?.first?.link == "https://example.com")
  }
}

/// Facet, entity and initializer behaviour.
@Suite("facets and construction")
struct FacetModelTests {
  @Test("FacetFeature round-trips through JSON with the $type discriminator")
  func featureCoding() throws {
    let features: [FacetFeature] = [
      .link(uri: "https://example.com"),
      .mention(did: "did:plc:abc"),
      .tag(tag: "news"),
    ]
    for feature in features {
      let data = try JSONEncoder().encode(feature)
      let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: String]
      )
      #expect(object["$type"] == feature.type)
      #expect(try JSONDecoder().decode(FacetFeature.self, from: data) == feature)
    }
  }

  @Test("Facet decodes the golden fixture's shape")
  func facetCoding() throws {
    let json = """
      {"index": {"byteStart": 8, "byteEnd": 27},
       "features": [{"uri": "https://example.com", "$type": "app.bsky.richtext.facet#link"}]}
      """
    let facet = try JSONDecoder().decode(Facet.self, from: Data(json.utf8))
    #expect(facet.index == ByteSlice(byteStart: 8, byteEnd: 27))
    #expect(facet.link == "https://example.com")
    #expect(facet.features == [.link(uri: "https://example.com")])
  }

  @Test("init drops negative-length facets but keeps zero-length ones")
  func facetFilter() {
    let richText = RichText(
      text: "hello",
      facets: [
        Facet(byteStart: 4, byteEnd: 2, feature: .tag(tag: "negative")),
        Facet(byteStart: 2, byteEnd: 2, feature: .tag(tag: "zero")),
      ]
    )
    #expect(richText.facets?.count == 1)
    #expect(richText.facets?.first?.tag == "zero")
  }

  @Test("init sorts facets by byteStart")
  func facetSort() {
    let richText = RichText(
      text: "hello world",
      facets: [
        Facet(byteStart: 6, byteEnd: 11, feature: .tag(tag: "second")),
        Facet(byteStart: 0, byteEnd: 5, feature: .tag(tag: "first")),
      ]
    )
    #expect(richText.facets?.map(\.index.byteStart) == [0, 6])
  }

  @Test("entities convert from UTF-16 offsets to UTF-8 byte offsets")
  func entities() {
    // "🙂" is 2 UTF-16 units and 4 UTF-8 bytes, so the entity's UTF-16 range
    // {0, 2} must come out as bytes {0, 4}.
    let richText = RichText(
      text: "\u{1F642} hi",
      entities: [RichTextEntity(type: .link, value: "https://example.com", start: 0, end: 2)]
    )
    #expect(richText.facets?.first?.index == ByteSlice(byteStart: 0, byteEnd: 4))
    #expect(richText.facets?.first?.link == "https://example.com")
  }

  @Test("explicit facets win over entities")
  func facetsBeatEntities() {
    let richText = RichText(
      text: "hello",
      facets: [Facet(byteStart: 0, byteEnd: 5, feature: .tag(tag: "facet"))],
      entities: [RichTextEntity(type: .link, value: "x", start: 0, end: 5)]
    )
    #expect(richText.facets?.first?.tag == "facet")
  }
}
