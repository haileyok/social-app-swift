import Foundation
import PostThreadLogic

/// The copy the thread surfaces show.
///
/// This is the strings seam, in the same shape `UIComponentsCore.ListStrings`
/// uses for feed lists: one value with every user-facing string on it, with a
/// `.defaults` instance for production and the ability to hand a screen a
/// different instance in a preview or a future test. The strings themselves are
/// the RN thread screen's, so a translator only has to look in one place.
///
/// ```swift
/// PostThreadScreen(thread: fixture)             // PostThreadStrings.defaults
/// PostThreadScreen(thread: fixture, strings: .init(...))
/// ```
public enum ThreadEngagementKind: Hashable, Sendable {
  case reposts
  case quotes
  case likes
}

public struct PostThreadStrings: Equatable, Sendable {
  /// The screen/navigation title.
  public let title: String

  /// The tombstone copy, one per ``ThreadTombstoneKind``.
  public let deletedPost: String
  public let blockedPost: String
  public let hiddenPost: String

  /// The reply-count line under a tombstone, e.g. "3 replies".
  public let replyCount: String

  /// The context line above a reply the original poster liked.
  public let likedByAuthor: String

  /// "Load more replies" - the row that widens the reply window.
  public let loadMoreReplies: String
  /// "Load more" - the row that reveals another chunk of ancestors.
  public let loadMoreParents: String
  /// The read-more row that continues an ancestor chain upwards.
  public let showMoreParents: String
  /// The count suffix on a read-more row, e.g. "Show 4 more replies".
  public let showMoreRepliesFormat: String

  /// The bottom composer affordance.
  public let replyPlaceholder: String

  /// Singular/plural labels in the focused post's engagement summary.
  public let repost: String
  public let reposts: String
  public let quote: String
  public let quotes: String
  public let like: String
  public let likes: String
  public let reply: String
  public let replies: String

  /// The likes/reposts/quotes list titles.
  public let likedByTitle: String
  public let repostedByTitle: String
  public let quotesTitle: String
  /// The empty states for those lists.
  public let likedByEmpty: String
  public let repostedByEmpty: String
  public let quotesEmpty: String

  /// The blocked / not-found full-screen placeholders.
  public let blockedTitle: String
  public let blockedMessage: String
  public let notFoundTitle: String
  public let notFoundMessage: String

  /// The "other replies" affordance, for replies moderation moved out of the
  /// inline list.
  public let otherReplies: String

  public let retry: String

  public init(
    title: String = "Post",
    deletedPost: String = "Post has been deleted",
    blockedPost: String = "Post hidden by block",
    hiddenPost: String = "Post hidden by moderation",
    replyCount: String = "replies",
    likedByAuthor: String = "Liked by author",
    loadMoreReplies: String = "Load more replies",
    loadMoreParents: String = "Load more",
    showMoreParents: String = "Show more",
    showMoreRepliesFormat: String = "Show %d more replies",
    replyPlaceholder: String = "Write a reply",
    repost: String = "repost",
    reposts: String = "reposts",
    quote: String = "quote",
    quotes: String = "quotes",
    like: String = "like",
    likes: String = "likes",
    reply: String = "reply",
    replies: String = "replies",
    likedByTitle: String = "Likes",
    repostedByTitle: String = "Reposts",
    quotesTitle: String = "Quotes",
    likedByEmpty: String = "No likes yet",
    repostedByEmpty: String = "No reposts yet",
    quotesEmpty: String = "No quotes yet",
    blockedTitle: String = "Blocked",
    blockedMessage: String = "You have blocked this account, or it has blocked you.",
    notFoundTitle: String = "Post not found",
    notFoundMessage: String = "This post was deleted or is unavailable.",
    otherReplies: String = "Show other replies",
    retry: String = "Retry"
  ) {
    self.title = title
    self.deletedPost = deletedPost
    self.blockedPost = blockedPost
    self.hiddenPost = hiddenPost
    self.replyCount = replyCount
    self.likedByAuthor = likedByAuthor
    self.loadMoreReplies = loadMoreReplies
    self.loadMoreParents = loadMoreParents
    self.showMoreParents = showMoreParents
    self.showMoreRepliesFormat = showMoreRepliesFormat
    self.replyPlaceholder = replyPlaceholder
    self.repost = repost
    self.reposts = reposts
    self.quote = quote
    self.quotes = quotes
    self.like = like
    self.likes = likes
    self.reply = reply
    self.replies = replies
    self.likedByTitle = likedByTitle
    self.repostedByTitle = repostedByTitle
    self.quotesTitle = quotesTitle
    self.likedByEmpty = likedByEmpty
    self.repostedByEmpty = repostedByEmpty
    self.quotesEmpty = quotesEmpty
    self.blockedTitle = blockedTitle
    self.blockedMessage = blockedMessage
    self.notFoundTitle = notFoundTitle
    self.notFoundMessage = notFoundMessage
    self.otherReplies = otherReplies
    self.retry = retry
  }

  /// The production strings.
  public static let `defaults` = PostThreadStrings()

  /// The tombstone copy for a kind.
  public func tombstone(_ kind: ThreadTombstoneKind) -> String {
    switch kind {
    case .deleted: deletedPost
    case .blocked: blockedPost
    case .hiddenByModeration: hiddenPost
    }
  }
}
