import HomeFeedLogic
import Lexicons
import Moderation
import RichText
import UIComponents
import UIComponentsCore

/// The repost/pin attribution line above a feed row.
///
/// Port of `src/view/com/posts/PostFeedReason.tsx`, which renders one line above
/// the post for `reasonRepost` and `reasonPin` and nothing otherwise.
public enum HomeFeedReasonLine: Equatable, Sendable {
  /// `Reposted by <name>`, or `Reposted by you` when the viewer is the reposter.
  case repost(name: String, isViewer: Bool)
  /// The pinned-post marker, RN's `Pinned`.
  case pinned

  /// The line's text.
  public var text: String {
    switch self {
    case .repost(let name, let isViewer):
      return isViewer ? HomeFeedStrings.repostedByYou : HomeFeedStrings.repostedBy(name)
    case .pinned:
      return HomeFeedStrings.pinned
    }
  }

  /// The leading SF Symbol, matching the RN reason icons.
  public var systemImage: String {
    switch self {
    case .repost: return "arrow.2.squarepath"
    case .pinned: return "pin.fill"
    }
  }
}

/// One rendered post inside a row.
public struct HomeFeedRowItem: Identifiable {
  /// The item's react key, which already carries the slice key and index.
  public let id: String
  /// The post's `at://` URI - the navigation target for a body tap. The
  /// react key is display-only and must never be used as a URI.
  public let uri: String
  /// The data `PostFeedItem` renders.
  public let data: FeedItemViewData
  /// True when a reply connector should be drawn above this item - i.e. it is
  /// part of a merged thread and is not the slice's selected post.
  public let showsReplyLine: Bool

  public init(id: String, uri: String, data: FeedItemViewData, showsReplyLine: Bool) {
    self.id = id
    self.uri = uri
    self.data = data
    self.showsReplyLine = showsReplyLine
  }
}

/// One row of the Home feed: a tuned slice, flattened for rendering.
///
/// A ``HomeFeedSlice`` is a thread group; the RN list renders it as a stack of
/// posts with a connector between them (`showReplyLine` in
/// `src/view/com/post/Post.tsx`). Flattening that here keeps the view a loop
/// over precomputed rows and keeps every display decision testable by
/// inspection.
public struct HomeFeedRow: Identifiable {
  /// The slice's react key. ``HomeFeedLogic/HomeFeedQuery`` de-duplicates on
  /// exactly this value, so it is unique across a feed's pages.
  public let id: String
  /// The reason line, when the slice carried one.
  public let reason: HomeFeedReasonLine?
  /// The posts in the row, oldest first.
  public let items: [HomeFeedRowItem]
  /// True when the slice merged more than one post.
  public let isThreadMerged: Bool

  public init(id: String, reason: HomeFeedReasonLine?, items: [HomeFeedRowItem], isThreadMerged: Bool) {
    self.id = id
    self.reason = reason
    self.items = items
    self.isThreadMerged = isThreadMerged
  }

  /// A row is skipped entirely when every post in it was filtered by moderation;
  /// there is nothing to draw, not even a mask.
  public var isRenderable: Bool {
    items.contains { $0.data.moderation.content.isVisible }
  }

  /// Remote assets to warm before this row enters the viewport.
  public var imageURLs: [URL] {
    items.flatMap(\.data.imageURLs)
  }
}

/// Turns tuned slices into render rows.
public enum HomeFeedViewData {
  /// Maps a page's slices to rows.
  ///
  /// - Parameters:
  ///   - slices: the tuned slices, in feed order.
  ///   - moderationOpts: the engine options, or `nil` to render everything
  ///     unmasked (the demo and logged-out paths).
  ///   - viewerDid: the signed-in DID, so a repost by the viewer reads
  ///     "Reposted by you" the way RN does.
  ///   - options: the render options (clock and locale) shared by every row.
  public static func rows(
    _ slices: [HomeFeedSlice],
    moderationOpts: ModerationOpts?,
    viewerDid: String? = nil,
    options: FeedItemRenderOptions = FeedItemRenderOptions()
  ) -> [HomeFeedRow] {
    slices.map { slice in
      row(slice, moderationOpts: moderationOpts, viewerDid: viewerDid, options: options)
    }
    // A slice the tuner kept but that moderation hides completely is dropped
    // rather than rendered as an empty mask, matching RN's filtered list.
    .filter(\.isRenderable)
  }

  /// Maps one slice to a row.
  public static func row(
    _ slice: HomeFeedSlice,
    moderationOpts: ModerationOpts?,
    viewerDid: String? = nil,
    options: FeedItemRenderOptions = FeedItemRenderOptions()
  ) -> HomeFeedRow {
    let items = slice.items.enumerated().map { index, item in
      HomeFeedRowItem(
        id: item.reactKey.isEmpty ? item.uri : item.reactKey,
        uri: item.uri,
        data: viewData(
          item,
          slice: slice,
          isSelectedPost: index == slice.items.count - 1,
          moderationOpts: moderationOpts,
          options: options),
        // The selected (last) post is the row's subject; earlier posts in a
        // merged thread are the reply chain above it.
        showsReplyLine: index < slice.items.count - 1)
    }
    return HomeFeedRow(
      id: slice.reactKey,
      reason: reasonLine(slice, viewerDid: viewerDid),
      items: items,
      isThreadMerged: items.count > 1)
  }

  /// The reason line for a slice, or `nil`.
  static func reasonLine(_ slice: HomeFeedSlice, viewerDid: String?) -> HomeFeedReasonLine? {
    switch slice.reason {
    case .feedDefsReasonRepost(let repost):
      let by = repost.by
      let name = displayName(
        displayName: by.displayName, handle: by.handle.rawValue)
      let isViewer = viewerDid != nil && by.did.rawValue == viewerDid
      return .repost(name: name, isViewer: isViewer)
    case .feedDefsReasonPin:
      return .pinned
    case ._other, .none:
      return nil
    }
  }

  /// Builds the view data for one item.
  static func viewData(
    _ item: HomeFeedSliceItem,
    slice: HomeFeedSlice,
    isSelectedPost: Bool,
    moderationOpts: ModerationOpts?,
    options: FeedItemRenderOptions
  ) -> FeedItemViewData {
    let subject = LexiconModeration.subject(item.post)
    let decision = moderationOpts.map { moderatePost(subject, opts: $0) } ?? ModerationDecision()
    return feedItemViewData(
      subject,
      counts: FeedItemCounts(
        replyCount: item.post.replyCount,
        repostCount: item.post.repostCount,
        likeCount: item.post.likeCount),
      decision: decision,
      options: renderOptions(
        for: item,
        slice: slice,
        isSelectedPost: isSelectedPost,
        options: options))
  }

  /// The render options with this item's context line filled in.
  ///
  /// The context line is the reply attribution the RN feed shows when a slice's
  /// subject is a reply: `Replying to @handle`, or the parent's blocked/not-found
  /// variants when the parent could not be resolved.
  static func renderOptions(
    for item: HomeFeedSliceItem,
    slice: HomeFeedSlice,
    isSelectedPost: Bool,
    options: FeedItemRenderOptions
  ) -> FeedItemRenderOptions {
    guard isSelectedPost, let contextLine = contextLine(item, slice: slice) else {
      return options
    }
    return FeedItemRenderOptions(
      now: options.now, locale: options.locale, contextLine: contextLine)
  }

  /// The reply context line for an item, or `nil` when the post is not a reply.
  static func contextLine(_ item: HomeFeedSliceItem, slice: HomeFeedSlice) -> String? {
    if item.isParentBlocked {
      return blockedParentText
    }
    if item.isParentNotFound {
      return notFoundParentText
    }
    guard let parent = item.parentAuthor else { return nil }
    return HomeFeedStrings.replyingTo(parent.handle.rawValue)
  }

  /// A display name or a handle, trimmed, the way the RN sanitizer falls back.
  static func displayName(displayName: String?, handle: String) -> String {
    let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty { return trimmed }
    return handle
  }

  /// RN's `PostFeed` parent-unavailable copy.
  static let blockedParentText = "Reply to a blocked post"
  /// RN's `PostFeed` parent-not-found copy.
  static let notFoundParentText = "Reply to a post that could not be found"
}
