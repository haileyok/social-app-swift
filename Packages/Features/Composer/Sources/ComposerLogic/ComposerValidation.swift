import Foundation

/// The outcome of validating the composer, as a reason or nothing.
///
/// Ported from the RN `canPost` derivation and the `missingAltError` /
/// `hasUnavailableChatInvite` inputs it combines. The RN code computes a
/// boolean; keeping the *reason* means the UI can show the same copy without
/// re-deriving it.
public enum ComposerValidationError: Hashable, Sendable {
  /// `One or more images is missing alt text.`
  case imageMissingAltText
  /// `One or more GIFs is missing alt text.`
  case gifMissingAltText
  /// `One or more videos is missing alt text.`
  case videoMissingAltText
  /// A chat invite link in the thread resolved to no usable preview.
  case unavailableChatInvite
  /// A post is over ``ComposerConstants/maxGraphemeLength`` graphemes.
  case postOverGraphemeLimit(postId: String)
  /// A post's video pipeline failed, so the post cannot be published.
  case videoFailed(postId: String)
  /// Every post is empty, so there is nothing to publish.
  case nothingToPost
}

/// Whether the composer can publish, and if not, why.
///
/// Ported from the `canPost` expression in `Composer.tsx`:
///
/// ```ts
/// const canPost =
///   !missingAltError &&
///   !hasUnavailableChatInvite &&
///   thread.posts.some(post => !isEmptyPost(post)) &&
///   thread.posts.every(
///     post =>
///       isEmptyPost(post) ||
///       (post.shortenedGraphemeLength <= MAX_GRAPHEME_LENGTH &&
///         !(post.embed.media?.type === 'video' &&
///           post.embed.media.video.status === 'error')),
///   )
/// ```
///
/// Two subtleties are preserved exactly:
///
/// 1. **Empty posts are exempt from the limit and video checks.** The `every`
///    clause short-circuits on `isEmptyPost(post)`, so a blank third post never
///    blocks publishing an otherwise valid thread.
/// 2. **Alt text is checked even in the `requireAltTextEnabled == false` case
///    only when the flag is set** — see ``altTextError(requireAltText:)``.
public enum ComposerValidation {
  /// The alt-text rule, when the account requires alt text.
  ///
  /// Ported from the `missingAltError` memo. The image and GIF branches are not
  /// gated on the video status; the video branch skips a video that is already
  /// in `error`, because the video error itself is what surfaces.
  public static func altTextError(
    in thread: ThreadDraft,
    requireAltText: Bool
  ) -> ComposerValidationError? {
    guard requireAltText else { return nil }
    for post in thread.posts {
      guard let media = post.embed.media else { continue }
      switch media {
      case .images(let images):
        if images.images.contains(where: { $0.alt.isEmpty }) {
          return .imageMissingAltText
        }
      case .gif(let gif):
        if gif.alt.isEmpty { return .gifMissingAltText }
      case .video(let video):
        if video.status != "error" && video.altText.isEmpty {
          return .videoMissingAltText
        }
      }
    }
    return nil
  }

  /// Validates the whole composer.
  ///
  /// - Parameters:
  ///   - thread: the thread to validate.
  ///   - requireAltText: whether the account requires alt text on media.
  ///   - hasUnavailableChatInvite: whether any link in the thread resolved to a
  ///     chat invite with no preview (revoked or expired), which must block
  ///     publishing rather than go out without the embed.
  public static func validate(
    thread: ThreadDraft,
    requireAltText: Bool = false,
    hasUnavailableChatInvite: Bool = false
  ) -> ComposerValidationError? {
    if let altError = altTextError(in: thread, requireAltText: requireAltText) {
      return altError
    }
    if hasUnavailableChatInvite {
      return .unavailableChatInvite
    }
    guard thread.posts.contains(where: { !$0.isEmpty }) else {
      return .nothingToPost
    }
    for post in thread.posts {
      if post.isEmpty { continue }
      if post.shortenedGraphemeLength > ComposerConstants.maxGraphemeLength {
        return .postOverGraphemeLimit(postId: post.id)
      }
      if case .video(let video) = post.embed.media, video.status == "error" {
        return .videoFailed(postId: post.id)
      }
    }
    return nil
  }

  /// Whether the thread can be published.
  public static func canPost(
    thread: ThreadDraft,
    requireAltText: Bool = false,
    hasUnavailableChatInvite: Bool = false
  ) -> Bool {
    validate(
      thread: thread,
      requireAltText: requireAltText,
      hasUnavailableChatInvite: hasUnavailableChatInvite) == nil
  }
}

/// How the thread's empty posts are classified before publishing.
///
/// Ported from `getFilteredThread`. The RN publish path warns differently
/// depending on whether the empty post is merely trailing (harmless, just drop
/// it) or sits *between* non-empty posts (the user probably meant to write it).
public enum EmptyPostClassification: Hashable, Sendable {
  /// No empty posts; the thread publishes as-is.
  case none
  /// Empty posts exist, but only after the last non-empty one.
  case trailingOnly
  /// At least one empty post sits before the last non-empty post.
  case nonTrailing

  /// Whether the user should be prompted before publishing.
  public var requiresConfirmation: Bool { self == .nonTrailing }
}

/// The result of dropping empty posts from a thread.
public struct FilteredThread: Hashable, Sendable {
  /// How the dropped posts were classified.
  public let classification: EmptyPostClassification
  /// The thread with empty posts removed.
  public let thread: ThreadDraft

  public init(classification: EmptyPostClassification, thread: ThreadDraft) {
    self.classification = classification
    self.thread = thread
  }
}

extension ThreadDraft {
  /// Drops empty posts, classifying what was dropped.
  ///
  /// Ported from `getFilteredThread`.
  public func filteringEmptyPosts() -> FilteredThread {
    let nonEmpty = posts.filter { !$0.isEmpty }
    if nonEmpty.count == posts.count {
      return FilteredThread(classification: .none, thread: self)
    }
    let lastNonEmptyIndex = posts.lastIndex(where: { !$0.isEmpty }) ?? -1
    let hasNonTrailingEmpty = posts.enumerated().contains { index, post in
      index < lastNonEmptyIndex && post.isEmpty
    }
    var filtered = self
    filtered.posts = nonEmpty
    return FilteredThread(
      classification: hasNonTrailingEmpty ? .nonTrailing : .trailingOnly,
      thread: filtered)
  }
}
