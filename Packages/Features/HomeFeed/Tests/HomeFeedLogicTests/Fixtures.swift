import Foundation
import Lexicons
import Preferences
import SwiftAtproto

@testable import HomeFeedLogic

/// Fixture builders for the home-feed suites.
enum Fixtures {
  /// An ISO-8601 timestamp the lexicon `FormatString<Date>` accepts.
  static let defaultDate = "2026-08-31T00:00:00.000Z"

  static func profile(did: String = "did:plc:alice", handle: String = "alice.test")
    -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<SwiftAtproto.DID>(rawValue: did),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle))
  }

  /// A profile the viewer is following, so reply filters admit it.
  static func followedProfile(handle: String) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<SwiftAtproto.DID>(rawValue: "did:plc:\(handle)"),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: "\(handle).test"),
      viewer: App.Bsky.ActorDefs_ViewerState(
        following: FormatString<ATURI>(rawValue: "at://did:plc:alice/app.bsky.graph.follow/1")))
  }

  static func feedPostRecord(
    text: String = "text", reply: App.Bsky.FeedPost_ReplyRef? = nil, langs: [String]? = nil
  ) -> App.Bsky.FeedPost {
    App.Bsky.FeedPost(
      createdAt: FormatString<Date>(rawValue: defaultDate),
      langs: langs?.map { FormatString<SwiftAtproto.Language>(rawValue: $0) },
      reply: reply,
      text: text)
  }

  static func uri(_ id: String, did: String = "did:plc:alice") -> String {
    "at://\(did)/app.bsky.feed.post/\(id)"
  }

  /// A post view identified by `id`.
  static func post(
    _ id: String,
    author: App.Bsky.ActorDefs_ProfileViewBasic? = nil,
    record: App.Bsky.FeedPost? = nil,
    threadMuted: Bool? = nil,
    embed: App.Bsky.FeedDefs_PostView_Embed? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    let viewer = threadMuted.map { App.Bsky.FeedDefs_ViewerState(threadMuted: $0) }
    return App.Bsky.FeedDefs_PostView(
      author: author ?? profile(),
      cid: FormatString<LexLink>(rawValue: id),
      embed: embed,
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      record: .record(record ?? feedPostRecord(text: id)),
      uri: FormatString<ATURI>(rawValue: uri(id)),
      viewer: viewer)
  }

  /// A reply post view, whose parent and root are hydrated post views.
  static func reply(
    _ id: String,
    parent: App.Bsky.FeedDefs_PostView,
    root: App.Bsky.FeedDefs_PostView? = nil,
    author: App.Bsky.ActorDefs_ProfileViewBasic? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    let rootView = root ?? parent
    let record = feedPostRecord(
      text: id,
      reply: App.Bsky.FeedPost_ReplyRef(
        parent: Com.Atproto.RepoStrongRef(
          cid: FormatString<LexLink>(rawValue: "cid"),
          uri: FormatString<ATURI>(rawValue: parent.uri.rawValue)),
        root: Com.Atproto.RepoStrongRef(
          cid: FormatString<LexLink>(rawValue: "cid"),
          uri: FormatString<ATURI>(rawValue: rootView.uri.rawValue))))
    return App.Bsky.FeedDefs_PostView(
      author: author ?? profile(),
      cid: FormatString<LexLink>(rawValue: id),
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      record: .record(record),
      uri: FormatString<ATURI>(rawValue: uri(id)))
  }

  static func replyRef(
    parent: App.Bsky.FeedDefs_PostView, root: App.Bsky.FeedDefs_PostView? = nil
  ) -> App.Bsky.FeedDefs_ReplyRef {
    App.Bsky.FeedDefs_ReplyRef(
      parent: .feedDefsPostView(parent),
      root: .feedDefsPostView(root ?? parent))
  }

  /// A `feedViewPost` around `postView`.
  static func feedViewPost(
    _ postView: App.Bsky.FeedDefs_PostView,
    reply: App.Bsky.FeedDefs_ReplyRef? = nil,
    reason: App.Bsky.FeedDefs_FeedViewPost_Reason? = nil,
    feedContext: String? = nil,
    reqId: String? = nil
  ) -> App.Bsky.FeedDefs_FeedViewPost {
    App.Bsky.FeedDefs_FeedViewPost(
      feedContext: feedContext,
      post: postView,
      reason: reason,
      reply: reply,
      reqId: reqId)
  }

  /// A plain top-level post as a feed item.
  static func item(_ id: String, feedContext: String? = nil, reqId: String? = nil)
    -> App.Bsky.FeedDefs_FeedViewPost {
    feedViewPost(post(id), feedContext: feedContext, reqId: reqId)
  }

  /// A `#reasonRepost` whose `indexedAt` drives the slice key.
  static func repostReason(indexedAt: String? = nil)
    -> App.Bsky.FeedDefs_FeedViewPost_Reason {
    .feedDefsReasonRepost(
      App.Bsky.FeedDefs_ReasonRepost(
        by: profile(did: "did:plc:reposter", handle: "reposter.test"),
        indexedAt: FormatString<Date>(rawValue: indexedAt ?? defaultDate)))
  }

  static func generatorView(
    uri: String = "at://did:plc:feeds/app.bsky.feed.generator/cool",
    displayName: String = "Cool Feed",
    creatorHandle: String = "feedmaker.test"
  ) -> App.Bsky.FeedDefs_GeneratorView {
    App.Bsky.FeedDefs_GeneratorView(
      cid: FormatString<LexLink>(rawValue: "gencid"),
      creator: App.Bsky.ActorDefs_ProfileView(
        did: FormatString<SwiftAtproto.DID>(rawValue: "did:plc:feeds"),
        handle: FormatString<SwiftAtproto.Handle>(rawValue: creatorHandle)),
      did: FormatString<SwiftAtproto.DID>(rawValue: "did:plc:feeds"),
      displayName: displayName,
      indexedAt: FormatString<Date>(rawValue: defaultDate),
      uri: FormatString<ATURI>(rawValue: uri))
  }

  static func skeletonItem(
    _ uri: String, feedContext: String? = nil
  ) -> App.Bsky.FeedDefs_SkeletonFeedPost {
    App.Bsky.FeedDefs_SkeletonFeedPost(
      feedContext: feedContext,
      post: FormatString<ATURI>(rawValue: uri))
  }

  /// A saved-feed preference object, as the v2 pref stores it.
  static func savedFeedPref(
    id: String, type: String, value: String, pinned: Bool
  ) -> PrefObject {
    PrefObject(fields: [
      "$type": JSONValue("app.bsky.actor.defs#savedFeed"),
      "id": JSONValue(id),
      "type": JSONValue(type),
      "value": JSONValue(value),
      "pinned": JSONValue(pinned),
    ])
  }

  /// The timeline saved-feed entry.
  static func timelineEntry(pinned: Bool = true) -> SavedFeedEntry {
    SavedFeedEntry(id: "timeline-id", type: .timeline, value: "following", pinned: pinned)
  }

  /// A generator saved-feed entry.
  static func feedEntry(
    _ uri: String = "at://did:plc:feeds/app.bsky.feed.generator/cool",
    pinned: Bool = true,
    id: String = "feed-id"
  ) -> SavedFeedEntry {
    SavedFeedEntry(id: id, type: .feed, value: uri, pinned: pinned)
  }

  /// A list saved-feed entry.
  static func listEntry(
    _ uri: String = "at://did:plc:alice/app.bsky.graph.list/friends",
    pinned: Bool = true,
    id: String = "list-id"
  ) -> SavedFeedEntry {
    SavedFeedEntry(id: id, type: .list, value: uri, pinned: pinned)
  }
}
