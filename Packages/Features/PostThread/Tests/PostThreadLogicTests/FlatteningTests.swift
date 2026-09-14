import Foundation
import Lexicons
import Moderation
import SwiftAtproto
import Testing

@testable import PostThreadLogic

/// Flattening: the anchor + parent chain + reply tree become one linear list
/// with depths and connector state.
///
/// Ports the semantics of `responseToThreadNodes` +
/// `createThreadSkeleton`/`flattenThreadParents`/`flattenThreadReplies` in the
/// RN tree implementation (`state/queries/post-thread.ts` and
/// `view/com/post-thread/PostThread.tsx`, commit `c5641ac2b`).
@Suite("Thread flattening")
struct FlatteningTests {
  @Test("a lone anchor flattens to a single row")
  func loneAnchor() {
    let tree = Fixtures.withDepths(Fixtures.post("at://anchor"))
    let flat = ThreadFlattener.flatten(tree)

    #expect(flat.items.count == 1)
    #expect(flat.items[0].uri == "at://anchor")
    #expect(flat.items[0].depth == 0)
    #expect(flat.items[0].isAnchor)
    #expect(flat.shape == .linear)
  }

  @Test("the parent chain is emitted top-down with negative depths")
  func parentChainTopDown() {
    // Build grandparent <- parent <- anchor by linking parents.
    let grandparent = Fixtures.post("at://grandparent")
    let parent = Fixtures.post("at://parent", parent: grandparent)
    let anchor = Fixtures.post("at://anchor", parent: parent)

    let flat = ThreadFlattener.flatten(Fixtures.withDepths(anchor))

    #expect(
      flat.layout == [
        "at://grandparent@-2", "at://parent@-1", "at://anchor@0",
      ])
  }

  @Test("replies are emitted depth-first, parents before children")
  func depthFirstReplies() {
    // anchor
    //   |- a
    //   |   |- a1
    //   |- b
    let a1 = Fixtures.post("at://a1")
    let a = Fixtures.post("at://a", replies: [a1])
    let b = Fixtures.post("at://b")
    let tree = Fixtures.withDepths(
      Fixtures.post("at://anchor", replies: [a, b]))

    let flat = ThreadFlattener.flatten(tree)
    #expect(
      flat.layout == [
        "at://anchor@0", "at://a@1", "at://a1@2", "at://b@1",
      ])
  }

  @Test("a deep chain keeps increasing depth")
  func deepChain() {
    // r0 <- r1 <- r2 <- r3 <- r4, built so r4 is the root of the tree.
    var root = Fixtures.post("at://r0")
    for index in 1...4 {
      root = Fixtures.post("at://r\(index)", replies: [root])
    }
    let flat = ThreadFlattener.flatten(Fixtures.withDepths(root))

    #expect(flat.items.map(\.depth) == [0, 1, 2, 3, 4])
    #expect(flat.items.map(\.uri) == [
      "at://r4", "at://r3", "at://r2", "at://r1", "at://r0",
    ])
    #expect(flat.shape == .linear)
  }

  @Test("a branching thread reports its shape")
  func branchingShape() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [
          Fixtures.post("at://a"),
          Fixtures.post("at://b"),
        ]))
    #expect(ThreadFlattener.flatten(tree).shape == .branching)
  }

  @Test("a single-reply chain is linear even when it is long")
  func linearChainShape() {
    var root = Fixtures.post("at://r0")
    for index in 1...5 {
      root = Fixtures.post("at://r\(index)", replies: [root])
    }
    #expect(ThreadFlattener.flatten(Fixtures.withDepths(root)).shape == .linear)
  }

  @Test("the anchor is the only row flagged as anchor")
  func onlyAnchorFlagged() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [Fixtures.post("at://a"), Fixtures.post("at://b")]))
    let flat = ThreadFlattener.flatten(tree)
    #expect(flat.items.filter(\.isAnchor).map(\.uri) == ["at://anchor"])
  }

  @Test("a deleted middle becomes a tombstone at its depth")
  func deletedMiddle() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [
          Fixtures.post(
            "at://a",
            replies: [Fixtures.notFound("at://gone", depth: 2)])
        ]))
    let flat = ThreadFlattener.flatten(tree)

    #expect(flat.layout == ["at://anchor@0", "at://a@1", "[deleted]2"])
    #expect(flat.items[2].tombstoneKind == .deleted)
  }

  @Test("a deleted parent in the chain becomes a tombstone")
  func deletedParent() {
    let anchor = Fixtures.post(
      "at://anchor", parent: Fixtures.notFound("at://gone", depth: -1))
    let flat = ThreadFlattener.flatten(Fixtures.withDepths(anchor))
    #expect(flat.layout == ["[deleted]-1", "at://anchor@0"])
  }

  @Test("a blocked reply branch is dropped from the inline list")
  func blockedBranchDropped() {
    // RN filters blocked nodes out of replies entirely.
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [
          Fixtures.post("at://ok"),
          Fixtures.blocked("at://blocked", depth: 1),
          Fixtures.post("at://ok2"),
        ]))
    let flat = ThreadFlattener.flatten(tree)

    #expect(flat.postUris == ["at://anchor", "at://ok", "at://ok2"])
    #expect(flat.items.allSatisfy { $0.tombstoneKind != .blocked })
  }

  @Test("a blocked anchor is kept, since there is nothing else to show")
  func blockedAnchorKept() {
    let flat = ThreadFlattener.flatten(Fixtures.blocked("at://blocked", depth: 0))
    #expect(flat.items.count == 1)
    #expect(flat.items[0].tombstoneKind == .blocked)
  }

  @Test("moderation decisions are attached to every post row")
  func moderationAttached() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [Fixtures.post("at://a"), Fixtures.post("at://b")]))

    // With no options, no decisions.
    let plain = ThreadFlattener.flatten(tree)
    #expect(plain.items.allSatisfy { $0.postContent?.moderation == nil })

    // With options, every row carries a decision. Nothing is labelled in the
    // fixture, so nothing is hidden - which is what RN does with no causes.
    let opts = ModerationOpts(userDid: "did:plc:me", prefs: ModerationPrefs())
    let moderated = ThreadFlattener.flatten(
      tree,
      options: ThreadFlattenOptions(
        hasSession: true, moderationOpts: opts))

    #expect(moderated.postUris.count == 3)
    #expect(moderated.items.allSatisfy { $0.postContent?.moderation != nil })
    #expect(!moderated.hasOtherReplies)
  }

  @Test("skipping moderation handling keeps every row inline in tree order")
  func skipModerationHandling() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [Fixtures.post("at://a"), Fixtures.post("at://b")]))
    let flat = ThreadFlattener.flatten(
      tree, options: ThreadFlattenOptions(skipModerationHandling: true))
    #expect(flat.postUris == ["at://anchor", "at://a", "at://b"])
  }

  @Test("an unhydrated reply count produces a read-more row")
  func readMoreRow() {
    // The anchor says it has 5 replies but only one was sent.
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replyCount: 5,
        replies: [Fixtures.post("at://a")]))
    let flat = ThreadFlattener.flatten(tree)

    #expect(flat.layout == ["at://anchor@0", "at://a@1", "[moredown]1"])
    guard case .readMore(let content) = flat.items[2].content else {
      Issue.record("expected a read-more row")
      return
    }
    #expect(content.direction == .down)
    #expect(content.moreReplies == 4)
  }

  @Test("a fully hydrated branch has no read-more row")
  func noReadMoreWhenHydrated() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replyCount: 1,
        replies: [Fixtures.post("at://a")]))
    #expect(ThreadFlattener.flatten(tree).items.count == 2)
  }

  @Test("the anchor has no parent reply line and sits at indent 0")
  func anchorConnectors() {
    let tree = Fixtures.withDepths(
      Fixtures.post("at://anchor", replies: [Fixtures.post("at://a")]))
    let anchor = ThreadFlattener.flatten(tree).items[0]
    #expect(anchor.connector?.showParentReplyLine == false)
    #expect(anchor.connector?.indent == 0)
  }

  @Test("a reply to a deeper parent shows a line up to it")
  func replyParentLine() {
    // A reply directly under the anchor does NOT show a parent line: RN's rule
    // is `prevItemDepth && prevItemDepth !== 0 && prevItemDepth < depth`.
    let shallow = Fixtures.withDepths(
      Fixtures.post("at://anchor", replies: [Fixtures.post("at://a")]))
    #expect(ThreadFlattener.flatten(shallow).items[1].connector?.showParentReplyLine == false)

    // A grandchild, whose parent sits at depth 1, does.
    let deep = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [
          Fixtures.post("at://a", replies: [Fixtures.post("at://a1")])
        ]))
    let flat = ThreadFlattener.flatten(deep)
    #expect(flat.items[2].uri == "at://a1")
    #expect(flat.items[2].connector?.showParentReplyLine == true)
    #expect(flat.items[2].connector?.indent == 2)
  }

  @Test("a childless row is a last child; a branching parent is not")
  func lastChild() {
    // anchor
    //   |- a          (no children)
    //   |- b          (no children)
    let flat = ThreadFlattener.flatten(
      Fixtures.withDepths(
        Fixtures.post(
          "at://anchor",
          replies: [Fixtures.post("at://a"), Fixtures.post("at://b")])))
    // Neither has anything rendered below it, so both are last children. RN's
    // rule is `nextItemDepth === undefined || nextItemDepth <= depth`.
    #expect(flat.items[1].connector?.isLastChild == true)
    #expect(flat.items[2].connector?.isLastChild == true)

    // A row that does have a child below it is not a last child.
    let nested = ThreadFlattener.flatten(
      Fixtures.withDepths(
        Fixtures.post(
          "at://anchor",
          replies: [
            Fixtures.post("at://a", replies: [Fixtures.post("at://a1")]),
            Fixtures.post("at://b"),
          ])))
    #expect(nested.items[1].uri == "at://a")
    #expect(nested.items[1].connector?.isLastChild == false)
    #expect(nested.items[2].uri == "at://a1")
    #expect(nested.items[2].connector?.isLastChild == true)
  }

  @Test("a reply index tracks position among siblings")
  func replyIndex() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [
          Fixtures.post("at://a"), Fixtures.post("at://b"),
          Fixtures.post("at://c"),
        ]))
    let flat = ThreadFlattener.flatten(tree)
    #expect(flat.items[1].connector?.replyIndex == 0)
    #expect(flat.items[2].connector?.replyIndex == 1)
    #expect(flat.items[3].connector?.replyIndex == 2)
    #expect(flat.items[3].connector?.isLastSibling == true)
  }

  @Test("a tombstone-bearing anchor flattens to its tombstone alone")
  func tombstoneOnlyAnchor() {
    let flat = ThreadFlattener.flatten(Fixtures.notFound("at://gone", depth: 0))
    #expect(flat.items.count == 1)
    #expect(flat.items[0].tombstoneKind == .deleted)
    #expect(flat.items[0].isAnchor)
  }
}

/// Parsing a response into a tree, and the self-thread annotation.
@Suite("Thread tree building")
struct ThreadTreeBuildingTests {
  @Test("a response round-trips into a tree")
  func buildsTree() {
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [Fixtures.post("at://a")]))
    let output = Fixtures.response(tree)
    let rebuilt = ThreadTreeBuilder.build(output: output)

    guard case .post(let node) = rebuilt else {
      Issue.record("expected a post node")
      return
    }
    #expect(node.post.uri.rawValue == "at://anchor")
    #expect(node.replies.count == 1)
  }

  @Test("missing counters are filled with zero, as RN does")
  func fillsCounters() {
    let view = App.Bsky.FeedDefs_ThreadViewPost(
      post: Fixtures.postView(
        uri: "at://anchor", replyCount: nil, likeCount: nil, repostCount: nil))
    let rebuilt = ThreadTreeBuilder.build(
      output: App.Bsky.FeedGetPostThread_Output(thread: .feedDefsThreadViewPost(view)))

    guard case .post(let node) = rebuilt else {
      Issue.record("expected a post node")
      return
    }
    #expect(node.post.replyCount == 0)
    #expect(node.post.likeCount == 0)
    #expect(node.post.repostCount == 0)
  }

  @Test("blocked replies survive building and are dropped at flatten time")
  func blockedReplyBuilding() {
    let wire = App.Bsky.FeedDefs_ThreadViewPost(
      post: Fixtures.postView(uri: "at://anchor"),
      replies: [
        .feedDefsBlockedPost(
          App.Bsky.FeedDefs_BlockedPost(
            author: App.Bsky.FeedDefs_BlockedAuthor(
              did: FormatString<DID>(rawValue: "did:plc:b")),
            blocked: true,
            uri: FormatString<ATURI>(rawValue: "at://blocked")))
      ])
    let rebuilt = ThreadTreeBuilder.build(
      output: App.Bsky.FeedGetPostThread_Output(thread: .feedDefsThreadViewPost(wire)))

    guard case .post(let node) = rebuilt else {
      Issue.record("expected a post node")
      return
    }
    #expect(node.replies.count == 1)
    #expect(node.replies[0].uri == "at://blocked")

    let flat = ThreadFlattener.flatten(Fixtures.withDepths(rebuilt))
    #expect(flat.postUris == ["at://anchor"])
  }

  @Test("rootAuthorLike surfaces as hasOPLike")
  func opLike() {
    let wire = App.Bsky.FeedDefs_ThreadViewPost(
      post: Fixtures.postView(uri: "at://anchor"),
      threadContext: App.Bsky.FeedDefs_ThreadContext(
        rootAuthorLike: FormatString<ATURI>(rawValue: "at://like"))
    )
    let rebuilt = ThreadTreeBuilder.build(
      output: App.Bsky.FeedGetPostThread_Output(thread: .feedDefsThreadViewPost(wire)))

    guard case .post(let node) = rebuilt else {
      Issue.record("expected a post node")
      return
    }
    #expect(node.hasOPLike)
  }

  @Test("a self-thread of the same author is annotated")
  func selfThreadAnnotated() {
    // author -> author -> author chain.
    var root = Fixtures.post("at://r0", author: Fixtures.selfDid)
    for index in 1...2 {
      root = Fixtures.post(
        "at://r\(index)", author: Fixtures.selfDid, replies: [root])
    }
    let flattened = ThreadTreeAnnotator.annotate(Fixtures.withDepths(root))

    guard case .post(let node) = flattened else {
      Issue.record("expected a post node")
      return
    }
    // The whole chain is the same author, so the root and its reply are marked.
    #expect(node.isSelfThread)
    if case .post(let child) = node.replies.first {
      #expect(child.isSelfThread)
    } else {
      Issue.record("expected a child")
    }
  }

  @Test("a thread that changes author is not a self-thread")
  func notSelfThread() {
    let root = Fixtures.post(
      "at://anchor",
      author: Fixtures.anchorDid,
      replies: [Fixtures.post("at://a", author: "did:plc:someone-else")])
    let flattened = ThreadTreeAnnotator.annotate(Fixtures.withDepths(root))

    guard case .post(let node) = flattened else {
      Issue.record("expected a post node")
      return
    }
    #expect(!node.isSelfThread)
  }
}
