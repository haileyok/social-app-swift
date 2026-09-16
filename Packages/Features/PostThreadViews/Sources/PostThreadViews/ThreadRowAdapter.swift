import Foundation
import Lexicons
import Moderation
import PostThreadLogic
import UIComponentsCore

/// Adapters from ``PostThreadLogic``'s row model onto the widgets
/// `UIComponents` renders.
///
/// The logic package owns the shapes the server gives us; `UIComponents` owns
/// the shapes the views draw. Neither knows about the other, so this file is
/// the seam - the same job `PostModerationAdapter` does for the Moderation
/// engine and `feedItemViewData` does for feed rows.
enum ThreadRowAdapter {
  /// The render data for a hydrated post row.
  ///
  /// Counts come off the `#postView` rather than the row, and the author's
  /// relationship to the viewer rides on the context line ("Replying to ..."),
  /// which is what the RN thread screen shows above a reply.
  static func viewData(
    for content: ThreadPostContent,
    now: Date,
    locale: Locale,
    contextLine: String?
  ) -> FeedItemViewData {
    let post = content.post
    let counts = FeedItemCounts(
      replyCount: post.replyCount,
      repostCount: post.repostCount,
      likeCount: post.likeCount)
    // The Moderation engine's subject type is bridged by the logic package, so
    // the row picks up the same decision the flattening pass applied. When the
    // row carries no decision the engine projects an empty one, i.e. render
    // normally.
    let decision = content.moderation ?? ModerationDecision()
    return feedItemViewData(
      PostModerationAdapter.subject(post),
      counts: counts,
      decision: decision,
      options: FeedItemRenderOptions(
        now: now,
        locale: locale,
        contextLine: contextLine,
        isReposted: post.viewer?.repost != nil,
        isLiked: post.viewer?.like != nil))
  }

  /// The blended indent width for a row at `depth`, matching the RN thread's
  /// reply-line indent (a fixed step per level).
  static let indentStep: Double = 16

  /// How far to indent a row: parents are not indented (they read as context
  /// above the anchor), replies indent by their distance from the anchor.
  static func indent(for item: ThreadItem) -> Double {
    Double(max(0, item.depth)) * indentStep
  }
}
