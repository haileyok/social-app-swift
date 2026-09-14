import Foundation
import Lexicons
import Moderation

/// How replies are ordered. Port of the `sort` field on RN's
/// `threadViewPrefs` (`state/queries/preferences/useThreadPreferences.ts`).
public enum ThreadSortOrder: String, Sendable, Hashable, CaseIterable {
  case hotness
  case oldest
  case newest
  case mostLikes = "most-likes"
  case random
}

/// Everything the comparator needs beyond the two items being compared.
///
/// RN's `sortThread` reads several pieces of ambient state (the viewer, the
/// set of just-posted uris, a fetched-at stamp, a moderation cache and a random
/// score cache) rather than comparing the nodes in isolation. Modelling that as
/// inputs keeps the comparator pure and testable.
public struct ThreadSortInputs: Sendable {
  /// The signed-in account's DID, or `nil` when logged out.
  public var currentDid: String?
  /// Urls posted by the viewer during this session, which pin to the top.
  public var justPostedUris: Set<String>
  /// Urls hidden by the threadgate record; they sink unless authored by the
  /// viewer.
  public var threadgateHiddenReplies: Set<String>
  /// When true, replies from accounts the viewer follows sort first.
  public var prioritizeFollowedUsers: Bool
  /// Whether the anchor is the highlighted post (always true for the post
  /// screen). Gates the just-posted boost, as in RN.
  public var isHighlightedPost: Bool
  /// Whether the tree view is enabled. Together with `isHighlightedPost` this
  /// gates the just-posted boost.
  public var treeViewEnabled: Bool
  /// The fetch generation stamp. Items from different fetches never interleave.
  public var fetchedAt: Int
  /// Per-uri fetch stamps, mutated as new uris are seen.
  public var fetchedAtCache: [String: Int]
  /// Stable random scores per uri, so `.random` does not reshuffle on re-sort.
  public var randomScores: [String: Double]
  /// Moderation decisions, keyed by uri.
  public var moderationDecisions: [String: ModerationDecision]

  public init(
    currentDid: String? = nil,
    justPostedUris: Set<String> = [],
    threadgateHiddenReplies: Set<String> = [],
    prioritizeFollowedUsers: Bool = false,
    isHighlightedPost: Bool = true,
    treeViewEnabled: Bool = false,
    fetchedAt: Int = 0,
    fetchedAtCache: [String: Int] = [:],
    randomScores: [String: Double] = [:],
    moderationDecisions: [String: ModerationDecision] = [:]
  ) {
    self.currentDid = currentDid
    self.justPostedUris = justPostedUris
    self.threadgateHiddenReplies = threadgateHiddenReplies
    self.prioritizeFollowedUsers = prioritizeFollowedUsers
    self.isHighlightedPost = isHighlightedPost
    self.treeViewEnabled = treeViewEnabled
    self.fetchedAt = fetchedAt
    self.fetchedAtCache = fetchedAtCache
    self.randomScores = randomScores
    self.moderationDecisions = moderationDecisions
  }
}

/// The minimal view of a reply the comparator needs, so the same ordering can
/// be applied to tree nodes (before flattening) and flat rows (after).
public struct SortableReply: Sendable {
  public let uri: String
  public let post: App.Bsky.FeedDefs_PostView
  public let record: App.Bsky.FeedPost?
  public let hasOPLike: Bool
  public let moderation: ModerationDecision?

  public init(
    uri: String,
    post: App.Bsky.FeedDefs_PostView,
    record: App.Bsky.FeedPost?,
    hasOPLike: Bool,
    moderation: ModerationDecision?
  ) {
    self.uri = uri
    self.post = post
    self.record = record
    self.hasOPLike = hasOPLike
    self.moderation = moderation
  }
}

/// RN's reply comparator, lifted out of `sortThread`
/// (`state/queries/post-thread.ts`).
///
/// The order of the checks *is* the behaviour, so it is preserved exactly:
///
/// 1. non-post nodes (tombstones) always sort last;
/// 2. replies posted during this session pin to the top;
/// 3. the OP's own replies come next, oldest first;
/// 4. the viewer's own replies, oldest first;
/// 5. threadgate-hidden replies sink, unless the viewer wrote them;
/// 6. moderated (blurred in the content list) replies sink;
/// 7. pinned replies (a bare pin emoji) sink;
/// 8. optionally, followed accounts rise;
/// 9. items from an older fetch generation always come first, so a refresh
///    does not interleave with what the user is already reading;
/// 10. finally the selected sort order.
public struct ThreadReplyComparator: Sendable {
  let parentAuthorDid: String
  let inputs: ThreadSortInputs
  let order: ThreadSortOrder

  public init(
    parentAuthorDid: String,
    inputs: ThreadSortInputs,
    order: ThreadSortOrder
  ) {
    self.parentAuthorDid = parentAuthorDid
    self.inputs = inputs
    self.order = order
  }

  /// Compares two flat rows. Returns `true` when `a` sorts before `b`.
  public func sortsBefore(_ a: ThreadItem, _ b: ThreadItem) -> Bool {
    compare(a, b) < 0
  }

  /// Compares two tree nodes. Returns `true` when `a` sorts before `b`.
  public func sortsBefore(_ a: ThreadNode, _ b: ThreadNode) -> Bool {
    compare(a, b) < 0
  }

  /// The sign of the comparison for two rows, matching RN's
  /// `Array.prototype.sort` comparator.
  public func compare(_ a: ThreadItem, _ b: ThreadItem) -> Int {
    guard case .post(let postA) = a.content else { return 1 }
    guard case .post(let postB) = b.content else { return -1 }
    return compare(SortableReply(postA), SortableReply(postB))
  }

  /// The sign of the comparison for two tree nodes.
  public func compare(_ a: ThreadNode, _ b: ThreadNode) -> Int {
    guard case .post(let nodeA) = a else { return 1 }
    guard case .post(let nodeB) = b else { return -1 }
    return compare(SortableReply(nodeA), SortableReply(nodeB))
  }

  /// The ordering itself: RN's chain of checks, in order.
  public func compare(_ a: SortableReply, _ b: SortableReply) -> Int {
    if let boost = compareJustPosted(a, b) { return boost }
    if let author = compareAuthorship(a, b) { return author }
    if let visibility = compareVisibility(a, b) { return visibility }
    if let follow = compareFollowing(a, b) { return follow }
    if let generation = compareFetchGeneration(a, b) { return generation }
    return compareByOrder(a, b, fetchedAt: inputs.fetchedAtCache[a.uri] ?? inputs.fetchedAt)
  }

  /// The just-posted pin, gated on the highlighted/tree flags as RN does.
  private func compareJustPosted(_ a: SortableReply, _ b: SortableReply) -> Int? {
    guard inputs.isHighlightedPost || inputs.treeViewEnabled else { return nil }
    let aJustPosted = isJustPosted(a)
    let bJustPosted = isJustPosted(b)
    if aJustPosted && bJustPosted {
      return compareIndexedAtOldestFirst(a, b)
    } else if aJustPosted {
      return -1
    } else if bJustPosted {
      return 1
    }
    return nil
  }

  /// The OP's own replies, then the viewer's own replies, each oldest first.
  private func compareAuthorship(_ a: SortableReply, _ b: SortableReply) -> Int? {
    let aIsByOP = a.post.author.did.rawValue == parentAuthorDid
    let bIsByOP = b.post.author.did.rawValue == parentAuthorDid
    if aIsByOP && bIsByOP {
      return compareIndexedAtOldestFirst(a, b)
    } else if aIsByOP {
      return -1
    } else if bIsByOP {
      return 1
    }

    let aIsBySelf = isBySelf(a)
    let bIsBySelf = isBySelf(b)
    if aIsBySelf && bIsBySelf {
      return compareIndexedAtOldestFirst(a, b)
    } else if aIsBySelf {
      return -1
    } else if bIsBySelf {
      return 1
    }
    return nil
  }

  /// Threadgate-hidden, moderated and pinned replies all sink.
  private func compareVisibility(_ a: SortableReply, _ b: SortableReply) -> Int? {
    let aIsBySelf = isBySelf(a)
    let bIsBySelf = isBySelf(b)

    let aHidden = inputs.threadgateHiddenReplies.contains(a.uri)
    let bHidden = inputs.threadgateHiddenReplies.contains(b.uri)
    if aHidden && !aIsBySelf && !bHidden {
      return 1
    } else if bHidden && !bIsBySelf && !aHidden {
      return -1
    }

    let aBlur = isBlurred(a)
    let bBlur = isBlurred(b)
    if aBlur != bBlur {
      return aBlur ? 1 : -1
    }

    let aPinned = isPinned(a)
    let bPinned = isPinned(b)
    if aPinned != bPinned {
      return aPinned ? 1 : -1
    }
    return nil
  }

  /// Followed accounts rise, when the preference is on.
  private func compareFollowing(_ a: SortableReply, _ b: SortableReply) -> Int? {
    guard inputs.prioritizeFollowedUsers else { return nil }
    let aFollows = a.post.author.viewer?.following != nil
    let bFollows = b.post.author.viewer?.following != nil
    if aFollows && !bFollows {
      return -1
    } else if !aFollows && bFollows {
      return 1
    }
    return nil
  }

  /// Items from an older fetch generation always come first, so a refresh does
  /// not interleave with what the user is already reading.
  private func compareFetchGeneration(_ a: SortableReply, _ b: SortableReply) -> Int? {
    let aFetchedAt = inputs.fetchedAtCache[a.uri] ?? inputs.fetchedAt
    let bFetchedAt = inputs.fetchedAtCache[b.uri] ?? inputs.fetchedAt
    if aFetchedAt != bFetchedAt {
      return aFetchedAt - bFetchedAt
    }
    return nil
  }

  private func compareByOrder(
    _ a: SortableReply,
    _ b: SortableReply,
    fetchedAt: Int
  ) -> Int {
    switch order {
    case .hotness:
      let aHotness = ThreadHotness.score(a, fetchedAt: fetchedAt)
      let bHotness = ThreadHotness.score(b, fetchedAt: fetchedAt)
      // Descending hotness.
      if aHotness == bHotness { return 0 }
      return aHotness > bHotness ? -1 : 1
    case .oldest:
      return compareIndexedAtOldestFirst(a, b)
    case .newest:
      return compareIndexedAtOldestFirst(b, a)
    case .mostLikes:
      let aLikes = a.post.likeCount ?? 0
      let bLikes = b.post.likeCount ?? 0
      if aLikes == bLikes {
        return compareIndexedAtOldestFirst(b, a) // newest
      }
      // Descending like count.
      return aLikes > bLikes ? -1 : 1
    case .random:
      let aScore = inputs.randomScores[a.uri] ?? 0
      let bScore = inputs.randomScores[b.uri] ?? 0
      if aScore == bScore { return 0 }
      return aScore < bScore ? -1 : 1
    }
  }

  private func isJustPosted(_ reply: SortableReply) -> Bool {
    guard let did = inputs.currentDid else { return false }
    return reply.post.author.did.rawValue == did
      && inputs.justPostedUris.contains(reply.uri)
  }

  private func isBySelf(_ reply: SortableReply) -> Bool {
    guard let did = inputs.currentDid else { return false }
    return reply.post.author.did.rawValue == did
  }

  private func isBlurred(_ reply: SortableReply) -> Bool {
    reply.moderation?.ui(.contentList).blur == true
  }

  /// A post whose entire text is a pin emoji is pinned to the bottom of the
  /// replies. Port of RN's `a.record.text.trim() === '📌'`.
  private func isPinned(_ reply: SortableReply) -> Bool {
    reply.record?.text.trimmingCharacters(in: .whitespacesAndNewlines) == "📌"
  }

  /// `indexedAt` compared as strings, exactly as RN does
  /// (`a.post.indexedAt.localeCompare(b.post.indexedAt)`). ISO-8601 timestamps
  /// with a fixed precision compare correctly as strings, and following RN here
  /// keeps the ordering identical for the odd records it also produces.
  private func compareIndexedAtOldestFirst(
    _ a: SortableReply,
    _ b: SortableReply
  ) -> Int {
    let aValue = a.post.indexedAt.rawValue
    let bValue = b.post.indexedAt.rawValue
    if aValue == bValue { return 0 }
    return aValue < bValue ? -1 : 1
  }
}

extension SortableReply {
  init(_ content: ThreadPostContent) {
    self.init(
      uri: content.post.uri.rawValue,
      post: content.post,
      record: content.record,
      hasOPLike: content.hasOPLike,
      moderation: content.moderation)
  }

  init(_ node: ThreadPostNode) {
    self.init(
      uri: node.post.uri.rawValue,
      post: node.post,
      record: node.record,
      hasOPLike: node.hasOPLike,
      moderation: nil)
  }
}

/// RN's `getHotness` (`state/queries/post-thread.ts`), ported verbatim.
///
/// Inspired by the Lemmy ranking algorithm: recent replies get a real chance
/// without burying well-liked older ones. An OP like boosts both the like order
/// and the time penalty (so an OP-liked reply decays faster but starts higher).
public enum ThreadHotness {
  public static func score(_ reply: SortableReply, fetchedAt: Int) -> Double {
    let indexedAt = parseDate(reply.post.indexedAt.rawValue)
    let fetchedDate = Date(timeIntervalSince1970: TimeInterval(fetchedAt))
    let hoursAgo = max(
      0,
      (fetchedDate.timeIntervalSince(indexedAt ?? fetchedDate)) / (60 * 60)
    )
    let likeCount = Double(reply.post.likeCount ?? 0)
    let hasOPLike = reply.hasOPLike
    let likeOrder = log(3 + likeCount) * (hasOPLike ? 1.45 : 1.0)
    let timePenaltyExponent = 1.5 + 1.5 / (1 + log(1 + likeCount))
    let opLikeBoost = hasOPLike ? 0.8 : 1.0
    let timePenalty = pow(hoursAgo + 2, timePenaltyExponent * opLikeBoost)
    return likeOrder / timePenalty
  }

  /// Parses an ISO-8601 timestamp. `FormatString<Date>` keeps the wire string
  /// and parses on demand, so this mirrors that parse without throwing.
  static func parseDate(_ raw: String) -> Date? {
    // Formatters are built per call: `ISO8601DateFormatter` is not `Sendable`
    // and a shared static would be a data race under strict concurrency.
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: raw) { return date }

    let withoutFractional = ISO8601DateFormatter()
    withoutFractional.formatOptions = [.withInternetDateTime]
    return withoutFractional.date(from: raw)
  }
}
