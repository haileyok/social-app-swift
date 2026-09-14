import Foundation

/// The labeler the app reports to, for reasons and subjects that only Bluesky
/// is allowed to review (port of `api.moderation.did`).
public let bskyModerationDid = "did:plc:ar7c4by46qjdydhdevvrndac"

/// The result of classifying a raw subject for the report dialog.
///
/// Port of `ParsedReportSubject` in
/// `src/components/moderation/ReportDialog/types.ts`. The RN type is a
/// discriminated union over the raw lexicon views; Swift's enum makes the
/// discriminant explicit and forces every submit site to handle every shape.
public enum ParsedReportSubject: Sendable, Hashable {
  /// `app.bsky.actor.defs#profileViewBasic` / `profileView` /
  /// `profileViewDetailed`.
  case account(did: String, nsid: String)
  /// `app.bsky.actor.defs#statusView`, reported via its backing record.
  case status(uri: String, cid: String, nsid: String)
  /// `app.bsky.graph.defs#listView`.
  case list(uri: String, cid: String, nsid: String)
  /// `app.bsky.feed.defs#generatorView`.
  case feed(uri: String, cid: String, nsid: String)
  /// A starter pack view. `sourceType` records which `$type` it was parsed
  /// from, so a parse of RN's typo'd variant stays observable.
  case starterPack(uri: String, cid: String, nsid: String, sourceType: String)
  /// `app.bsky.feed.defs#postView` whose record is a `app.bsky.feed.post`.
  case post(uri: String, cid: String, nsid: String, attributes: PostReportAttributes)
  /// A single chat message.
  case convoMessage(convoId: String, message: ParsedConvoMessage)
  /// A whole conversation.
  case convo(convoId: String, did: String)

  /// The NSID of the record being reported, where one exists. Account subjects
  /// carry the profile NSID; chat subjects carry none.
  public var nsid: String? {
    switch self {
    case .account(_, let nsid), .status(_, _, let nsid), .list(_, _, let nsid),
      .feed(_, _, let nsid), .starterPack(_, _, let nsid, _), .post(_, _, let nsid, _):
      return nsid
    case .convoMessage, .convo:
      return nil
    }
  }

  /// The wire `$type` this subject was parsed from, i.e. `nsid` with a
  /// `#viewName` suffix. Used by the report dialog's `$type` display and by
  /// tests asserting which parse branch ran.
  public var sourceType: String {
    switch self {
    case .account: return "app.bsky.actor.defs#profileViewBasic"
    case .status: return "app.bsky.actor.defs#statusView"
    case .list: return "app.bsky.graph.defs#listView"
    case .feed: return "app.bsky.feed.defs#generatorView"
    case .starterPack(_, _, _, let sourceType): return sourceType
    case .post: return "app.bsky.feed.defs#postView"
    case .convoMessage: return "chat.bsky.convo.defs#messageView"
    case .convo: return "chat.bsky.convo.defs#convoView"
    }
  }
}

/// What a reported post contains, derived from its record and embed.
///
/// Port of the `attributes` object in `parseReportSubject`. These gate the
/// report form's extra questions (which kinds of content are being reported).
public struct PostReportAttributes: Sendable, Hashable {
  public var reply: Bool
  public var image: Bool
  public var video: Bool
  public var link: Bool
  public var quote: Bool

  public init(
    reply: Bool = false, image: Bool = false, video: Bool = false, link: Bool = false,
    quote: Bool = false
  ) {
    self.reply = reply
    self.image = image
    self.video = video
    self.link = link
    self.quote = quote
  }
}

/// A chat message referenced by a report.
public struct ParsedConvoMessage: Sendable, Hashable {
  public var messageId: String
  public var convoId: String
  /// The sender's did, taken from the message view.
  public var senderDid: String

  public init(messageId: String, convoId: String, senderDid: String) {
    self.messageId = messageId
    self.convoId = convoId
    self.senderDid = senderDid
  }
}
