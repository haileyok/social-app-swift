import Foundation
import Testing

@testable import StarterPacksLogic

/// Asserts the URI, share-link and referrer builders.
///
/// The values are the exact strings RN produces, so a shared link and an
/// in-app navigation agree byte for byte.
@Suite("StarterPackURI")
struct StarterPackURITests {
  @Test("an at:// pack URI parses to its authority and rkey")
  func parseAtURI() {
    let parsed = StarterPackURI.parse("at://did:plc:qrllvid7s54k4hnwtqxwetrf/app.bsky.graph.starterpack/3l4poszxde32k")
    #expect(parsed == ParsedStarterPackURI(name: "did:plc:qrllvid7s54k4hnwtqxwetrf", rkey: "3l4poszxde32k"))
  }

  @Test("a bsky.app starter-pack URL parses to its handle and rkey")
  func parseHttpStarterPackURL() {
    let parsed = StarterPackURI.parse("https://bsky.app/starter-pack/joshuajfriedman.com/3l4poszxde32k")
    #expect(parsed == ParsedStarterPackURI(name: "joshuajfriedman.com", rkey: "3l4poszxde32k"))
  }

  @Test("the legacy /start/ web path parses the same way")
  func parseLegacyStartPath() {
    let parsed = StarterPackURI.parse("https://bsky.app/start/joshuajfriedman.com/3l4poszxde32k")
    #expect(parsed == ParsedStarterPackURI(name: "joshuajfriedman.com", rkey: "3l4poszxde32k"))
  }

  @Test("an at:// URI in the wrong collection is rejected")
  func parseWrongCollection() {
    #expect(StarterPackURI.parse("at://did:plc:x/app.bsky.feed.post/3abc") == nil)
  }

  @Test("an at:// pack URI with no rkey is rejected")
  func parseMissingRkey() {
    #expect(StarterPackURI.parse("at://did:plc:x/app.bsky.graph.starterpack") == nil)
  }

  @Test("an http path with too many segments is rejected")
  func parseTooManySegments() {
    #expect(StarterPackURI.parse("https://bsky.app/starter-pack/a/b/c") == nil)
  }

  @Test("an http path under an unrelated route is rejected")
  func parseWrongPath() {
    #expect(StarterPackURI.parse("https://bsky.app/profile/a/b") == nil)
  }

  @Test("nil, empty and non-URL inputs are rejected")
  func parseNilAndEmpty() {
    #expect(StarterPackURI.parse(nil) == nil)
    #expect(StarterPackURI.parse("") == nil)
    #expect(StarterPackURI.parse("not a uri") == nil)
  }

  @Test("an http URI converts to its at:// form and an at:// URI passes through")
  func httpToAtURI() {
    #expect(
      StarterPackURI.httpToAtURI("https://bsky.app/starter-pack/joshuajfriedman.com/3l4poszxde32k")
        == "at://joshuajfriedman.com/app.bsky.graph.starterpack/3l4poszxde32k")
    #expect(
      StarterPackURI.httpToAtURI("at://did:plc:x/app.bsky.graph.starterpack/3abc")
        == "at://did:plc:x/app.bsky.graph.starterpack/3abc")
    #expect(StarterPackURI.httpToAtURI(nil) == nil)
  }

  @Test("the record URI is built from a DID and rkey")
  func makeURI() {
    #expect(
      StarterPackURI.makeURI(did: "did:plc:author", rkey: "3abc")
        == "at://did:plc:author/app.bsky.graph.starterpack/3abc")
  }

  @Test("the app share link uses the handle, not the DID")
  func appShareLink() {
    #expect(
      StarterPackURI.appShareLink(name: "joshuajfriedman.com", rkey: "3l4poszxde32k")
        == "https://bsky.app/start/joshuajfriedman.com/3l4poszxde32k")
  }

  @Test("the OG card URL uses the creator's DID")
  func ogCardURL() {
    #expect(
      StarterPackURI.ogCardURL(creatorDID: "did:plc:qrllvid7s54k4hnwtqxwetrf", rkey: "3l4poszxde32k")
        == "https://ogcard.cdn.bsky.app/start/did:plc:qrllvid7s54k4hnwtqxwetrf/3l4poszxde32k")
  }

  @Test("a /start/ path rewrites to /starter-pack/")
  func startToStarterPackPath() {
    #expect(
      StarterPackURI.startToStarterPackPath("https://bsky.app/start/a/3abc")
        == "https://bsky.app/starter-pack/a/3abc")
  }

  @Test("the Google Play referrer carries the pack in utm_content")
  func googlePlayURI() {
    #expect(
      StarterPackURI.googlePlayURI(name: "haileyok.com", rkey: "3abc")
        == "https://play.google.com/store/apps/details?id=xyz.blueskyweb.app&referrer=utm_source%3Dbluesky%26utm_medium%3Dstarterpack%26utm_content%3Dstarterpack_haileyok.com_3abc"
    )
  }

  @Test("the Google Play referrer is nil without a name or rkey")
  func googlePlayURIRejectsEmpty() {
    #expect(StarterPackURI.googlePlayURI(name: "", rkey: "3abc") == nil)
    #expect(StarterPackURI.googlePlayURI(name: "a", rkey: "") == nil)
  }

  @Test("an Android install referrer recovers the pack URI")
  func androidReferrer() {
    #expect(
      StarterPackURI.fromAndroidReferrer(
        "utm_source=bluesky&utm_medium=starterpack&utm_content=starterpack_haileyok.com_3abc")
        == "at://haileyok.com/app.bsky.graph.starterpack/3abc")
  }

  @Test("a referrer from another source is rejected")
  func androidReferrerWrongSource() {
    #expect(
      StarterPackURI.fromAndroidReferrer(
        "utm_source=other&utm_content=starterpack_a_3abc") == nil)
  }

  @Test("a referrer with the wrong content shape is rejected")
  func androidReferrerWrongShape() {
    #expect(StarterPackURI.fromAndroidReferrer("utm_source=bluesky&utm_content=other_a_3abc") == nil)
    #expect(StarterPackURI.fromAndroidReferrer("utm_source=bluesky&utm_content=starterpack_a") == nil)
    #expect(StarterPackURI.fromAndroidReferrer("") == nil)
  }

  @Test("a record key is recovered from any at:// URI")
  func parseRecordRkey() {
    #expect(StarterPackURI.parseRecordRkey("at://did:plc:x/app.bsky.graph.list/3abc") == "3abc")
    #expect(StarterPackURI.parseRecordRkey("at://did:plc:x/app.bsky.graph.list") == nil)
    #expect(StarterPackURI.parseRecordRkey("https://example.com/") == nil)
  }
}

/// Asserts the share and QR data builders.
@Suite("StarterPackShare")
struct StarterPackShareTests {
  @Test("share data derives link, card URL and filename from the pack")
  func shareData() {
    let detail = StarterPackViewBuilder.detail(
      Fixtures.packView(name: "Bluesky for Art History"))
    let data = StarterPackShare.shareData(detail, shortLink: "https://go.bsky.app/abc")

    #expect(data.shareLink == "https://go.bsky.app/abc")
    #expect(data.longLink == "https://bsky.app/start/joshuajfriedman.com/3l4poszxde32k")
    #expect(
      data.imageURL
        == "https://ogcard.cdn.bsky.app/start/did:plc:author/3l4poszxde32k")
    #expect(data.qrDownloadFilename == "Bluesky_for_Art_History_Share_Card.png")
    #expect(data.isReady)
  }

  @Test("share data is not ready until the short link resolves")
  func shareDataNotReady() {
    let detail = StarterPackViewBuilder.detail(Fixtures.packView())
    let data = StarterPackShare.shareData(detail)
    #expect(data.isReady == false)
    #expect(StarterPackShare.shareURL(data) == nil)
  }

  @Test("the QR download filename replaces only spaces")
  func qrFilename() {
    #expect(StarterPackShare.qrDownloadFilename(packName: "a b-c.d") == "a_b-c.d_Share_Card.png")
  }

  @Test("a pack with a creator handle and rkey can be shared")
  func canShare() {
    let detail = StarterPackViewBuilder.detail(Fixtures.packView())
    #expect(StarterPackShare.canShare(detail))
  }

  @Test("a pack with no rkey cannot be shared")
  func cannotShareWithoutRkey() {
    let view = Fixtures.packView(rkey: "")
    let detail = StarterPackViewBuilder.detail(view)
    #expect(StarterPackShare.canShare(detail) == false)
  }
}
