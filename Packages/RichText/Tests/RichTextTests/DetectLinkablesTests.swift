import Foundation
import Testing

@testable import RichText

/// `detectLinkables`, the RN app's plain-text linkification pass.
///
/// There is no sibling test file in the reference repo (`src/lib/strings/__tests__`
/// holds only `bidi`, `errors` and `text-direction`), so these cases were
/// produced by running the original TypeScript function under node and are
/// recorded verbatim.
@Suite("detectLinkables")
struct DetectLinkablesTests {
  /// Flattens the output into a comparable, readable form.
  private func segments(_ text: String) -> [DetectedLinkable] {
    detectLinkables(text)
  }

  @Test("text with no links is one literal run")
  func noLinks() {
    #expect(segments("hello world") == [.text("hello world")])
  }

  @Test("a URL is split out with its surrounding text")
  func simpleUrl() {
    #expect(
      segments("check https://example.com out")
        == [.text("check "), .link("https://example.com"), .text(" out")]
    )
  }

  @Test("a schemeless domain is detected without a scheme added")
  func schemelessDomain() {
    // Unlike detectFacets, detectLinkables keeps the link text exactly as it
    // appeared and does not normalize to https.
    #expect(segments("see www.example.com now") == [.text("see "), .link("www.example.com"), .text(" now")])
    #expect(segments("no scheme example.org/path here") == [
      .text("no scheme "), .link("example.org/path"), .text(" here"),
    ])
  }

  @Test("a mention is treated as a link")
  func mentionsAreLinks() {
    #expect(segments("ping @alice.test please") == [
      .text("ping "), .link("@alice.test"), .text(" please"),
    ])
  }

  @Test("the leading separator is excluded from the link")
  func stripsLeadingSeparator() {
    // The regex consumes the space or "(" before the link and the ported code
    // steps back over it, so the literal run keeps that character.
    #expect(segments("a (https://example.com) b") == [
      .text("a ("), .link("https://example.com"), .text(") b"),
    ])
  }

  @Test("trailing punctuation is stripped from the link")
  func trailingPunctuation() {
    #expect(segments("trailing https://example.com/path.") == [
      .text("trailing "), .link("https://example.com/path"), .text("."),
    ])
    // Balanced parentheses inside the URL are kept.
    #expect(segments("paren https://example.com/a(b) end") == [
      .text("paren "), .link("https://example.com/a(b)"), .text(" end"),
    ])
  }

  @Test("a link at the very start of the text")
  func atStart() {
    #expect(segments("start https://example.com") == [
      .text("start "), .link("https://example.com"),
    ])
  }

  @Test("a URL immediately followed by whitespace keeps the slash")
  func trailingSlash() {
    #expect(segments("mid https://example.com/ end") == [
      .text("mid "), .link("https://example.com/"), .text(" end"),
    ])
  }

  @Test("the segments reassemble the input in order")
  func reassembles() {
    for text in [
      "check https://example.com out",
      "a (https://example.com) b",
      "ping @alice.test please",
      "bare example.com",
      "hello world",
    ] {
      let rebuilt = segments(text)
        .map { segment in
          switch segment {
          case .text(let text): text
          case .link(let link): link
          }
        }
        .joined()
      #expect(rebuilt == text, "\(text): segments must tile the input")
    }
  }
}
