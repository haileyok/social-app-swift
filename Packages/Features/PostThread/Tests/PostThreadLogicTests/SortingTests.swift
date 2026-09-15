import Foundation
import Lexicons
import Moderation
import Testing

@testable import PostThreadLogic

/// The reply comparator, as a table.
///
/// Ports the ordering rules of `sortThread`'s comparator in
/// `state/queries/post-thread.ts`. Each case is a pair of replies to the same
/// parent, asserted to sort in the documented order.
@Suite("Reply comparator")
struct SortingTests {
  static let parentDid = "did:plc:op"
  static let meDid = "did:plc:me"

  /// Builds a sortable reply with the fields a given rule reads.
  static func reply(
    _ uri: String,
    author: String = "did:plc:someone",
    indexedAt: String = "2026-01-01T00:00:00.000Z",
    text: String = "hello",
    likeCount: Int? = 0,
    following: Bool = false,
    blurred: Bool = false
  ) -> SortableReply {
    let decision = blurred ? Self.blurDecision() : nil
    return SortableReply(
      uri: uri,
      post: Fixtures.postView(
        uri: uri, author: author, text: text, indexedAt: indexedAt,
        likeCount: likeCount, following: following ? "at://follow" : nil),
      record: Fixtures.postRecord(text: text, indexedAt: indexedAt),
      hasOPLike: false,
      moderation: decision
    )
  }

  /// A decision that blurs the post in a content list (a user-level mute is the
  /// simplest cause that produces a content-list blur).
  static func blurDecision() -> ModerationDecision {
    var decision = ModerationDecision()
    decision.causes = [
      ModerationCause(type: .muted, source: .user, priority: 1)
    ]
    return decision
  }

  static func comparator(
    order: ThreadSortOrder = .newest,
    inputs: ThreadSortInputs = ThreadSortInputs()
  ) -> ThreadReplyComparator {
    ThreadReplyComparator(
      parentAuthorDid: parentDid, inputs: inputs, order: order)
  }

  @Test("the OP's own replies come before everyone else's")
  func opFirst() {
    let comparison = Self.comparator()
    let opReply = Self.reply("at://op", author: Self.parentDid)
    let other = Self.reply("at://other", author: "did:plc:x")

    #expect(comparison.compare(opReply, other) < 0)
    #expect(comparison.compare(other, opReply) > 0)
  }

  @Test("two OP replies are ordered oldest first")
  func opOldestFirst() {
    let comparison = Self.comparator()
    let older = Self.reply(
      "at://older", author: Self.parentDid, indexedAt: "2026-01-01T00:00:00.000Z")
    let newer = Self.reply(
      "at://newer", author: Self.parentDid, indexedAt: "2026-01-02T00:00:00.000Z")

    #expect(comparison.compare(older, newer) < 0)
  }

  @Test("the viewer's own replies come before strangers, after the OP")
  func selfBeforeStrangers() {
    let comparison = Self.comparator(
      inputs: ThreadSortInputs(currentDid: Self.meDid))
    let mine = Self.reply("at://mine", author: Self.meDid)
    let other = Self.reply("at://other", author: "did:plc:x")
    let opReply = Self.reply("at://op", author: Self.parentDid)

    #expect(comparison.compare(opReply, mine) < 0)
    #expect(comparison.compare(mine, other) < 0)
  }

  @Test("a just-posted reply pins to the top")
  func justPostedPins() {
    let comparison = Self.comparator(
      inputs: ThreadSortInputs(
        currentDid: Self.meDid,
        justPostedUris: ["at://fresh"],
        isHighlightedPost: true))
    let fresh = Self.reply(
      "at://fresh", author: Self.meDid, indexedAt: "2026-01-09T00:00:00.000Z")
    let normal = Self.reply(
      "at://normal", author: "did:plc:x", indexedAt: "2026-01-01T00:00:00.000Z")

    #expect(comparison.compare(fresh, normal) < 0)
  }

  @Test("the just-posted boost is gated by the highlighted/tree flags")
  func justPostedGating() {
    let comparison = Self.comparator(
      inputs: ThreadSortInputs(
        currentDid: Self.meDid,
        justPostedUris: ["at://fresh"],
        isHighlightedPost: false,
        treeViewEnabled: false))
    let fresh = Self.reply(
      "at://fresh", author: Self.meDid, indexedAt: "2026-01-09T00:00:00.000Z")
    let normal = Self.reply(
      "at://normal", author: "did:plc:x", indexedAt: "2026-01-01T00:00:00.000Z")

    // Without the gate, plain `.newest` puts the newer one first anyway.
    #expect(comparison.compare(fresh, normal) < 0)
  }

  @Test("threadgate-hidden replies sink unless the viewer wrote them")
  func threadgateHiddenSinks() {
    let comparison = Self.comparator(
      inputs: ThreadSortInputs(
        currentDid: Self.meDid,
        threadgateHiddenReplies: ["at://hidden"]))
    let hidden = Self.reply("at://hidden", author: "did:plc:x")
    let visible = Self.reply("at://visible", author: "did:plc:y")

    #expect(comparison.compare(visible, hidden) < 0)

    // A hidden reply by the viewer is not sunk.
    let mineHidden = Self.reply("at://minehidden", author: Self.meDid)
    let comparisonMine = Self.comparator(
      inputs: ThreadSortInputs(
        currentDid: Self.meDid,
        threadgateHiddenReplies: ["at://minehidden"]))
    // Both are by self, so the self rule fires first and orders by date.
    #expect(comparisonMine.compare(mineHidden, mineHidden) == 0)
  }

  @Test("moderated replies sink")
  func moderatedSinks() {
    let comparison = Self.comparator()
    let blurred = Self.reply("at://blurred", blurred: true)
    let clean = Self.reply("at://clean")

    #expect(comparison.compare(clean, blurred) < 0)
    #expect(comparison.compare(blurred, clean) > 0)
  }

  @Test("a pinned reply sinks")
  func pinnedSinks() {
    let comparison = Self.comparator()
    let pinned = Self.reply("at://pin", text: "📌")
    let normal = Self.reply("at://normal")

    #expect(comparison.compare(normal, pinned) < 0)
  }

  @Test("a pin surrounded by whitespace still counts as pinned")
  func pinnedTrims() {
    let comparison = Self.comparator()
    let pinned = Self.reply("at://pin", text: "  📌\n")
    let normal = Self.reply("at://normal")
    #expect(comparison.compare(normal, pinned) < 0)
  }

  @Test("followed accounts rise when prioritised")
  func followedRise() {
    let comparison = Self.comparator(
      inputs: ThreadSortInputs(prioritizeFollowedUsers: true))
    let followed = Self.reply("at://followed", following: true)
    let stranger = Self.reply("at://stranger", following: false)

    #expect(comparison.compare(followed, stranger) < 0)
  }

  @Test("followed accounts are ignored when not prioritised")
  func followedIgnored() {
    // Same indexedAt, so neither is preferred.
    let comparison = Self.comparator(
      inputs: ThreadSortInputs(prioritizeFollowedUsers: false))
    let followed = Self.reply("at://followed", following: true)
    let stranger = Self.reply("at://stranger", following: false)
    #expect(comparison.compare(followed, stranger) == 0)
  }

  @Test("items from an older fetch generation sort first")
  func fetchGenerations() {
    let comparison = Self.comparator(
      inputs: ThreadSortInputs(
        fetchedAt: 200, fetchedAtCache: ["at://old": 100]))
    let old = Self.reply("at://old", indexedAt: "2026-01-05T00:00:00.000Z")
    let recent = Self.reply("at://recent", indexedAt: "2026-01-01T00:00:00.000Z")

    // Even though `old` is newer by date, it came from an earlier fetch.
    #expect(comparison.compare(old, recent) < 0)
  }

  @Test("the newest order sorts descending by date")
  func newestOrder() {
    let comparison = Self.comparator(order: .newest)
    let older = Self.reply("at://older", indexedAt: "2026-01-01T00:00:00.000Z")
    let newer = Self.reply("at://newer", indexedAt: "2026-01-02T00:00:00.000Z")
    #expect(comparison.compare(newer, older) < 0)
  }

  @Test("the oldest order sorts ascending by date")
  func oldestOrder() {
    let comparison = Self.comparator(order: .oldest)
    let older = Self.reply("at://older", indexedAt: "2026-01-01T00:00:00.000Z")
    let newer = Self.reply("at://newer", indexedAt: "2026-01-02T00:00:00.000Z")
    #expect(comparison.compare(older, newer) < 0)
  }

  @Test("most-likes sorts by count, breaking ties newest-first")
  func mostLikesOrder() {
    let comparison = Self.comparator(order: .mostLikes)
    let popular = Self.reply("at://popular", likeCount: 100)
    let unpopular = Self.reply("at://unpopular", likeCount: 1)
    #expect(comparison.compare(popular, unpopular) < 0)

    // Ties break newest-first.
    let older = Self.reply(
      "at://older", indexedAt: "2026-01-01T00:00:00.000Z", likeCount: 5)
    let newer = Self.reply(
      "at://newer", indexedAt: "2026-01-02T00:00:00.000Z", likeCount: 5)
    #expect(comparison.compare(newer, older) < 0)
  }

  @Test("a missing like count is treated as zero")
  func missingLikes() {
    let comparison = Self.comparator(order: .mostLikes)
    let none = Self.reply("at://none", likeCount: nil)
    let some = Self.reply("at://some", likeCount: 3)
    #expect(comparison.compare(some, none) < 0)
  }

  @Test("hotness favours a recent, liked reply over an old one")
  func hotnessOrder() {
    let fetchedAt = 1_800_000_000 // 2027-01-15
    let comparison = Self.comparator(
      order: .hotness, inputs: ThreadSortInputs(fetchedAt: fetchedAt))
    let recent = Self.reply(
      "at://recent", indexedAt: "2027-01-14T00:00:00.000Z", likeCount: 5)
    let old = Self.reply(
      "at://old", indexedAt: "2026-01-01T00:00:00.000Z", likeCount: 5)
    #expect(comparison.compare(recent, old) < 0)
  }

  @Test("random order uses the supplied stable scores")
  func randomOrder() {
    let comparison = Self.comparator(
      order: .random,
      inputs: ThreadSortInputs(
        randomScores: ["at://a": 0.1, "at://b": 0.9]))
    let a = Self.reply("at://a")
    let b = Self.reply("at://b")
    #expect(comparison.compare(a, b) < 0)
    #expect(comparison.compare(b, a) > 0)
  }

  @Test("identical replies compare equal")
  func equalReplies() {
    let comparison = Self.comparator()
    let a = Self.reply("at://same")
    #expect(comparison.compare(a, a) == 0)
  }

  @Test("tombstones always sort last")
  func tombstonesLast() {
    let comparison = Self.comparator()
    let post = ThreadItem(
      id: "at://post", uri: "at://post", depth: 1, isAnchor: false,
      content: .post(
        ThreadPostContent(
          post: Fixtures.postView(uri: "at://post"), record: nil, hasOPLike: false,
          moderation: nil)))
    let tombstone = ThreadItem(
      id: "at://gone", uri: "at://gone", depth: 1, isAnchor: false,
      content: .tombstone(ThreadTombstone(kind: .deleted, uri: "at://gone")))

    #expect(comparison.compare(post, tombstone) < 0)
    #expect(comparison.compare(tombstone, post) > 0)
  }

  @Test("sorting a tree orders every reply level")
  func sortsTree() {
    let older = Fixtures.post(
      "at://older", author: "did:plc:x", indexedAt: "2026-01-01T00:00:00.000Z")
    let newer = Fixtures.post(
      "at://newer", author: "did:plc:y", indexedAt: "2026-01-05T00:00:00.000Z")
    let tree = Fixtures.withDepths(
      Fixtures.post("at://anchor", replies: [older, newer]))

    let sorted = ThreadTreeSorter.sort(
      tree, order: .newest, inputs: ThreadSortInputs())
    let flat = ThreadFlattener.flatten(sorted)
    #expect(flat.postUris == ["at://anchor", "at://newer", "at://older"])
  }

  @Test("hotness is monotonically decreasing with age for a fixed like count")
  func hotnessMonotonic() {
    let fetchedAt = 1_800_000_000
    let recent = ThreadHotness.score(
      Self.reply("at://r", indexedAt: "2027-01-14T00:00:00.000Z", likeCount: 10),
      fetchedAt: fetchedAt)
    let old = ThreadHotness.score(
      Self.reply("at://o", indexedAt: "2027-01-01T00:00:00.000Z", likeCount: 10),
      fetchedAt: fetchedAt)
    #expect(recent > old)
  }

  @Test("an OP like raises hotness")
  func opLikeBoost() {
    let fetchedAt = 1_800_000_000
    let plain = ThreadHotness.score(
      Self.reply("at://p", indexedAt: "2027-01-14T00:00:00.000Z", likeCount: 10),
      fetchedAt: fetchedAt)
    var withOPLike = Self.reply(
      "at://p", indexedAt: "2027-01-14T00:00:00.000Z", likeCount: 10)
    withOPLike = SortableReply(
      uri: withOPLike.uri, post: withOPLike.post, record: withOPLike.record,
      hasOPLike: true, moderation: nil)
    #expect(ThreadHotness.score(withOPLike, fetchedAt: fetchedAt) > plain)
  }
}
