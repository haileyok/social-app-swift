import Foundation
import Testing

@testable import Domain

/// `src/lib/link-meta/link-meta.ts` has no sibling test file in the RN repo, so
/// these cases assert the pure classification and mapping logic directly.
@Suite("link-meta")
struct LinkMetaTests {

  @Test func getLikelyTypeClassifiesImagesByPath() {
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.png") == .image)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.jpg") == .image)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.JPEG") == .image)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.webp") == .image)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.svgz") == .image)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.tiff") == .image)
  }

  @Test func getLikelyTypeFallsBackToHtml() {
    #expect(LinkMeta.getLikelyType(from: "https://example.com/") == .html)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/page") == .html)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.png?x=1") == .image)
    #expect(LinkMeta.getLikelyType(from: "https://example.com/a.pngx") == .html)
  }

  @Test func getLikelyTypeOfUnparseableUrlIsOther() {
    #expect(LinkMeta.getLikelyType(from: "notaurl") == .other)
  }

  @Test func preflightTreatsNonStarterPackAppUrlsAsAtpData() {
    #expect(LinkMeta.preflightType(url: "https://bsky.app/profile/alice") == .atpData)
    // Starter packs are fetched, not treated as AtpData.
    #expect(LinkMeta.preflightType(url: "https://bsky.app/starter-pack/alice/3k") == nil)
    #expect(LinkMeta.preflightType(url: "https://example.com") == nil)
  }

  @Test func proxyBodyMapsFields() {
    let meta = LinkMeta(likelyType: .html, url: "https://example.com")
    let body: [String: LinkMetaValue] = [
      "description": .string("desc"),
      "image": .string("https://example.com/img.png"),
      "title": .string("title"),
    ]
    let updated = LinkMeta.applyingProxyBody(body, to: meta, shouldFollowRedirect: false)
    #expect(updated.description == "desc")
    #expect(updated.image == "https://example.com/img.png")
    #expect(updated.title == "title")
    // Without the redirect flag the proxy url is not applied.
    #expect(updated.url == "https://example.com")
  }

  @Test func proxyBodyAppliesRedirectUrlOnlyWhenFollowing() {
    let meta = LinkMeta(likelyType: .html, url: "https://on.soundcloud.com/x")
    let body: [String: LinkMetaValue] = ["url": .string("https://soundcloud.com/real")]
    let followed = LinkMeta.applyingProxyBody(body, to: meta, shouldFollowRedirect: true)
    #expect(followed.url == "https://soundcloud.com/real")
  }

  @Test func proxyErrorReportsNonEmptyError() {
    #expect(LinkMeta.proxyError(in: ["error": .string("")]) == nil)
    #expect(LinkMeta.proxyError(in: ["error": .string("boom")]) == "boom")
    #expect(LinkMeta.proxyError(in: [:]) == nil)
  }

  @Test func parseStarterPackUriParts() {
    let at = parseStarterPackUri("at://did:plc:alice/app.bsky.graph.starterpack/3k")
    #expect(at?.name == "did:plc:alice")
    #expect(at?.rkey == "3k")

    let http = parseStarterPackUri("https://bsky.app/starter-pack/alice.test/3k")
    #expect(http?.name == "alice.test")
    #expect(http?.rkey == "3k")

    let start = parseStarterPackUri("https://bsky.app/start/alice.test/3k")
    #expect(start?.rkey == "3k")

    #expect(parseStarterPackUri(nil) == nil)
    #expect(parseStarterPackUri("https://bsky.app/profile/alice") == nil)
    #expect(parseStarterPackUri("at://did:plc:alice/app.bsky.feed.post/3k") == nil)
  }
}
