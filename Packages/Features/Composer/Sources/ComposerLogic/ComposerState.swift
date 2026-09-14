import Foundation
import Lexicons
import RichText
import SwiftAtproto

/// A quote target: an app URL that resolves to a record at publish time.
///
/// Ported from the `Link` member of `EmbedDraft`.
public struct QuoteLink: Hashable, Sendable {
  public var uri: String

  public init(uri: String) {
    self.uri = uri
  }
}

/// A link-card target. Distinct from ``QuoteLink`` because the composer keeps
/// them in separate slots: a post URL can only ever become a quote, and a
/// non-post URL can only ever become a link card.
public struct ExternalLink: Hashable, Sendable {
  public var uri: String

  public init(uri: String) {
    self.uri = uri
  }
}

/// What a post's embed will be built from.
///
/// Ported from `EmbedDraft`. The three slots are independent: `quote` and
/// `media` are always honoured, while `link` is ignored when there is more
/// important content to show (the resolution order lives in
/// ``ComposerRecordBuilder``).
public struct EmbedDraft: Hashable, Sendable {
  /// The post being quoted, if any.
  public var quote: QuoteLink?
  /// The attached media, if any.
  public var media: ComposerMedia?
  /// The link card candidate, if any.
  public var link: ExternalLink?

  public init(
    quote: QuoteLink? = nil,
    media: ComposerMedia? = nil,
    link: ExternalLink? = nil
  ) {
    self.quote = quote
    self.media = media
    self.link = link
  }
}

/// One post in the composer thread.
///
/// Ported from `PostDraft`. `shortenedGraphemeLength` is cached here because the
/// character counter and the publish-time limit check both need it and both
/// must see the *post-shortening* count (see ``ComposerText``).
public struct PostDraft: Hashable, Sendable, Identifiable {
  /// A stable identity for this post within the composer session.
  public var id: String
  /// The post's rich text, including detected facets.
  ///
  /// Stored as a value snapshot rather than ``RichText`` (a non-`Sendable`
  /// class) so composer state can cross actor boundaries and be compared.
  public var richText: RichTextValue
  /// Self-labels attached to this post.
  public var labels: SelfLabelSet
  /// The embed draft.
  public var embed: EmbedDraft
  /// The grapheme length once links are shortened, i.e. what the limit applies to.
  public var shortenedGraphemeLength: Int

  public init(
    id: String,
    richText: RichTextValue,
    labels: SelfLabelSet = SelfLabelSet(),
    embed: EmbedDraft = EmbedDraft(),
    shortenedGraphemeLength: Int? = nil
  ) {
    self.id = id
    self.richText = richText
    self.labels = labels
    self.embed = embed
    self.shortenedGraphemeLength =
      shortenedGraphemeLength ?? ComposerText.shortenedGraphemeLength(richText)
  }

  /// An empty post, as `add_post` inserts it.
  public static func empty(id: String) -> PostDraft {
    PostDraft(id: id, richText: .empty)
  }

  /// Whether this post has no content at all.
  ///
  /// Ported from `isEmptyPost`: the text (trimmed) must be empty **and** there
  /// must be no media, link or quote.
  public var isEmpty: Bool {
    richText.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && embed.media == nil
      && embed.link == nil
      && embed.quote == nil
  }

  /// Whether the post is over the publish limit.
  public var isOverLimit: Bool {
    shortenedGraphemeLength > ComposerConstants.maxGraphemeLength
  }
}

/// The composer's thread-level state.
///
/// Ported from `ThreadDraft`.
public struct ThreadDraft: Hashable, Sendable {
  /// The posts, in order.
  public var posts: [PostDraft]
  /// The postgate the published thread will carry.
  public var postgate: App.Bsky.FeedPostgate
  /// The reply permissions, as UI settings.
  public var threadgate: [ThreadgateAllowUISetting]

  public init(
    posts: [PostDraft],
    postgate: App.Bsky.FeedPostgate,
    threadgate: [ThreadgateAllowUISetting]
  ) {
    self.posts = posts
    self.postgate = postgate
    self.threadgate = threadgate
  }
}

/// The whole composer state.
///
/// Ported from `ComposerState`. The RN `loadedMediaMap`/`originalLocalRefs`
/// fields are draft-editing bookkeeping and live on ``ComposerSession``'s draft
/// attachment instead, because they are only meaningful for a draft being edited.
public struct ComposerState: Hashable, Sendable {
  /// The thread.
  public var thread: ThreadDraft
  /// The index of the post the text field is bound to.
  public var activePostIndex: Int
  /// Whether the active post should take focus after the next render.
  public var mutableNeedsFocusActive: Bool
  /// The id of the draft being edited, when the composer was opened from one.
  public var draftId: String?
  /// Whether the composer has been modified since a draft was loaded.
  public var isDirty: Bool

  public init(
    thread: ThreadDraft,
    activePostIndex: Int = 0,
    mutableNeedsFocusActive: Bool = false,
    draftId: String? = nil,
    isDirty: Bool = false
  ) {
    self.thread = thread
    self.activePostIndex = activePostIndex
    self.mutableNeedsFocusActive = mutableNeedsFocusActive
    self.draftId = draftId
    self.isDirty = isDirty
  }

  /// Every post that has content, in order.
  ///
  /// Ported from `getFilteredThread`'s `nonEmptyPosts`.
  public var nonEmptyPosts: [PostDraft] {
    thread.posts.filter { !$0.isEmpty }
  }

  /// The post the text field is bound to. Always valid while `posts` is
  /// non-empty, which every mutation preserves.
  public var activePost: PostDraft {
    thread.posts[min(activePostIndex, thread.posts.count - 1)]
  }
}
