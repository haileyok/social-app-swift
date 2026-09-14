import Foundation
import Lexicons
import PostThreadLogic
import SwiftAtproto

/// Fixture threads for previews and the App's screenshot surface.
///
/// The rows a view renders are built by the real logic package, not hand-made:
/// each fixture constructs a `getPostThread`-shaped wire tree and runs it
/// through ``ThreadFlattener``, so the sample thread exercises the same
/// flattening, connector annotation and moderation pass a live thread would.
///
/// ```swift
/// PostThreadScreen(thread: ThreadFixtures.sampleThread())
/// ```
public enum ThreadFixtures {
  /// A realistic thread: two ancestors, a highlighted anchor, a small
  /// conversation with a nested reply, a deleted reply, a blocked reply, an
  /// OP-liked reply, and a branch whose replies the server only partly
  /// hydrated (so the list shows a read-more row).
  ///
  /// This is the fixture the App shell renders for screenshots. It is
  /// deliberately deep and mixed so one image shows indent, connectors,
  /// tombstones, the anchor highlight and the read-more affordance at once.
  public static func sampleThread() -> FlattenedThread {
    ThreadFlattener.flatten(ThreadTreeBuilder.build(output: sampleResponse()))
  }

  /// A short, linear thread: one parent, the anchor, one reply.
  public static func linearThread() -> FlattenedThread {
    let anchor = postView(
      uri: uri("anchor"),
      handle: "alice.bsky.social",
      displayName: "Alice",
      text: "A short thread with a single reply.")
    let parent = postView(
      uri: uri("parent1"),
      handle: "bob.bsky.social",
      displayName: "Bob",
      text: "Replying to close out this thought.")
    let anchorWithParent = App.Bsky.FeedDefs_ThreadViewPost(
      parent: .feedDefsThreadViewPost(App.Bsky.FeedDefs_ThreadViewPost(post: parent)),
      post: anchor,
      replies: [
        .feedDefsThreadViewPost(
          App.Bsky.FeedDefs_ThreadViewPost(
            post: postView(
              uri: uri("reply1"),
              handle: "carol.bsky.social",
              displayName: "Carol",
              text: "Nice one.")))
      ])
    return ThreadFlattener.flatten(
      ThreadTreeBuilder.build(
        output: App.Bsky.FeedGetPostThread_Output(thread: .feedDefsThreadViewPost(anchorWithParent))))
  }

  /// The wire response the sample thread is built from.
  public static func sampleResponse() -> App.Bsky.FeedGetPostThread_Output {
    App.Bsky.FeedGetPostThread_Output(thread: .feedDefsThreadViewPost(sampleThreadView()))
  }

  // MARK: - Tree

  static func sampleThreadView() -> App.Bsky.FeedDefs_ThreadViewPost {
    // Parents, oldest first: root <- parent1 <- anchor.
    let root = App.Bsky.FeedDefs_ThreadViewPost(
      post: postView(
        uri: uri("root"),
        handle: "dave.bsky.social",
        displayName: "Dave",
        text: "Starting a thread about how we draw reply lines in the new SwiftUI client."))
    let parent = App.Bsky.FeedDefs_ThreadViewPost(
      parent: .feedDefsThreadViewPost(root),
      post: postView(
        uri: uri("parent1"),
        handle: "bob.bsky.social",
        displayName: "Bob",
        text: "Worth getting the connector data out of the view and into the logic package."))

    let anchor = postView(
      uri: uri("anchor"),
      handle: "alice.bsky.social",
      displayName: "Alice",
      text: "Agreed. The flattened rows carry their own indent state now, so the view just draws what it is told.",
      replyCount: 6,
      likeCount: 42,
      repostCount: 7)

    let anchorView = App.Bsky.FeedDefs_ThreadViewPost(
      parent: .feedDefsThreadViewPost(parent),
      post: anchor,
      replies: anchorReplies())

    return anchorView
  }

  /// The anchor's replies: a nested conversation, a tombstone, a partial
  /// branch (read-more), and a blocked one.
  static func anchorReplies() -> [App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem] {
    // A reply that itself has two children, one of which is OP-liked.
    let likedReply = App.Bsky.FeedDefs_ThreadViewPost(
      post: postView(
        uri: uri("reply-1-1"),
        handle: "erin.bsky.social",
        displayName: "Erin",
        text: "This is the deepest useful reply in the sample."),
      threadContext: App.Bsky.FeedDefs_ThreadContext(
        rootAuthorLike: FormatString<ATURI>(rawValue: uri("like"))))

    let firstReply = App.Bsky.FeedDefs_ThreadViewPost(
      post: postView(
        uri: uri("reply-1"),
        handle: "frank.bsky.social",
        displayName: "Frank",
        text: "Does the read-more row grow the window by a whole chunk?",
        replyCount: 2),
      replies: [
        .feedDefsThreadViewPost(
          App.Bsky.FeedDefs_ThreadViewPost(
            post: postView(
              uri: uri("reply-1-0"),
              handle: "grace.bsky.social",
              displayName: "Grace",
              text: "It does - one chunk per tap, same as the RN client."))),
        .feedDefsThreadViewPost(likedReply),
      ])

    // A branch the server only partly hydrated: replyCount exceeds the replies
    // sent, so the flattener appends a read-more row after it.
    let partial = App.Bsky.FeedDefs_ThreadViewPost(
      post: postView(
        uri: uri("reply-2"),
        handle: "heidi.bsky.social",
        displayName: "Heidi",
        text: "There are more replies under this one than the server sent back.",
        replyCount: 9))

    // A deleted reply, which the server answers with a #notFoundPost.
    let deleted = App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem.feedDefsNotFoundPost(
      App.Bsky.FeedDefs_NotFoundPost(notFound: true, uri: FormatString<ATURI>(rawValue: uri("reply-deleted"))))

    // A blocked reply. The logic package drops blocked replies from the inline
    // list at depth > 0, exactly as RN does, so this one is present but not
    // rendered - keeping it here proves the drop still holds.
    let blocked = App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem.feedDefsBlockedPost(
      App.Bsky.FeedDefs_BlockedPost(
        author: App.Bsky.FeedDefs_BlockedAuthor(did: FormatString<DID>(rawValue: "did:plc:blocked")),
        blocked: true,
        uri: FormatString<ATURI>(rawValue: uri("reply-blocked"))))

    return [
      .feedDefsThreadViewPost(firstReply),
      .feedDefsThreadViewPost(partial),
      deleted,
      blocked,
    ]
  }

  /// A thread whose anchor is itself a tombstone, for the placeholder-adjacent
  /// "the post is gone" row.
  public static func deletedAnchorThread() -> FlattenedThread {
    ThreadFlattener.flatten(
      ThreadTreeBuilder.build(
        output: App.Bsky.FeedGetPostThread_Output(
          thread: .feedDefsNotFoundPost(
            App.Bsky.FeedDefs_NotFoundPost(
              notFound: true,
              uri: FormatString<ATURI>(rawValue: uri("deleted-anchor")))))))
  }

  /// Sample rows for the actor lists.
  public static func sampleLikes() -> [PostLike] {
    [
      PostLike(
        actor: profileView(handle: "bob.bsky.social", displayName: "Bob"),
        createdAt: "2026-01-01T00:00:00.000Z",
        indexedAt: "2026-01-01T00:00:00.000Z"),
      PostLike(
        actor: profileView(handle: "carol.bsky.social", displayName: "Carol"),
        createdAt: "2026-01-01T00:00:00.000Z",
        indexedAt: "2026-01-01T00:00:00.000Z"),
      PostLike(
        actor: profileView(handle: "dave.bsky.social", displayName: nil),
        createdAt: "2026-01-01T00:00:00.000Z",
        indexedAt: "2026-01-01T00:00:00.000Z"),
    ]
  }

  /// Sample actors for the reposts list.
  public static func sampleReposts() -> [App.Bsky.ActorDefs_ProfileView] {
    [
      App.Bsky.ActorDefs_ProfileView(
        did: FormatString<DID>(rawValue: "did:plc:bob"),
        displayName: "Bob",
        handle: FormatString<Handle>(rawValue: "bob.bsky.social")),
      App.Bsky.ActorDefs_ProfileView(
        did: FormatString<DID>(rawValue: "did:plc:erin"),
        displayName: "Erin",
        handle: FormatString<Handle>(rawValue: "erin.bsky.social")),
    ]
  }

  /// Sample quoting posts for the quotes list.
  public static func sampleQuotes() -> [PostQuote] {
    [
      PostQuote(
        post: postView(
          uri: uri("quote-1"),
          handle: "grace.bsky.social",
          displayName: "Grace",
          text: "Quoting this because the connector rendering is the interesting part.")),
      PostQuote(
        post: postView(
          uri: uri("quote-2"),
          handle: "heidi.bsky.social",
          displayName: "Heidi",
          text: "Second quote in the sample list.")),
    ]
  }

  // MARK: - Builders

  /// A `did:plc:` uri under the fixture author's repo.
  static func uri(_ slug: String) -> String {
    "at://did:plc:alice/app.bsky.feed.post/\(slug)"
  }

  static func postView(
    uri: String,
    handle: String,
    displayName: String?,
    text: String,
    replyCount: Int = 0,
    likeCount: Int = 0,
    repostCount: Int = 0
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: App.Bsky.ActorDefs_ProfileViewBasic(
        did: FormatString<DID>(rawValue: did(for: handle)),
        displayName: displayName,
        handle: FormatString<Handle>(rawValue: handle)),
      cid: FormatString<LexLink>(rawValue: "bafy\(slugHash(uri))"),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T12:00:00.000Z"),
      likeCount: likeCount,
      record: .record(
        App.Bsky.FeedPost(
          createdAt: FormatString<Date>(rawValue: "2026-01-01T12:00:00.000Z"),
          text: text)),
      replyCount: replyCount,
      repostCount: repostCount,
      uri: FormatString<ATURI>(rawValue: uri),
      viewer: App.Bsky.FeedDefs_ViewerState())
  }

  static func profileView(handle: String, displayName: String?) -> App.Bsky.ActorDefs_ProfileView {
    App.Bsky.ActorDefs_ProfileView(
      did: FormatString<DID>(rawValue: did(for: handle)),
      displayName: displayName,
      handle: FormatString<Handle>(rawValue: handle))
  }

  /// A stable `did:plc:` stand-in derived from the handle, so fixtures do not
  /// share one identity.
  static func did(for handle: String) -> String {
    let local = handle.split(separator: ".").first.map(String.init) ?? handle
    return "did:plc:\(local)"
  }

  /// A deterministic cid-shaped string, since the cid is never read by a view.
  static func slugHash(_ value: String) -> Int {
    abs(value.hashValue % 1_000_000)
  }
}
