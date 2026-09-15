import Foundation
import Lexicons
import Moderation
import SwiftAtproto

@testable import PostThreadLogic

/// Builders for lexicon thread fixtures.
///
/// The lexicon types are all generated structs with large memberwise
/// initialisers, so these helpers keep fixtures readable and let a test change
/// exactly the field it cares about.
enum Fixtures {
  static let anchorDid = "did:plc:anchor"
  static let opDid = "did:plc:anchor"
  static let selfDid = "did:plc:me"

  /// A post view with sensible defaults.
  static func postView(
    uri: String,
    author: String = anchorDid,
    text: String = "hello",
    indexedAt: String = "2026-01-01T00:00:00.000Z",
    replyCount: Int? = 0,
    likeCount: Int? = 0,
    repostCount: Int? = 0,
    record: App.Bsky.FeedPost? = nil,
    labels: [Com.Atproto.LabelDefs_Label]? = nil,
    following: String? = nil,
    replyDisabled: Bool? = nil
  ) -> App.Bsky.FeedDefs_PostView {
    App.Bsky.FeedDefs_PostView(
      author: profile(author, following: following),
      cid: FormatString<LexLink>(rawValue: "bafy\(abs(uri.hashValue))"),
      indexedAt: FormatString<Date>(rawValue: indexedAt),
      labels: labels,
      likeCount: likeCount,
      record: .record(record ?? postRecord(text: text, indexedAt: indexedAt)),
      replyCount: replyCount,
      repostCount: repostCount,
      uri: FormatString<ATURI>(rawValue: uri),
      viewer: App.Bsky.FeedDefs_ViewerState(replyDisabled: replyDisabled)
    )
  }

  static func profile(_ did: String, following: String? = nil) -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      avatar: nil,
      did: FormatString<DID>(rawValue: did),
      displayName: nil,
      handle: FormatString<Handle>(rawValue: did.replacingOccurrences(of: "did:plc:", with: "") + ".test"),
      labels: nil,
      viewer: following.map { value in
        App.Bsky.ActorDefs_ViewerState(
          following: FormatString<ATURI>(rawValue: value))
      }
    )
  }

  static func postRecord(
    text: String = "hello",
    indexedAt: String = "2026-01-01T00:00:00.000Z",
    replyParent: String? = nil
  ) -> App.Bsky.FeedPost {
    App.Bsky.FeedPost(
      createdAt: FormatString<Date>(rawValue: indexedAt),
      reply: replyParent.map { parent in
        App.Bsky.FeedPost_ReplyRef(
          parent: Com.Atproto.RepoStrongRef(
            cid: FormatString<LexLink>(rawValue: "bafyparent"),
            uri: FormatString<ATURI>(rawValue: parent)),
          root: Com.Atproto.RepoStrongRef(
            cid: FormatString<LexLink>(rawValue: "bafyroot"),
            uri: FormatString<ATURI>(rawValue: parent))
        )
      },
      text: text
    )
  }

  /// A thread-view node. Depths are 0 until ``withDepths(_:depth:)`` fixes
  /// them, so fixtures can be built bottom-up.
  static func post(
    _ uri: String,
    author: String = anchorDid,
    text: String = "hello",
    indexedAt: String = "2026-01-01T00:00:00.000Z",
    replyCount: Int? = 0,
    likeCount: Int? = 0,
    rootAuthorLike: Bool = false,
    parent: ThreadNode? = nil,
    replies: [ThreadNode] = []
  ) -> ThreadNode {
    .post(
      ThreadPostNode(
        post: postView(
          uri: uri, author: author, text: text, indexedAt: indexedAt,
          replyCount: replyCount, likeCount: likeCount),
        record: postRecord(text: text, indexedAt: indexedAt),
        hasOPLike: rootAuthorLike,
        parent: parent,
        replies: replies,
        depth: 0,
        isHighlighted: false
      ))
  }

  /// A reply node with a parent link, so depths resolve correctly.
  static func reply(
    _ uri: String,
    to parent: ThreadNode,
    author: String = "did:plc:replier",
    text: String = "reply",
    indexedAt: String = "2026-01-02T00:00:00.000Z",
    replyCount: Int? = 0,
    likeCount: Int? = 0,
    rootAuthorLike: Bool = false,
    replies: [ThreadNode] = []
  ) -> ThreadNode {
    post(
      uri, author: author, text: text, indexedAt: indexedAt,
      replyCount: replyCount, likeCount: likeCount, rootAuthorLike: rootAuthorLike,
      parent: parent, replies: replies)
  }

  /// A tombstone node at a depth.
  static func blocked(_ uri: String, depth: Int) -> ThreadNode {
    .tombstone(ThreadTombstone(kind: .blocked, uri: uri, depth: depth))
  }

  static func notFound(_ uri: String, depth: Int) -> ThreadNode {
    .tombstone(ThreadTombstone(kind: .deleted, uri: uri, depth: depth))
  }

  /// Recomputes depths down a tree, so a fixture can be built bottom-up without
  /// threading the depth through every call.
  static func withDepths(_ node: ThreadNode, depth: Int = 0) -> ThreadNode {
    guard case .post(var postNode) = node else {
      if case .tombstone(let tombstone) = node {
        return .tombstone(
          ThreadTombstone(kind: tombstone.kind, uri: tombstone.uri, depth: depth))
      }
      return node
    }
    postNode.depth = depth
    postNode.isHighlighted = depth == 0
    if let parent = postNode.parent {
      postNode.parent = withDepths(parent, depth: depth - 1)
    }
    postNode.replies = postNode.replies.map { withDepths($0, depth: depth + 1) }
    return .post(postNode)
  }

  /// A flat `getPostThread` response wrapping a tree.
  static func response(_ node: ThreadNode) -> App.Bsky.FeedGetPostThread_Output {
    App.Bsky.FeedGetPostThread_Output(thread: wire(node))
  }

  static func wire(_ node: ThreadNode) -> App.Bsky.FeedGetPostThread_Output_Thread {
    switch node {
    case .post(let postNode):
      return .feedDefsThreadViewPost(wirePost(postNode))
    case .tombstone(let tombstone):
      switch tombstone.kind {
      case .blocked:
        return .feedDefsBlockedPost(
          App.Bsky.FeedDefs_BlockedPost(
            author: App.Bsky.FeedDefs_BlockedAuthor(
              did: FormatString<DID>(rawValue: "did:plc:blocked")),
            blocked: true,
            uri: FormatString<ATURI>(rawValue: tombstone.uri)))
      case .deleted, .hiddenByModeration:
        return .feedDefsNotFoundPost(
          App.Bsky.FeedDefs_NotFoundPost(
            notFound: true, uri: FormatString<ATURI>(rawValue: tombstone.uri)))
      }
    }
  }

  static func wirePost(_ node: ThreadPostNode) -> App.Bsky.FeedDefs_ThreadViewPost {
    App.Bsky.FeedDefs_ThreadViewPost(
      parent: node.parent.map(wireParent),
      post: node.post,
      replies: node.replies.isEmpty ? nil : node.replies.map(wireReply),
      threadContext: node.hasOPLike
        ? App.Bsky.FeedDefs_ThreadContext(
          rootAuthorLike: FormatString<ATURI>(rawValue: node.post.uri.rawValue))
        : nil
    )
  }

  static func wireParent(_ node: ThreadNode) -> App.Bsky.FeedDefs_ThreadViewPost_Parent {
    switch node {
    case .post(let postNode):
      return .feedDefsThreadViewPost(wirePost(postNode))
    case .tombstone(let tombstone):
      switch tombstone.kind {
      case .blocked:
        return .feedDefsBlockedPost(
          App.Bsky.FeedDefs_BlockedPost(
            author: App.Bsky.FeedDefs_BlockedAuthor(
              did: FormatString<DID>(rawValue: "did:plc:blocked")),
            blocked: true,
            uri: FormatString<ATURI>(rawValue: tombstone.uri)))
      case .deleted, .hiddenByModeration:
        return .feedDefsNotFoundPost(
          App.Bsky.FeedDefs_NotFoundPost(
            notFound: true, uri: FormatString<ATURI>(rawValue: tombstone.uri)))
      }
    }
  }

  static func wireReply(_ node: ThreadNode) -> App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem {
    switch node {
    case .post(let postNode):
      return .feedDefsThreadViewPost(wirePost(postNode))
    case .tombstone(let tombstone):
      switch tombstone.kind {
      case .blocked:
        return .feedDefsBlockedPost(
          App.Bsky.FeedDefs_BlockedPost(
            author: App.Bsky.FeedDefs_BlockedAuthor(
              did: FormatString<DID>(rawValue: "did:plc:blocked")),
            blocked: true,
            uri: FormatString<ATURI>(rawValue: tombstone.uri)))
      case .deleted, .hiddenByModeration:
        return .feedDefsNotFoundPost(
          App.Bsky.FeedDefs_NotFoundPost(
            notFound: true, uri: FormatString<ATURI>(rawValue: tombstone.uri)))
      }
    }
  }
}

/// Convenience accessors for assertions.
extension FlattenedThread {
  /// The uri of every post row, in order.
  var postUris: [String] {
    items.compactMap {
      if case .post = $0.content { return $0.uri }
      return nil
    }
  }

  /// Every row's `(uri, depth)` pair, including tombstones and synthetic rows.
  var layout: [String] {
    items.map { row in
      switch row.content {
      case .post: return "\(row.uri)@\(row.depth)"
      case .tombstone(let tombstone): return "[\(tombstone.kind.rawValue)]\(row.depth)"
      case .readMore(let content): return "[more\(content.direction)]\(row.depth)"
      case .showMore: return "[showMore]"
      }
    }
  }
}

extension ThreadItem {
  var isPost: Bool {
    if case .post = content { return true }
    return false
  }

  var tombstoneKind: ThreadTombstoneKind? {
    if case .tombstone(let tombstone) = content { return tombstone.kind }
    return nil
  }

  var postContent: ThreadPostContent? {
    if case .post(let content) = content { return content }
    return nil
  }
}
