import Foundation
import SwiftAtproto
@testable import Domain
@testable import Lexicons

/// Fixture builders shared by the Domain test suites.
enum Fixtures {

  /// An ISO-8601 timestamp the lexicon `FormatString<Date>` accepts.
  static let defaultDate = "2026-08-31T00:00:00.000Z"

  static func profile(did: String = "did:plc:alice", handle: String = "alice.test")
    -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<SwiftAtproto.DID>(rawValue: did),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle)
    )
  }

  static func feedPostRecord(
    text: String = "text",
    reply: App.Bsky.FeedPost_ReplyRef? = nil,
    langs: [String]? = nil
  ) -> App.Bsky.FeedPost {
    App.Bsky.FeedPost(
      createdAt: FormatString<Date>(rawValue: defaultDate),
      langs: langs?.map { FormatString<SwiftAtproto.Language>(rawValue: $0) },
      reply: reply,
      text: text
    )
  }

  /// A `post` record reply ref, for marking a post as a reply.
  static func recordReply(parent: String, root: String) -> App.Bsky.FeedPost_ReplyRef {
    App.Bsky.FeedPost_ReplyRef(
      parent: Com.Atproto.RepoStrongRef(
        cid: FormatString<LexLink>(rawValue: "cid"),
        uri: FormatString<ATURI>(rawValue: parent)),
      root: Com.Atproto.RepoStrongRef(
        cid: FormatString<LexLink>(rawValue: "cid"),
        uri: FormatString<ATURI>(rawValue: root))
    )
  }

  /// A post view identified by `id` under alice's DID.
  static func post(
    _ id: String,
    author: App.Bsky.ActorDefs_ProfileViewBasic? = nil,
    record: App.Bsky.FeedPost? = nil,
    embed: App.Bsky.FeedDefs_PostView_Embed? = nil,
    threadMuted: Bool? = nil,
    likeCount: Int? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    let viewer = threadMuted.map { App.Bsky.FeedDefs_ViewerState(threadMuted: $0) }
    return App.Bsky.FeedDefs_PostView(
      author: author ?? profile(),
      cid: FormatString<LexLink>(rawValue: id),
      embed: embed,
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      likeCount: likeCount,
      record: .record(record ?? feedPostRecord(text: id)),
      uri: FormatString<ATURI>(rawValue: uri(id)),
      viewer: viewer
    )
  }

  static func uri(_ id: String, did: String = "did:plc:alice") -> String {
    "at://\(did)/app.bsky.feed.post/\(id)"
  }

  /// A `feedViewPost` with optional reply context and numbering.
  static func feedViewPost(
    post postView: App.Bsky.FeedDefs_PostView,
    reply: App.Bsky.FeedDefs_ReplyRef? = nil,
    reason: App.Bsky.FeedDefs_FeedViewPost_Reason? = nil,
    opThreadPostIndex: Int? = nil,
    opThreadPostCount: Int? = nil,
    feedContext: String? = nil,
    reqId: String? = nil
  ) -> FeedViewPost {
    FeedViewPost(
      post: postView,
      reply: reply,
      reason: reason,
      feedContext: feedContext,
      reqId: reqId,
      opThreadPostIndex: opThreadPostIndex,
      opThreadPostCount: opThreadPostCount
    )
  }

  /// A `#reasonRepost` whose `indexedAt` drives the slice key.
  static func repostReason(by: App.Bsky.ActorDefs_ProfileViewBasic? = nil, indexedAt: String? = nil)
    -> App.Bsky.FeedDefs_FeedViewPost_Reason {
    .feedDefsReasonRepost(
      App.Bsky.FeedDefs_ReasonRepost(
        by: by ?? profile(did: "did:plc:reposter", handle: "reposter.test"),
        indexedAt: FormatString<Date>(rawValue: indexedAt ?? defaultDate)))
  }

  static func replyRef(
    parent: App.Bsky.FeedDefs_ReplyRef_Parent,
    root: App.Bsky.FeedDefs_ReplyRef_Root,
    grandparentAuthor: App.Bsky.ActorDefs_ProfileViewBasic? = nil
  ) -> App.Bsky.FeedDefs_ReplyRef {
    App.Bsky.FeedDefs_ReplyRef(
      grandparentAuthor: grandparentAuthor, parent: parent, root: root)
  }

  static func postViewReply(_ view: App.Bsky.FeedDefs_PostView) -> App.Bsky.FeedDefs_ReplyRef_Parent {
    .feedDefsPostView(view)
  }

  static func postViewRoot(_ view: App.Bsky.FeedDefs_PostView) -> App.Bsky.FeedDefs_ReplyRef_Root {
    .feedDefsPostView(view)
  }

  /// A quote embed, which makes a slice `isQuotePost`.
  static func quoteEmbed() -> App.Bsky.FeedDefs_PostView_Embed {
    .embedRecordView(
      App.Bsky.EmbedRecord_View(
        record: .embedRecordViewRecord(
          App.Bsky.EmbedRecord_ViewRecord(
            author: profile(),
            cid: FormatString<LexLink>(rawValue: "cid"),
            indexedAt: FormatString<Date>(rawValue: defaultDate),
            uri: FormatString<ATURI>(rawValue: uri("quoted")),
            value: .record(feedPostRecord(text: "quoted"))))))
  }
}
