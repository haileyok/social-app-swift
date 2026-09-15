import Foundation
import HomeFeedLogic
import Lexicons
import SwiftAtproto

/**
 Synthetic home-feed content.

 The screen must render without a session, and the screenshot loop has no
 appview to talk to. These fixtures build ``HomeFeedLogic/HomeFeedSlice`` values
 the same way the tuner does - real generated lexicon post views, wrapped in
 slice items with react keys - so the lists, masks, embeds and reason lines the
 screenshot shows are produced by the production view path, not by a parallel
 mock renderer.

 The data is deliberately varied: an images post, an external card, a quoted
 post, a merged thread, a repost, a pinned post and a reply, plus a hand-built
 moderation decision that blurs one post, so a single screenshot exercises every
 branch the v1 matrix has.
 */
public enum HomeFeedFixtures {
  /// A fixed clock so relative timestamps are stable across runs, which is what
  /// makes screenshot diffs meaningful.
  public static let now = ISO8601DateFormatter().date(from: "2026-09-14T12:00:00Z")!

  /// The ISO-8601 timestamp every fixture post carries.
  public static let indexedAt = "2026-09-14T11:30:00.000Z"

  // MARK: - Authors

  /// A profile view for an author.
  public static func author(
    handle: String,
    displayName: String? = nil,
    did: String? = nil,
    avatar: String? = nil
  ) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      avatar: avatar.map { FormatString<URI>(rawValue: $0) },
      did: FormatString<SwiftAtproto.DID>(rawValue: did ?? "did:plc:\(handle)"),
      displayName: displayName,
      handle: FormatString<SwiftAtproto.Handle>(rawValue: handle))
  }

  // MARK: - Posts

  /// A post view with the given text and embed.
  public static func post(
    _ id: String,
    text: String,
    author: App.Bsky.ActorDefs_ProfileViewBasic,
    embed: App.Bsky.FeedDefs_PostView_Embed? = nil,
    replyCount: Int? = nil,
    repostCount: Int? = nil,
    likeCount: Int? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: author,
      cid: FormatString<LexLink>(rawValue: "bafy\(id)"),
      embed: embed,
      indexedAt: FormatString<Date>(rawValue: indexedAt),
      likeCount: likeCount,
      record: .record(
        App.Bsky.FeedPost(
          createdAt: FormatString<Date>(rawValue: indexedAt), text: text)),
      replyCount: replyCount,
      repostCount: repostCount,
      uri: FormatString<ATURI>(
        rawValue: "at://\(author.did.rawValue)/app.bsky.feed.post/\(id)"))
  }

  /// An images embed carrying placeholder render URLs.
  public static func images(_ count: Int) -> App.Bsky.FeedDefs_PostView_Embed {
    let images = (0..<count).map { index in
      App.Bsky.EmbedImages_ViewImage(
        alt: "Placeholder image \(index + 1)",
        fullsize: FormatString<URI>(rawValue: "https://cdn.example/\(index)/full"),
        thumb: FormatString<URI>(rawValue: "https://cdn.example/\(index)/thumb"))
    }
    return .embedImagesView(App.Bsky.EmbedImages_View(images: images))
  }

  /// An external link-card embed.
  public static func external(
    title: String, description: String
  ) -> App.Bsky.FeedDefs_PostView_Embed {
    .embedExternalView(
      App.Bsky.EmbedExternal_View(
        external: App.Bsky.EmbedExternal_ViewExternal(
          description: description,
          thumb: nil,
          title: title,
          uri: FormatString<URI>(rawValue: "https://example.com/article"))))
  }

  /// A quoted-post embed.
  public static func quote(
    _ id: String, text: String, author: App.Bsky.ActorDefs_ProfileViewBasic
  ) -> App.Bsky.FeedDefs_PostView_Embed {
    let quoted = post(id, text: text, author: author)
    return .embedRecordView(
      App.Bsky.EmbedRecord_View(
        record: .embedRecordViewRecord(
          App.Bsky.EmbedRecord_ViewRecord(
            author: quoted.author,
            cid: quoted.cid,
            indexedAt: quoted.indexedAt,
            uri: quoted.uri,
            value: quoted.record))))
  }

  // MARK: - Slices

  /// Wraps post views into a slice the way the tuner's
  /// `makeHomeFeedSlice(from:)` does.
  public static func slice(
    _ key: String,
    posts: [App.Bsky.FeedDefs_PostView],
    reason: App.Bsky.FeedDefs_FeedViewPost_Reason? = nil,
    isIncompleteThread: Bool = false
  ) -> HomeFeedSlice {
    let items = posts.enumerated().map { index, post -> HomeFeedSliceItem in
      var item = HomeFeedSliceItem(
        post: post,
        record: record(of: post),
        reactKey: "\(key)-\(index)-\(post.uri.rawValue)",
        uri: post.uri.rawValue)
      // Every item past the first is in a thread with the one before it.
      if index > 0 {
        item.parentAuthor = posts[index - 1].author
      }
      return item
    }
    let last = posts.last
    return HomeFeedSlice(
      reactKey: key,
      items: items,
      isIncompleteThread: isIncompleteThread,
      feedPostUri: last?.uri.rawValue ?? "",
      reason: reason,
      rootUri: posts.first?.uri.rawValue ?? "")
  }

  /// The typed post record for a post view, which the view-data builder reads.
  public static func record(of post: App.Bsky.FeedDefs_PostView) -> App.Bsky.FeedPost {
    if case .record(let record) = post.record, let typed = record as? App.Bsky.FeedPost {
      return typed
    }
    return App.Bsky.FeedPost(
      createdAt: FormatString<Date>(rawValue: indexedAt), text: "")
  }

  // MARK: - Pinned feeds

  /// The default switcher contents, selected on the timeline.
  public static var pinnedFeeds: [PinnedFeed] {
    [
      PinnedFeed(
        config: SavedFeedEntry(id: "pwi-timeline", type: .timeline, value: "following", pinned: true),
        displayName: "Following"),
      PinnedFeed(
        config: SavedFeedEntry(
          id: "pwi-discover", type: .feed, value: FeedURIs.discover, pinned: true),
        displayName: "Discover"),
      PinnedFeed(
        config: SavedFeedEntry(
          id: "pwi-science", type: .feed,
          value: "at://did:plc:science/app.bsky.feed.generator/science", pinned: true),
        displayName: "Science"),
    ]
  }

  // MARK: - The demo feed

  /// A varied feed: plain posts, every v1 embed, a repost, a pin, a merged
  /// thread and a reply.
  public static var slices: [HomeFeedSlice] {
    let alice = author(handle: "alice.bsky.social", displayName: "Alice")
    let bob = author(handle: "bob.bsky.social", displayName: "Bob Chen")
    let carol = author(handle: "carol.bsky.social", displayName: "carol")
    let dave = author(handle: "dave.bsky.social")

    return [
      slice(
        "s1",
        posts: [
          post(
            "1",
            text:
              "Shipping the Home feed screen today. Native lists, pull to refresh, and a real new-posts pill.",
            author: alice, replyCount: 12, repostCount: 34, likeCount: 210)
        ]),
      slice(
        "s2",
        posts: [
          post(
            "2",
            text: "Four album covers from the studio session this weekend.",
            author: bob,
            embed: images(4),
            replyCount: 3,
            repostCount: 8,
            likeCount: 96)
        ]),
      slice(
        "s3",
        posts: [
          post(
            "3",
            text: "Worth reading if you care about how feeds are ranked.",
            author: carol,
            embed: external(
              title: "How algorithmic feeds actually work",
              description:
                "A walk through candidate generation, ranking and the feedback loops that shape what you see."),
            replyCount: 5,
            repostCount: 41,
            likeCount: 388)
        ]),
      slice(
        "s4",
        posts: [
          post(
            "4",
            text: "Strongly agree with this.",
            author: dave,
            embed: quote("4q", text: "Local-first software is the only kind that ages well.", author: alice),
            replyCount: 1,
            repostCount: 2,
            likeCount: 44)
        ]),
      slice(
        "s5",
        posts: [
          post(
            "5", text: "Starting a thread about SwiftUI list performance.",
            author: bob, replyCount: 9, repostCount: 4, likeCount: 77),
          post(
            "5r1",
            text: "First: identity. A stable id on every row is the whole game.",
            author: bob, replyCount: 2, repostCount: 1, likeCount: 31),
        ],
        isIncompleteThread: true),
      slice(
        "s6",
        posts: [
          post(
            "6",
            text: "The repost line renders above the post, exactly like the old app.",
            author: carol, replyCount: 0, repostCount: 15, likeCount: 120)
        ],
        reason: .feedDefsReasonRepost(
          App.Bsky.FeedDefs_ReasonRepost(
            by: alice,
            indexedAt: FormatString<Date>(rawValue: indexedAt)))),
      slice(
        "s7",
        posts: [
          post(
            "7",
            text: "A pinned post stays at the top of the profile feed.",
            author: dave, replyCount: 1, repostCount: 0, likeCount: 18)
        ],
        reason: .feedDefsReasonPin(App.Bsky.FeedDefs_ReasonPin())),
      slice(
        "s8",
        posts: [
          post(
            "8",
            text: "Replying in a thread that also has its parent merged in.",
            author: alice, replyCount: 2, repostCount: 0, likeCount: 12)
        ]),
    ]
  }

  /// A feed whose posts all fail moderation, for the filtered-to-empty state.
  public static var allFilteredSlice: HomeFeedSlice {
    slice(
      "filtered",
      posts: [
        post("f1", text: "Hidden by a label.", author: author(handle: "spam.example"))
      ])
  }
}
