import Foundation
import Lexicons
import SwiftAtproto
import Testing

@testable import ModerationUILogic

/// Port of the parse behaviour in
/// `src/components/moderation/ReportDialog/utils/parseReportSubject.ts`.
///
/// The RN file has no unit test of its own; these cases are derived from the
/// `bsky.isType` branches it checks, plus the typo-tolerance requirement in the
/// task brief.
@Suite("Report subject parsing")
struct ReportSubjectParsingTests {

  // MARK: - Account

  @Test("a profile view basic parses as an account subject")
  func accountFromProfileViewBasic() {
    let parsed = ReportSubjectParser.parseProfile(Fixtures.profileViewBasic("did:plc:a"))
    #expect(parsed == .account(did: "did:plc:a", nsid: "app.bsky.actor.profile"))
  }

  @Test("a profile view parses as an account subject")
  func accountFromProfileView() {
    let parsed = ReportSubjectParser.parseProfile(Fixtures.profileView("did:plc:a"))
    #expect(parsed == .account(did: "did:plc:a", nsid: "app.bsky.actor.profile"))
  }

  @Test("a profile view detailed parses as an account subject")
  func accountFromProfileViewDetailed() {
    let view = App.Bsky.ActorDefs_ProfileViewDetailed(
      did: FormatString<DID>(rawValue: "did:plc:detailed"),
      handle: FormatString<Handle>(rawValue: "detailed.test"))
    let parsed = ReportSubjectParser.parseProfile(view)
    #expect(parsed == .account(did: "did:plc:detailed", nsid: "app.bsky.actor.profile"))
  }

  @Test("account subjects carry the profile NSID, not the view NSID")
  func accountNsidIsTheRecordNsid() {
    let parsed = ReportSubjectParser.parseProfile(Fixtures.profileViewBasic("did:plc:a"))
    #expect(parsed.nsid == "app.bsky.actor.profile")
  }

  // MARK: - Status

  @Test("a status view with a uri and cid parses")
  func statusParses() {
    let parsed = ReportSubjectParser.parseStatus(Fixtures.statusView())
    #expect(
      parsed == .status(
        uri: "at://did:plc:actor/app.bsky.actor.status/self", cid: "bafystatus",
        nsid: "app.bsky.actor.status"))
  }

  @Test("a status view without a uri is not reportable")
  func statusWithoutUriIsNil() {
    #expect(ReportSubjectParser.parseStatus(Fixtures.statusView(uri: nil)) == nil)
  }

  @Test("a status view without a cid is not reportable")
  func statusWithoutCidIsNil() {
    #expect(ReportSubjectParser.parseStatus(Fixtures.statusView(cid: nil)) == nil)
  }

  // MARK: - Other record-backed views

  @Test("a list view parses with the list NSID")
  func listParses() {
    let parsed = ReportSubjectParser.parseList(
      Fixtures.listView(uri: "at://did:plc:a/app.bsky.graph.list/1"))
    #expect(parsed?.nsid == "app.bsky.graph.list")
    #expect(parsed == .list(uri: "at://did:plc:a/app.bsky.graph.list/1", cid: "bafylist", nsid: "app.bsky.graph.list"))
  }

  @Test("a generator view parses with the generator NSID")
  func feedParses() {
    let parsed = ReportSubjectParser.parseFeed(
      Fixtures.generatorView(uri: "at://did:plc:a/app.bsky.feed.generator/1"))
    #expect(parsed?.nsid == "app.bsky.feed.generator")
  }

  // MARK: - Starter pack NSID typo

  @Test("a starter pack parses with the REAL graph.starterpack NSID")
  func starterPackUsesRealNsid() {
    let parsed = ReportSubjectParser.parseStarterPack(
      Fixtures.starterPackView(uri: "at://did:plc:a/app.bsky.graph.starterpack/1"))
    #expect(parsed?.nsid == "app.bsky.graph.starterpack")
  }

  @Test("a starter pack records which source $type it came from")
  func starterPackSourceType() {
    let parsed = ReportSubjectParser.parseStarterPack(
      Fixtures.starterPackView(uri: "at://did:plc:a/app.bsky.graph.starterpack/1"))
    #expect(parsed?.sourceType == "app.bsky.graph.defs#starterPackView")
  }

  @Test("the typo'd starter pack collection is accepted as an input $type")
  func starterPackTypoNsidAcceptedOnParse() {
    // RN wrote `app.bsky.graph.starterPack` into the parsed subject. A subject
    // handed over with that spelling must still parse, and must be normalized
    // onto the real NSID.
    let parsed = ReportSubjectParser.parse(
      .starterPack(
        uri: "at://did:plc:a/app.bsky.graph.starterpack/1", cid: "bafysp",
        sourceType: ReportSubjectParser.starterPackTypoNsid))
    #expect(parsed?.nsid == ReportSubjectParser.starterPackNsid)
    #expect(parsed?.sourceType == "app.bsky.graph.starterPack")
  }

  @Test("the real and typo'd starter pack NSIDs differ only in case")
  func starterPackNsidConstants() {
    #expect(ReportSubjectParser.starterPackNsid == "app.bsky.graph.starterpack")
    #expect(ReportSubjectParser.starterPackTypoNsid == "app.bsky.graph.starterPack")
    #expect(
      ReportSubjectParser.starterPackNsid.lowercased()
        == ReportSubjectParser.starterPackTypoNsid.lowercased())
  }

  // MARK: - Posts

  @Test("a post view parses with the post NSID")
  func postParses() {
    let parsed = ReportSubjectParser.parsePost(
      Fixtures.postView(uri: "at://did:plc:a/app.bsky.feed.post/1"))
    #expect(parsed?.nsid == "app.bsky.feed.post")
  }

  @Test("a reply post reports the reply attribute")
  func postReplyAttribute() {
    let view = Fixtures.postView(uri: "at://did:plc:a/app.bsky.feed.post/1", reply: true)
    guard case .post(_, _, _, let attributes) = ReportSubjectParser.parsePost(view)! else {
      Issue.record("expected a post subject")
      return
    }
    #expect(attributes.reply)
  }

  @Test("a top-level post does not report the reply attribute")
  func postNonReplyAttribute() {
    let view = Fixtures.postView(uri: "at://did:plc:a/app.bsky.feed.post/1")
    guard case .post(_, _, _, let attributes) = ReportSubjectParser.parsePost(view)! else {
      Issue.record("expected a post subject")
      return
    }
    #expect(!attributes.reply)
  }

  @Test("an image embed sets the image attribute")
  func postImageAttribute() {
    let embed = App.Bsky.FeedDefs_PostView_Embed.embedImagesView(
      App.Bsky.EmbedImages_View(images: []))
    let attributes = ReportSubjectParser.postAttributes(
      record: postRecord(), embed: embed)
    #expect(attributes.image)
    #expect(!attributes.video)
    #expect(!attributes.link)
    #expect(!attributes.quote)
  }

  @Test("a gallery embed sets the image attribute")
  func postGalleryAttribute() {
    let embed = App.Bsky.FeedDefs_PostView_Embed.embedGalleryView(
      App.Bsky.EmbedGallery_View(items: []))
    #expect(ReportSubjectParser.postAttributes(record: postRecord(), embed: embed).image)
  }

  @Test("a video embed sets the video attribute")
  func postVideoAttribute() {
    let embed = App.Bsky.FeedDefs_PostView_Embed.embedVideoView(
      App.Bsky.EmbedVideo_View(cid: FormatString<LexLink>(rawValue: "bafyvid"), playlist: FormatString<URI>(rawValue: "https://video.test/1")))
    #expect(ReportSubjectParser.postAttributes(record: postRecord(), embed: embed).video)
  }

  @Test("an external embed sets the link attribute")
  func postLinkAttribute() {
    let embed = App.Bsky.FeedDefs_PostView_Embed.embedExternalView(
      App.Bsky.EmbedExternal_View(
        external: App.Bsky.EmbedExternal_ViewExternal(
          description: "d", title: "t", uri: FormatString<URI>(rawValue: "https://x.test"))))
    let attributes = ReportSubjectParser.postAttributes(record: postRecord(), embed: embed)
    #expect(attributes.link)
    #expect(!attributes.image)
  }

  @Test("a record embed sets the quote attribute")
  func postQuoteAttribute() {
    let embed = App.Bsky.FeedDefs_PostView_Embed.embedRecordView(
      App.Bsky.EmbedRecord_View(record: ._other(UnknownRecord(type: "unknown"))))
    #expect(ReportSubjectParser.postAttributes(record: postRecord(), embed: embed).quote)
  }

  @Test("a record-with-media post sets quote and the media flag together")
  func postWithMediaAttributes() {
    let media = App.Bsky.EmbedRecordWithMedia_View_Media.embedImagesView(
      App.Bsky.EmbedImages_View(images: []))
    let embed = App.Bsky.FeedDefs_PostView_Embed.embedRecordWithMediaView(
      App.Bsky.EmbedRecordWithMedia_View(
        media: media,
        record: App.Bsky.EmbedRecord_View(record: ._other(UnknownRecord(type: "unknown")))))
    let attributes = ReportSubjectParser.postAttributes(record: postRecord(), embed: embed)
    #expect(attributes.quote)
    #expect(attributes.image)
  }

  @Test("a post with no embed sets no media attributes")
  func postNoEmbed() {
    let attributes = ReportSubjectParser.postAttributes(record: postRecord(), embed: nil)
    #expect(!attributes.image && !attributes.video && !attributes.link && !attributes.quote)
  }

  // MARK: - Chat

  @Test("a convo parses as a convo subject")
  func convoParses() {
    let parsed = ReportSubjectParser.parse(
      .chatConvo(ChatConvoRef(convoId: "c1", did: "did:plc:a")))
    #expect(parsed == .convo(convoId: "c1", did: "did:plc:a"))
  }

  @Test("a convo message parses with the sender did")
  func convoMessageParses() {
    let parsed = ReportSubjectParser.parse(
      .chatMessage(
        ChatMessageRef(
          convoId: "c1",
          message: ChatMessageRef.ChatMessage(id: "m1", senderDid: "did:plc:sender"))))
    #expect(
      parsed
        == .convoMessage(
          convoId: "c1",
          message: ParsedConvoMessage(messageId: "m1", convoId: "c1", senderDid: "did:plc:sender")))
  }

  @Test("chat subjects carry no record NSID")
  func chatSubjectsHaveNoNsid() {
    #expect(ReportSubjectParser.parse(.chatConvo(ChatConvoRef(convoId: "c", did: "d")))?.nsid == nil)
  }

  // MARK: - Source types

  @Test("each parsed subject reports the $type it came from")
  func sourceTypes() {
    #expect(
      ReportSubjectParser.parse(.profile(did: "did:plc:a"))?.sourceType
        == "app.bsky.actor.defs#profileViewBasic")
    #expect(
      ReportSubjectParser.parse(.status(uri: "u", cid: "c"))?.sourceType
        == "app.bsky.actor.defs#statusView")
    #expect(
      ReportSubjectParser.parse(.list(uri: "u", cid: "c"))?.sourceType
        == "app.bsky.graph.defs#listView")
    #expect(
      ReportSubjectParser.parse(.feed(uri: "u", cid: "c"))?.sourceType
        == "app.bsky.feed.defs#generatorView")
    #expect(
      ReportSubjectParser.parse(.post(uri: "u", cid: "c", attributes: PostReportAttributes()))?
        .sourceType == "app.bsky.feed.defs#postView")
  }

  /// A record fixture with no reply, for the embed-attribute cases.
  private func postRecord() -> UnknownATPValue {
    .record(Fixtures.postRecord(createdAt: "2026-01-01T00:00:00.000Z", reply: false))
  }
}
