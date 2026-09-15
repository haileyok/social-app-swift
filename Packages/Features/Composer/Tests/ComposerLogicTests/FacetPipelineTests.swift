import Foundation
import Lexicons
import RichText
import SwiftAtproto
import Testing

@testable import ComposerLogic

/// The facet pipeline and its byte math.
///
/// The composer converts RichText's facets into lexicon facets at publish time;
/// this suite pins the conversion, especially the UTF-8 byte offsets that emoji
/// and other multi-byte scalars make easy to get wrong.
@Suite("FacetPipeline")
struct FacetPipelineTests {

  @Test("a plain ASCII link converts to a lexicon facet with byte offsets")
  func asciiLinkFacet() {
    let value = RichTextValue(text: "see https://example.com").detectingFacetsWithoutResolution()
    let facets = ComposerRecordBuilder.facets(from: value.richText())
    #expect(facets?.count == 1)
    let facet = facets![0]
    #expect(facet.index.byteStart == 4)
    #expect(facet.index.byteEnd == 23)
    guard case .richtextFacetLink(let link) = facet.features[0] else {
      Issue.record("expected a link feature")
      return
    }
    #expect(link.uri.rawValue == "https://example.com")
  }

  @Test("an emoji before a link shifts the facet by its UTF-8 byte length, not its grapheme count")
  func emojiShiftsByteOffsets() {
    // "🎉 " is 4 bytes of emoji plus 1 byte of space = 5 bytes, but 2 graphemes.
    let value = RichTextValue(text: "🎉 https://example.com").detectingFacetsWithoutResolution()
    let facets = ComposerRecordBuilder.facets(from: value.richText())
    #expect(facets?.count == 1)
    let facet = facets![0]
    #expect(facet.index.byteStart == 5)
    #expect(facet.index.byteEnd == 24)
    // The grapheme count is much smaller than the byte offset, which is the
    // whole point of the distinction.
    #expect(value.graphemeLength == 21)
    #expect(value.byteLength == 24)
  }

  @Test("a mention with a resolved DID converts")
  func mentionFacet() {
    let richText = RichText(
      text: "hi @alice.test",
      facets: [Facet(byteStart: 3, byteEnd: 14, feature: .mention(did: "did:plc:alice"))])
    let facets = ComposerRecordBuilder.facets(from: richText)
    guard case .richtextFacetMention(let mention) = facets?.first?.features.first else {
      Issue.record("expected a mention feature")
      return
    }
    #expect(mention.did.rawValue == "did:plc:alice")
  }

  @Test("an unresolved mention is dropped from the published facets")
  func unresolvedMentionDropped() {
    let richText = RichText(
      text: "hi @alice.test",
      facets: [Facet(byteStart: 3, byteEnd: 14, feature: .mention(did: ""))])
    #expect(ComposerRecordBuilder.facets(from: richText) == nil)
  }

  @Test("a tag facet converts")
  func tagFacet() {
    let richText = RichText(
      text: "hi #swift",
      facets: [Facet(byteStart: 3, byteEnd: 9, feature: .tag(tag: "swift"))])
    let facets = ComposerRecordBuilder.facets(from: richText)
    guard case .richtextFacetTag(let tag) = facets?.first?.features.first else {
      Issue.record("expected a tag feature")
      return
    }
    #expect(tag.tag == "swift")
  }

  @Test("no facets publishes without the field")
  func noFacetsIsNil() {
    let value = RichTextValue(text: "just words")
    #expect(ComposerRecordBuilder.facets(from: value.richText()) == nil)
  }

  @Test("an emoji link's facet round-trips through JSON at the right byte offset")
  func emojiFacetJSON() {
    let richText = RichText(text: "🎉🎉 https://example.com")
    richText.detectFacetsWithoutResolution()
    let facets = ComposerRecordBuilder.facets(from: richText)
    let byteSlice = facets?.first?.index
    // Two 4-byte emoji plus a space is 9 bytes.
    #expect(byteSlice?.byteStart == 9)
    #expect(byteSlice?.byteEnd == 28)
    // And the wire form carries those numbers verbatim.
    do {
      let data = try JSONEncoder().encode(facets!)
      let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
      let wireIndex = array?.first?["index"] as? [String: Any]
      #expect(wireIndex?["byteStart"] as? Int == 9)
      #expect(wireIndex?["byteEnd"] as? Int == 28)
    } catch {
      Issue.record("facet encoding failed: \(error)")
    }
  }

  @Test("publish text trims leading blank lines and trailing whitespace")
  func publishTextTrimming() {
    #expect(ComposerText.publishText("\n\n  hello  ") == "  hello")
    #expect(ComposerText.publishText("hello\n\n\nworld\n") == "hello\n\n\nworld")
    #expect(ComposerText.publishText("ASCII art:\n  /\n / ") == "ASCII art:\n  /\n /")
  }

  @Test("shortened grapheme length counts a long URL as its short form")
  func shortenedLength() {
    let long = "https://example.com/a/very/long/path/that/keeps/going/and/going"
    let value = RichTextValue(text: long).detectingFacetsWithoutResolution()
    #expect(value.graphemeLength == long.count)
    #expect(ComposerText.shortenedGraphemeLength(value) < long.count)
  }

  @Test("the 300-grapheme rule is measured after shortening")
  func limitMeasuredAfterShortening() {
    // 270 characters of text plus a long URL: over 300 raw graphemes, but the
    // shortened URL brings it under the limit.
    let url = "https://example.com/some/extremely/long/path/for/testing"
    let text = String(repeating: "a", count: 270) + " " + url
    let value = RichTextValue(text: text).detectingFacetsWithoutResolution()
    let post = PostDraft(id: "p", richText: value)
    #expect(value.graphemeLength > 300)
    #expect(post.shortenedGraphemeLength <= 300)
    let thread = Fixtures.thread(posts: [post])
    #expect(ComposerValidation.canPost(thread: thread))
  }

  @Test("an emoji-only post counts graphemes, not bytes")
  func emojiGraphemeCounting() {
    // A family emoji with ZWJ joins: many scalars, one grapheme.
    let family = "👨‍👩‍👧‍👦"
    let value = RichTextValue(text: family)
    #expect(value.graphemeLength == 1)
    #expect(value.byteLength > 1)
  }

  @Test("four-byte scalars advance byte offsets correctly for a second facet")
  func multipleFacetsWithEmoji() {
    let richText = RichText(text: "🎉 https://a.test 🎉 https://b.test")
    richText.detectFacetsWithoutResolution()
    let facets = ComposerRecordBuilder.facets(from: richText)
    #expect(facets?.count == 2)
    // Second facet starts after "🎉 https://a.test 🎉 " = 5 + 14 + 1 + 4 + 1 = 25 bytes.
    #expect(facets?[1].index.byteStart == 25)
  }
}
