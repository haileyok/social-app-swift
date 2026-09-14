import Foundation

import Lexicons
import SwiftAtproto

/// Wire `$type` values the report dialog can parse.
public enum ReportSubjectType {
  public static let profileViewBasic = "app.bsky.actor.defs#profileViewBasic"
  public static let profileView = "app.bsky.actor.defs#profileView"
  public static let profileViewDetailed = "app.bsky.actor.defs#profileViewDetailed"
  public static let statusView = "app.bsky.actor.defs#statusView"
  public static let listView = "app.bsky.graph.defs#listView"
  public static let generatorView = "app.bsky.feed.defs#generatorView"
  public static let starterPackView = "app.bsky.graph.defs#starterPackView"
  public static let starterPackViewBasic = "app.bsky.graph.defs#starterPackViewBasic"
  public static let postView = "app.bsky.feed.defs#postView"
  public static let convoView = "chat.bsky.convo.defs#convoView"
  public static let messageView = "chat.bsky.convo.defs#messageView"
}

/// Parses a raw subject into the shape the report dialog submits.
///
/// Port of `parseReportSubject` in
/// `src/components/moderation/ReportDialog/utils/parseReportSubject.ts`.
///
/// The RN version switches on the view's `$type` via `bsky.isType` before
/// falling back to structural checks (`'convoId' in subject`). This port takes
/// a ``ReportSubjectInput`` wrapper: types the app can decode from the wire
/// carry their own `$type`, and the chat shapes (which have no lexicon view in
/// the app) are supplied structurally.
///
/// - Note: **the starter-pack NSID.** RN reads
///   `app.bsky.graph.defs.starterPackView` for the check but then writes
///   `nsid: 'app.bsky.graph.starterPack'` into the parsed subject — a typo:
///   the real collection is `app.bsky.graph.starterpack` (lowercase `p`). This
///   parser emits the REAL NSID (that value is what reaches
///   `subjectCollections` filtering and the report body), and additionally
///   accepts RN's typo'd collection spelling if it ever appears as an input
///   `$type`, so reports queued by the older client still parse. See
///   ``ReportSubjectType`` and the tests in `ReportSubjectParsingTests`.
public enum ReportSubjectParser {

  /// The real starter-pack collection NSID, as it exists in the lexicon.
  public static let starterPackNsid = "app.bsky.graph.starterpack"

  /// RN's typo'd starter-pack NSID, accepted on parse for compatibility.
  public static let starterPackTypoNsid = "app.bsky.graph.starterPack"

  /// Parses a raw subject, or nil when it is not a reportable shape.
  public static func parse(_ subject: ReportSubjectInput) -> ParsedReportSubject? {
    switch subject {
    case .chatConvo(let convo):
      return .convo(convoId: convo.convoId, did: convo.did)

    case .chatMessage(let message):
      return .convoMessage(
        convoId: message.convoId,
        message: ParsedConvoMessage(
          messageId: message.message.id,
          convoId: message.convoId,
          senderDid: message.message.senderDid))

    case .profile(let did):
      return .account(did: did, nsid: "app.bsky.actor.profile")

    case .status(let uri, let cid):
      guard !uri.isEmpty, !cid.isEmpty else { return nil }
      return .status(uri: uri, cid: cid, nsid: "app.bsky.actor.status")

    case .list(let uri, let cid):
      return .list(uri: uri, cid: cid, nsid: "app.bsky.graph.list")

    case .feed(let uri, let cid):
      return .feed(uri: uri, cid: cid, nsid: "app.bsky.feed.generator")

    case .starterPack(let uri, let cid, let sourceType):
      // The NSID written into the parsed subject is always the REAL one; the
      // source `$type` is retained so a typo'd input stays observable.
      return .starterPack(
        uri: uri, cid: cid, nsid: starterPackNsid, sourceType: sourceType)

    case .post(let uri, let cid, let attributes):
      return .post(
        uri: uri, cid: cid, nsid: "app.bsky.feed.post", attributes: attributes)
    }
  }

  /// Parses a decoded `ProfileViewBasic` (or a wider profile view) as an
  /// account subject.
  public static func parseProfile(_ view: App.Bsky.ActorDefs_ProfileViewBasic) -> ParsedReportSubject {
    .account(did: view.did.rawValue, nsid: "app.bsky.actor.profile")
  }

  /// Parses a decoded `ProfileView` as an account subject.
  public static func parseProfile(_ view: App.Bsky.ActorDefs_ProfileView) -> ParsedReportSubject {
    .account(did: view.did.rawValue, nsid: "app.bsky.actor.profile")
  }

  /// Parses a decoded `ProfileViewDetailed` as an account subject.
  public static func parseProfile(
    _ view: App.Bsky.ActorDefs_ProfileViewDetailed
  ) -> ParsedReportSubject {
    .account(did: view.did.rawValue, nsid: "app.bsky.actor.profile")
  }

  /// Parses a decoded `StatusView`. RN requires both a uri and a cid, and
  /// returns undefined (not a partial subject) when either is missing.
  public static func parseStatus(
    _ view: App.Bsky.ActorDefs_StatusView
  ) -> ParsedReportSubject? {
    guard let uri = view.uri?.rawValue, let cid = view.cid?.rawValue, !cid.isEmpty else {
      return nil
    }
    return .status(uri: uri, cid: cid, nsid: "app.bsky.actor.status")
  }

  /// Parses a decoded `ListView`.
  ///
  /// - Note: `cid` is non-optional in the lexicon; an empty one makes the
  ///   strongRef unusable, so it is rejected.
  public static func parseList(_ view: App.Bsky.GraphDefs_ListView) -> ParsedReportSubject? {
    let cid = view.cid.rawValue
    guard !cid.isEmpty else { return nil }
    return .list(uri: view.uri.rawValue, cid: cid, nsid: "app.bsky.graph.list")
  }

  /// Parses a decoded `GeneratorView`.
  ///
  /// - Note: `cid` on a generator view is non-optional in the lexicon, but the
  ///   app can still be handed a view whose cid is empty; an empty cid makes
  ///   the strongRef unusable, so this returns nil.
  public static func parseFeed(
    _ view: App.Bsky.FeedDefs_GeneratorView
  ) -> ParsedReportSubject? {
    let cid = view.cid.rawValue
    guard !cid.isEmpty else { return nil }
    return .feed(uri: view.uri.rawValue, cid: cid, nsid: "app.bsky.feed.generator")
  }

  /// Parses a decoded `StarterPackView`.
  public static func parseStarterPack(
    _ view: App.Bsky.GraphDefs_StarterPackView
  ) -> ParsedReportSubject? {
    guard let cid = view.cid.rawValue as String?, !cid.isEmpty else { return nil }
    return .starterPack(
      uri: view.uri.rawValue, cid: cid, nsid: starterPackNsid,
      sourceType: ReportSubjectType.starterPackView)
  }

  /// Parses a decoded `PostView`, including its content attributes.
  ///
  /// RN derives `attributes.reply` from the RECORD (not the view) and the
  /// media attributes from the parsed embed; a post view whose record is not
  /// an `app.bsky.feed.post` is not reportable and yields nil.
  public static func parsePost(_ view: App.Bsky.FeedDefs_PostView) -> ParsedReportSubject? {
    return .post(
      uri: view.uri.rawValue, cid: view.cid.rawValue,
      nsid: "app.bsky.feed.post",
      attributes: postAttributes(record: view.record, embed: view.embed))
  }

  /// Derives the report attributes from a post's record and embed.
  ///
  /// Split out so the embed-shape table can be tested independently of the
  /// lexicon view construction. Mirrors RN's `bsky.post.parseEmbed` switch.
  public static func postAttributes(
    record: UnknownATPValue,
    embed: App.Bsky.FeedDefs_PostView_Embed?
  ) -> PostReportAttributes {
    var attributes = PostReportAttributes()
    if case .record(let recordValue) = record, let post = recordValue as? App.Bsky.FeedPost {
      attributes.reply = post.reply != nil
    }
    guard let embed else { return attributes }

    switch embed {
    case .embedImagesView, .embedGalleryView:
      attributes.image = true
    case .embedVideoView:
      attributes.video = true
    case .embedExternalView:
      attributes.link = true
    case .embedRecordView:
      attributes.quote = true
    case .embedRecordWithMediaView(let view):
      // RN: quote for a record-with-media whose view is a post; media flags
      // from the inner media union.
      attributes.quote = true
      switch view.media {
      case .embedImagesView, .embedGalleryView:
        attributes.image = true
      case .embedVideoView:
        attributes.video = true
      case .embedExternalView:
        attributes.link = true
      case ._other:
        break
      }
    case ._other:
      break
    }
    return attributes
  }
}

/// A raw subject handed to ``ReportSubjectParser``.
///
/// RN parses the *view* objects directly. The Swift port keeps the same
/// branches but expresses the chat shapes, which have no generated view type in
/// this app, as their own cases.
public enum ReportSubjectInput: Sendable {
  case chatConvo(ChatConvoRef)
  case chatMessage(ChatMessageRef)
  case profile(did: String)
  case status(uri: String, cid: String)
  case list(uri: String, cid: String)
  case feed(uri: String, cid: String)
  case starterPack(uri: String, cid: String, sourceType: String)
  case post(uri: String, cid: String, attributes: PostReportAttributes)
}

/// A chat conversation reference (RN's `ReportSubjectConvo`).
public struct ChatConvoRef: Sendable, Hashable {
  public var convoId: String
  public var did: String

  public init(convoId: String, did: String) {
    self.convoId = convoId
    self.did = did
  }
}

/// A chat message reference (RN's `ReportSubjectConvoMessage`).
public struct ChatMessageRef: Sendable {
  public var convoId: String
  public var message: ChatMessage

  public init(convoId: String, message: ChatMessage) {
    self.convoId = convoId
    self.message = message
  }

  /// The minimal message shape the report body needs, so the package does not
  /// depend on the chat lexicon module.
  public struct ChatMessage: Sendable {
    public var id: String
    public var senderDid: String

    public init(id: String, senderDid: String) {
      self.id = id
      self.senderDid = senderDid
    }
  }
}
