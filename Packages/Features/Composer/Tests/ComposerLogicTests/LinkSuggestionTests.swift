import Foundation
import RichText
import Testing

@testable import ComposerLogic

/// Link-card suggestion and URL validation.
///
/// Ported from `suggestLinkCardUri` and `isValidUrlAndDomain` in
/// `src/view/com/composer/text-input/text-input-util.ts`.
@Suite("LinkSuggestion")
struct LinkSuggestionTests {

  @Test("an immediate suggestion skips the stability check")
  func immediateSuggestion() {
    let uri = "https://example.com/story"
    var past = Set<String>()
    let suggested = suggestLinkCardUri(
      suggestImmediately: true,
      nextDetectedUris: [uri: match(uri: uri, text: uri)],
      prevDetectedUris: [:],
      pastSuggestedUris: &past)
    #expect(suggested == uri)
    #expect(past.contains(uri))
  }

  @Test("a link not seen on the previous keystroke is ignored while typing")
  func unstableLinkIgnored() {
    let uri = "https://example.com/story"
    var past = Set<String>()
    let suggested = suggestLinkCardUri(
      suggestImmediately: false,
      nextDetectedUris: [uri: match(uri: uri, text: uri)],
      prevDetectedUris: [:],
      pastSuggestedUris: &past)
    #expect(suggested == nil)
  }

  @Test("a link becomes eligible when the text before it changes and the tail is stable")
  func stableTailSuggests() {
    let uri = "https://example.com/story"
    var past = Set<String>()
    let suggested = suggestLinkCardUri(
      suggestImmediately: false,
      nextDetectedUris: [uri: match(uri: uri, text: "abc " + uri)],
      prevDetectedUris: [uri: match(uri: uri, text: "ab " + uri)],
      pastSuggestedUris: &past)
    #expect(suggested == uri)
  }

  @Test("a link followed by a space is eligible")
  func trailingSpaceSuggests() {
    let uri = "https://example.com/story"
    var past = Set<String>()
    let suggested = suggestLinkCardUri(
      suggestImmediately: false,
      nextDetectedUris: [uri: match(uri: uri, text: uri + " ")],
      prevDetectedUris: [uri: match(uri: uri, text: uri)],
      pastSuggestedUris: &past)
    #expect(suggested == uri)
  }

  @Test("a link followed by punctuation and a space is eligible")
  func punctuationThenSpaceSuggests() {
    let uri = "https://example.com/story"
    var past = Set<String>()
    let suggested = suggestLinkCardUri(
      suggestImmediately: false,
      nextDetectedUris: [uri: match(uri: uri, text: uri + ". ")],
      prevDetectedUris: [uri: match(uri: uri, text: uri + ".")],
      pastSuggestedUris: &past)
    #expect(suggested == uri)
  }

  @Test("a link being extended is not eligible")
  func stillTypingNotEligible() {
    let uri = "https://example.com/story"
    var past = Set<String>()
    let suggested = suggestLinkCardUri(
      suggestImmediately: false,
      nextDetectedUris: [uri: match(uri: uri, text: "see " + uri + "/more")],
      prevDetectedUris: [uri: match(uri: uri, text: "see " + uri)],
      pastSuggestedUris: &past)
    #expect(suggested == nil)
  }

  @Test("an already-suggested link is never suggested twice")
  func alreadySuggestedSkipped() {
    let uri = "https://example.com/story"
    var past: Set<String> = [uri]
    let suggested = suggestLinkCardUri(
      suggestImmediately: true,
      nextDetectedUris: [uri: match(uri: uri, text: uri)],
      prevDetectedUris: [:],
      pastSuggestedUris: &past)
    #expect(suggested == nil)
  }

  @Test("a link that stops being detected becomes eligible again")
  func noLongerDetectedIsForgotten() {
    let uri = "https://example.com/story"
    var past: Set<String> = [uri]
    _ = suggestLinkCardUri(
      suggestImmediately: true,
      nextDetectedUris: [:],
      prevDetectedUris: [:],
      pastSuggestedUris: &past)
    #expect(!past.contains(uri))
  }

  @Test("URL validation accepts public hosts and rejects private addresses")
  func urlValidation() {
    #expect(isValidUrlAndDomain("https://example.com"))
    #expect(isValidUrlAndDomain("https://sub.example.co.uk/path?q=1#f"))
    #expect(!isValidUrlAndDomain("https://10.0.0.1/x"))
    #expect(!isValidUrlAndDomain("https://127.0.0.1/x"))
    #expect(!isValidUrlAndDomain("https://192.168.1.1/x"))
    #expect(!isValidUrlAndDomain("https://172.16.0.1/x"))
    #expect(!isValidUrlAndDomain("https://169.254.1.1/x"))
    #expect(!isValidUrlAndDomain("not a url"))
  }

  @Test("detected link URIs are split into post and external buckets")
  func detectionSplit() {
    let value = RichTextValue(
      text: "https://example.com/story and https://bsky.app/profile/a.test/post/b"
    ).detectingFacetsWithoutResolution()
    let detected = ComposerReducer.detectLinkUris(in: value)
    #expect(detected.externalUris.keys.sorted() == ["https://example.com/story"])
    #expect(detected.postUris.keys.sorted() == ["https://bsky.app/profile/a.test/post/b"])
  }

  @Test("detection produces an empty result when there are no facets")
  func detectionEmpty() {
    let detected = ComposerReducer.detectLinkUris(in: RichTextValue(text: "no links here"))
    #expect(detected.isEmpty)
  }

  // MARK: - Helpers

  /// A facet match for `uri` located inside `text`.
  ///
  /// The facet's byte range must actually point at the URI, because the
  /// stability checks read the text *after* `facet.index.byteEnd`; a facet at
  /// byte 0 in a text with a prefix would measure the wrong tail.
  private func match(uri: String, text: String) -> LinkFacetMatch {
    let richText = RichTextValue(text: text)
    // Find the URI's byte offset within the text.
    let utf8 = Array(text.utf8)
    let needle = Array(uri.utf8)
    var offset = 0
    if needle.count <= utf8.count {
      for candidate in 0...(utf8.count - needle.count)
      where Array(utf8[candidate..<(candidate + needle.count)]) == needle {
        offset = candidate
        break
      }
    }
    let facet = Facet(
      byteStart: offset, byteEnd: offset + uri.utf8.count, feature: .link(uri: uri))
    return LinkFacetMatch(richText: richText, facet: facet)
  }
}
