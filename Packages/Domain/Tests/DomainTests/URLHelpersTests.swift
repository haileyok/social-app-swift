import Foundation
import Testing

@testable import Domain

/// `src/lib/strings/url-helpers.ts` has no sibling test file in the RN repo, so
/// these cases were captured from the JS implementation directly (running the
/// ported functions' Node equivalents) and assert the same outputs.
@Suite("url-helpers")
struct URLHelpersTests {

  // MARK: - canParseUrl

  @Test func canParseUrl() {
    #expect(URLHelpers.canParseUrl("https://example.com"))
    #expect(!URLHelpers.canParseUrl("notaurl"))
    #expect(URLHelpers.canParseUrl("/profile/alice", base: "https://bsky.app"))
  }

  // MARK: - isValidDomain

  @Test func isValidDomain() {
    #expect(URLHelpers.isValidDomain("example.com"))
    #expect(URLHelpers.isValidDomain("foo.co.uk"))
    #expect(!URLHelpers.isValidDomain("localhost"))
    #expect(!URLHelpers.isValidDomain("example.notatld"))
    // The TLD must be a suffix, preceded by a dot.
    #expect(!URLHelpers.isValidDomain("example.com/path"))
  }

  // MARK: - makeRecordUri

  @Test func makeRecordUri() {
    #expect(
      URLHelpers.makeRecordUri(
        didOrName: "did:plc:alice", collection: "app.bsky.feed.post", rkey: "3k")
        == "at://did:plc:alice/app.bsky.feed.post/3k")
  }

  // MARK: - Display helpers

  @Test func toNiceDomain() {
    #expect(URLHelpers.toNiceDomain("https://bsky.social") == "Bluesky Social")
    #expect(URLHelpers.toNiceDomain("https://example.com/x") == "example.com")
    #expect(URLHelpers.toNiceDomain("notaurl") == "notaurl")
  }

  @Test func toShortUrl() {
    #expect(URLHelpers.toShortUrl("https://example.com/") == "example.com")
    #expect(URLHelpers.toShortUrl("https://example.com/abc") == "example.com/abc")
    #expect(
      URLHelpers.toShortUrl("https://example.com/abcdefghijklmnopqrst")
        == "example.com/abcdefghijkl...")
    #expect(URLHelpers.toShortUrl("https://example.com/a?b=c#d") == "example.com/a?b=c#d")
    // Non-http(s) protocols are returned unchanged.
    #expect(URLHelpers.toShortUrl("ftp://example.com/x") == "ftp://example.com/x")
  }

  @Test func toShareUrl() {
    #expect(URLHelpers.toShareUrl("/profile/alice") == "https://bsky.app/profile/alice")
    #expect(URLHelpers.toShareUrl("profile/alice") == "https://bsky.app/profile/alice")
    #expect(URLHelpers.toShareUrl("/") == "https://bsky.app/")
    // `?` and `#` are path characters once assigned to `pathname`, so the JS
    // setter percent-encodes them.
    #expect(
      URLHelpers.toShareUrl("/profile/alice?x=1") == "https://bsky.app/profile/alice%3Fx=1")
    #expect(URLHelpers.toShareUrl("/profile/alice#f") == "https://bsky.app/profile/alice%23f")
    #expect(URLHelpers.toShareUrl("https://x.com/a") == "https://x.com/a")
  }

  @Test func toNiceHostingUrl() {
    #expect(URLHelpers.toNiceHostingUrl("https://foo.host.bsky.network") == "Bluesky")
    #expect(URLHelpers.toNiceHostingUrl("https://example.com") == "example.com")
  }

  @Test func isBlueskyHostedUrl() {
    #expect(URLHelpers.isBlueskyHostedUrl("https://bsky.social"))
    #expect(URLHelpers.isBlueskyHostedUrl("https://foo.host.bsky.network"))
    #expect(!URLHelpers.isBlueskyHostedUrl("https://example.com"))
    #expect(!URLHelpers.isBlueskyHostedUrl("notaurl"))
  }

  // MARK: - Bluesky URL classification

  @Test func isBskyAppUrl() {
    #expect(URLHelpers.isBskyAppUrl("https://bsky.app/profile/alice"))
    #expect(!URLHelpers.isBskyAppUrl("https://bsky.app"))
    #expect(!URLHelpers.isBskyAppUrl("https://example.com"))
  }

  @Test func isRelativeUrl() {
    #expect(URLHelpers.isRelativeUrl("/profile/alice"))
    #expect(!URLHelpers.isRelativeUrl("//example.com"))
    #expect(!URLHelpers.isRelativeUrl("https://example.com"))
  }

  @Test func isBskyRSSUrl() {
    #expect(URLHelpers.isBskyRSSUrl("https://bsky.app/profile/alice/rss"))
    #expect(URLHelpers.isBskyRSSUrl("/profile/alice/rss"))
    #expect(!URLHelpers.isBskyRSSUrl("https://bsky.app/profile/alice"))
  }

  @Test func isExternalUrl() {
    #expect(URLHelpers.isExternalUrl("https://example.com"))
    #expect(!URLHelpers.isExternalUrl("https://bsky.app/profile/alice"))
    // RSS app URLs still count as external (that is the RN behaviour).
    #expect(URLHelpers.isExternalUrl("https://bsky.app/profile/alice/rss"))
  }

  @Test func isTrustedUrl() {
    #expect(URLHelpers.isTrustedUrl("https://bsky.app/profile/alice"))
    #expect(URLHelpers.isTrustedUrl("https://bsky.social"))
    #expect(URLHelpers.isTrustedUrl("https://sub.bsky.app/x"))
    #expect(URLHelpers.isTrustedUrl("/profile/alice"))
    #expect(URLHelpers.isTrustedUrl("#"))
    #expect(!URLHelpers.isTrustedUrl("https://example.com"))
  }

  @Test func bskyRecordUrlClassification() {
    #expect(URLHelpers.isBskyPostUrl("https://bsky.app/profile/alice/post/3k"))
    #expect(!URLHelpers.isBskyPostUrl("https://bsky.app/profile/alice"))
    #expect(URLHelpers.isBskyCustomFeedUrl("https://bsky.app/profile/alice/feed/3k"))
    #expect(URLHelpers.isBskyListUrl("https://bsky.app/profile/alice/lists/3k"))
    #expect(URLHelpers.isBskyStartUrl("https://bsky.app/start/alice/3k"))
    #expect(URLHelpers.isBskyStarterPackUrl("https://bsky.app/starter-pack/alice/3k"))
  }

  @Test func chatInviteCodes() {
    #expect(URLHelpers.getChatInviteCodeFromUrl("/chat/abcdefg") == "abcdefg")
    #expect(URLHelpers.getChatInviteCodeFromUrl("https://bsky.app/chat/abcdefg") == "abcdefg")
    #expect(URLHelpers.getChatInviteCodeFromUrl("/chat/abc") == nil)
    #expect(URLHelpers.isBskyChatInviteUrl("/chat/abcdefg"))
    #expect(!URLHelpers.isBskyChatInviteUrl("https://example.com"))
  }

  @Test func isBskyDownloadUrl() {
    #expect(URLHelpers.isBskyDownloadUrl("/download"))
    #expect(URLHelpers.isBskyDownloadUrl("/download?x=1"))
    #expect(!URLHelpers.isBskyDownloadUrl("/downloads"))
    #expect(!URLHelpers.isBskyDownloadUrl("https://example.com/download"))
  }

  @Test func convertBskyAppUrlIfNeeded() {
    #expect(
      URLHelpers.convertBskyAppUrlIfNeeded("https://bsky.app/profile/alice/post/3k")
        == "/profile/alice/post/3k")
    #expect(
      URLHelpers.convertBskyAppUrlIfNeeded("https://bsky.app/start/alice/3k")
        == "/starter-pack/alice/3k")
    #expect(
      URLHelpers.convertBskyAppUrlIfNeeded("https://go.bsky.app/abc")
        == "/starter-pack-short/abc")
    #expect(URLHelpers.convertBskyAppUrlIfNeeded("https://example.com") == "https://example.com")
  }

  // MARK: - Record URIs to app routes

  @Test func recordUriToHref() {
    #expect(
      URLHelpers.listUriToHref("at://did:plc:alice/app.bsky.graph.list/3k")
        == "/profile/did:plc:alice/lists/3k")
    #expect(URLHelpers.listUriToHref("notauri") == "")
    #expect(
      URLHelpers.feedUriToHref("at://did:plc:alice/app.bsky.feed.generator/3k")
        == "/profile/did:plc:alice/feed/3k")
  }

  @Test func postUriToRelativePath() {
    #expect(
      URLHelpers.postUriToRelativePath("at://did:plc:alice/app.bsky.feed.post/3k")
        == "/profile/did:plc:alice/post/3k")
    #expect(
      URLHelpers.postUriToRelativePath(
        "at://did:plc:alice/app.bsky.feed.post/3k", handle: "alice.test")
        == "/profile/alice.test/post/3k")
    // An invalid handle falls back to the authority.
    #expect(
      URLHelpers.postUriToRelativePath(
        "at://did:plc:alice/app.bsky.feed.post/3k", handle: "handle.invalid")
        == "/profile/did:plc:alice/post/3k")
    #expect(URLHelpers.postUriToRelativePath("notauri") == nil)
  }

  // MARK: - Link labels

  @Test func labelToDomain() {
    #expect(URLHelpers.labelToDomain("example.com") == "example.com")
    #expect(URLHelpers.labelToDomain("https://example.com/x") == "example.com")
    #expect(URLHelpers.labelToDomain("EXAMPLE.COM") == "example.com")
    #expect(URLHelpers.labelToDomain("foo bar") == nil)
  }

  @Test func isPossiblyAUrl() {
    #expect(URLHelpers.isPossiblyAUrl("http://example.com"))
    #expect(URLHelpers.isPossiblyAUrl("https://example.com"))
    #expect(URLHelpers.isPossiblyAUrl("example.com"))
    #expect(URLHelpers.isPossiblyAUrl("example.com/path"))
    #expect(!URLHelpers.isPossiblyAUrl("just some words"))
  }

  @Test func linkRequiresWarning() {
    // Relative URLs and `#` are trusted internal content.
    #expect(!URLHelpers.linkRequiresWarning(uri: "/profile/alice", label: "anything"))
    #expect(!URLHelpers.linkRequiresWarning(uri: "#", label: "anything"))
    // Unparseable uri warns.
    #expect(URLHelpers.linkRequiresWarning(uri: "notaurl", label: "example.com"))
    // External link with a mismatching label warns; matching does not.
    #expect(URLHelpers.linkRequiresWarning(uri: "https://evil.com/x", label: "example.com"))
    #expect(!URLHelpers.linkRequiresWarning(uri: "https://example.com/x", label: "example.com"))
    // External link with no parsable label warns.
    #expect(URLHelpers.linkRequiresWarning(uri: "https://example.com/x", label: "no spaces allowed"))
    // Trusted (app) link presented as another app's URL warns.
    #expect(URLHelpers.linkRequiresWarning(uri: "https://bsky.app/x", label: "evil.com"))
    // Trusted link with a non-URL label does not warn.
    #expect(!URLHelpers.linkRequiresWarning(uri: "https://bsky.app/x", label: "not a url"))
  }

  // MARK: - splitApexDomain

  @Test func splitApexDomain() {
    let simple = URLHelpers.splitApexDomain("example.com")
    #expect(simple.subdomain == "")
    #expect(simple.domain == "example.com")

    let withSub = URLHelpers.splitApexDomain("www.example.com")
    #expect(withSub.subdomain == "www.")
    #expect(withSub.domain == "example.com")

    let nested = URLHelpers.splitApexDomain("a.b.example.com")
    #expect(nested.subdomain == "a.b.")
    #expect(nested.domain == "example.com")

    // Multi-label public suffixes resolve to the right apex.
    let uk = URLHelpers.splitApexDomain("www.example.co.uk")
    #expect(uk.domain == "example.co.uk")

    // Unlisted hosts fall back to `["", hostname]`, matching psl.
    let unknown = URLHelpers.splitApexDomain("localhost")
    #expect(unknown.subdomain == "")
    #expect(unknown.domain == "localhost")
  }

  // MARK: - Proxying and short links

  @Test func createBskyAppAbsoluteUrl() {
    #expect(
      URLHelpers.createBskyAppAbsoluteUrl("/profile/alice") == "https://bsky.app/profile/alice")
    #expect(
      URLHelpers.createBskyAppAbsoluteUrl("profile/alice") == "https://bsky.app/profile/alice")
    #expect(
      URLHelpers.createBskyAppAbsoluteUrl("https://bsky.app/profile/alice")
        == "https://bsky.app/profile/alice")
  }

  @Test func createProxiedUrl() {
    #expect(
      URLHelpers.createProxiedUrl("https://example.com/a b")
        == "https://go.bsky.app/redirect?u=https%3A%2F%2Fexample.com%2Fa%20b")
    #expect(URLHelpers.createProxiedUrl("notaurl") == "notaurl")
    #expect(URLHelpers.createProxiedUrl("ftp://example.com/x") == "ftp://example.com/x")
  }

  @Test func shortLinks() {
    #expect(URLHelpers.isShortLink("https://go.bsky.app/abc"))
    #expect(!URLHelpers.isShortLink("https://example.com"))
    #expect(URLHelpers.shortLinkToHref("https://go.bsky.app/abc") == "/starter-pack-short/abc")
    #expect(URLHelpers.shortLinkToHref("https://go.bsky.app/a/b") == "https://go.bsky.app/a/b")
  }

  @Test func serviceAuthAud() {
    #expect(URLHelpers.getHostnameFromUrl("https://example.com/x") == "example.com")
    #expect(URLHelpers.getHostnameFromUrl("notaurl") == nil)
    #expect(URLHelpers.getServiceAuthAudFromUrl("https://example.com") == "did:web:example.com")
    #expect(URLHelpers.getServiceAuthAudFromUrl("notaurl") == nil)
  }

  @Test func definitelyUrl() {
    #expect(URLHelpers.definitelyUrl("example.com") == "https://example.com/")
    #expect(URLHelpers.definitelyUrl("https://example.com") == "https://example.com/")
    #expect(URLHelpers.definitelyUrl("foo.bar/baz?x=1") == "https://foo.bar/baz?x=1")
    #expect(URLHelpers.definitelyUrl("EXAMPLE.COM") == "https://example.com/")
    #expect(URLHelpers.definitelyUrl("example.com.") == nil)
    #expect(URLHelpers.definitelyUrl("localhost") == nil)
    #expect(URLHelpers.definitelyUrl("1.2.3.4") == nil)
  }
}
