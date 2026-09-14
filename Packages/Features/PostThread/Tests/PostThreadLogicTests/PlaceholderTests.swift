import Foundation
import Lexicons
import Moderation
import SwiftAtproto
import Testing

@testable import PostThreadLogic

/// Tombstone and placeholder mapping.
///
/// Ports the `#notFoundPost`/`#blockedPost` handling in `responseToThreadNodes`
/// (`state/queries/post-thread.ts`) plus the moderation-driven blur rule the
/// newer traversal reads from the decision (`childPost.isBlurred`).
@Suite("Placeholder mapping")
struct PlaceholderTests {
  @Test("a wire notFound node maps to a deleted tombstone")
  func notFoundMaps() {
    let node = App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem.feedDefsNotFoundPost(
      App.Bsky.FeedDefs_NotFoundPost(
        notFound: true, uri: FormatString<ATURI>(rawValue: "at://gone")))
    let tombstone = ThreadPlaceholder.tombstone(for: node)
    #expect(tombstone?.kind == .deleted)
    #expect(tombstone?.uri == "at://gone")
  }

  @Test("a wire blocked node maps to a blocked tombstone")
  func blockedMaps() {
    let node = App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem.feedDefsBlockedPost(
      App.Bsky.FeedDefs_BlockedPost(
        author: App.Bsky.FeedDefs_BlockedAuthor(
          did: FormatString<DID>(rawValue: "did:plc:b")),
        blocked: true,
        uri: FormatString<ATURI>(rawValue: "at://blocked")))
    let tombstone = ThreadPlaceholder.tombstone(for: node)
    #expect(tombstone?.kind == .blocked)
    #expect(tombstone?.uri == "at://blocked")
  }

  @Test("a readable node maps to no tombstone")
  func readableMapsToNil() {
    let node = App.Bsky.FeedDefs_ThreadViewPost_Replies_Elem.feedDefsThreadViewPost(
      App.Bsky.FeedDefs_ThreadViewPost(post: Fixtures.postView(uri: "at://ok")))
    #expect(ThreadPlaceholder.tombstone(for: node) == nil)
  }

  @Test("a parent-position notFound maps to a deleted tombstone")
  func parentNotFound() {
    let node = App.Bsky.FeedDefs_ThreadViewPost_Parent.feedDefsNotFoundPost(
      App.Bsky.FeedDefs_NotFoundPost(
        notFound: true, uri: FormatString<ATURI>(rawValue: "at://gone")))
    #expect(ThreadPlaceholder.tombstone(for: node)?.kind == .deleted)
  }

  @Test("the response root maps too")
  func rootNotFound() {
    let node = App.Bsky.FeedGetPostThread_Output_Thread.feedDefsNotFoundPost(
      App.Bsky.FeedDefs_NotFoundPost(
        notFound: true, uri: FormatString<ATURI>(rawValue: "at://gone")))
    #expect(ThreadPlaceholder.tombstone(for: node)?.kind == .deleted)
  }

  @Test("an unknown record type is not mapped")
  func unknownRecordUnmapped() {
    let node = App.Bsky.FeedGetPostThread_Output_Thread._other(
      UnknownRecord(type: "com.example.unknown"))
    #expect(ThreadPlaceholder.tombstone(for: node) == nil)
  }

  @Test("a nil decision is never hidden")
  func nilDecisionVisible() {
    #expect(ThreadPlaceholder.isHiddenByModeration(nil) == false)
  }

  @Test("a decision with no causes is not hidden")
  func cleanDecisionVisible() {
    let decision = ModerationDecision()
    #expect(ThreadPlaceholder.isHiddenByModeration(decision) == false)
  }

  @Test("a muting decision blurs in the content list, so it is hidden")
  func mutedDecisionHidden() {
    var decision = ModerationDecision()
    decision.causes = [
      ModerationCause(type: .muted, source: .user, priority: 1)
    ]
    #expect(ThreadPlaceholder.isHiddenByModeration(decision))
  }

  @Test("the moderation tombstone is kinded as hidden-by-moderation")
  func moderationTombstoneKind() {
    let tombstone = ThreadPlaceholder.moderationTombstone(uri: "at://hidden")
    #expect(tombstone.kind == .hiddenByModeration)
    #expect(tombstone.uri == "at://hidden")
  }

  @Test("all three tombstone kinds exist and encode stably")
  func kinds() {
    #expect(ThreadTombstoneKind.allCases.count == 3)
    #expect(ThreadTombstoneKind.deleted.rawValue == "deleted")
    #expect(ThreadTombstoneKind.blocked.rawValue == "blocked")
    #expect(ThreadTombstoneKind.hiddenByModeration.rawValue == "hiddenByModeration")
  }

  @Test("a hidden top-level reply is bucketed instead of rendered inline")
  func hiddenReplyBucketing() {
    // A post the viewer has hidden is dropped from the content list by the
    // moderation engine (`checkHiddenPost` reads `prefs.hiddenPosts`), which is
    // the same signal RN's traversal reads as `isBlurred`.
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [Fixtures.post("at://hidden"), Fixtures.post("at://ok")]))

    let opts = ModerationOpts(
      userDid: "did:plc:me",
      prefs: ModerationPrefs(hiddenPosts: ["at://hidden"]))

    let flat = ThreadFlattener.flatten(
      tree, options: ThreadFlattenOptions(hasSession: true, moderationOpts: opts))

    // It is not inline, and it is offered in the other bucket instead.
    #expect(!flat.postUris.contains("at://hidden"))
    #expect(flat.hasOtherReplies)
    #expect(flat.otherItems.map(\.uri) == ["at://hidden"])
  }

  @Test("a hidden reply deeper in the tree is dropped with its subtree")
  func hiddenDeepReplyDropped() {
    // anchor -> a -> hidden -> grandchild
    let tree = Fixtures.withDepths(
      Fixtures.post(
        "at://anchor",
        replies: [
          Fixtures.post(
            "at://a",
            replies: [
              Fixtures.post(
                "at://hidden",
                replies: [Fixtures.post("at://grandchild")])
            ])
        ]))

    let opts = ModerationOpts(
      userDid: "did:plc:me",
      prefs: ModerationPrefs(hiddenPosts: ["at://hidden"]))

    let flat = ThreadFlattener.flatten(
      tree, options: ThreadFlattenOptions(hasSession: true, moderationOpts: opts))

    // RN drops the moderated node and everything below it; it is not bucketed
    // because it is not a top-level reply.
    #expect(flat.postUris == ["at://anchor", "at://a"])
    #expect(!flat.hasOtherReplies)
  }

  @Test("a post hidden by moderation maps onto the hidden tombstone kind")
  func hiddenTombstoneKind() {
    // The tombstone the data layer would emit for a moderated-out post.
    let tombstone = ThreadPlaceholder.moderationTombstone(uri: "at://hidden")
    let row = ThreadItem(
      id: "hidden", uri: tombstone.uri, depth: 1, isAnchor: false,
      content: .tombstone(tombstone))
    #expect(row.tombstoneKind == .hiddenByModeration)
  }
}
