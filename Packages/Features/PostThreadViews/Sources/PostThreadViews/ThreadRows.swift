import DesignSystem
import DesignTokens
import Foundation
import PostThreadLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// One row of the thread list: the gutter, then the content for the row's kind.
///
/// A row is a pure render of a ``ThreadItem``, so the interesting decisions -
/// indent, connector state, which kind of row it is - were all made by the
/// logic package's flattening pass.
struct ThreadRow: View {
  let item: ThreadItem
  let strings: PostThreadStrings
  let now: Date
  let locale: Locale
  let onShowMoreReplies: (ThreadItem) -> Void
  let onOpen: (RichTextTarget) -> Void
  let onReply: (ThreadPostContent) -> Void
  let onLike: (ThreadPostContent) -> Void
  let onRepost: (ThreadPostContent) -> Void
  let onOpenEngagement: (String, ThreadEngagementKind) -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ThreadReplyLines(connector: item.connector)
      content
    }
  }

  @ViewBuilder
  private var content: some View {
    switch item.content {
    case .post(let post):
      ThreadPostRow(
        item: item,
        content: post,
        now: now,
        locale: locale,
        strings: strings,
        onOpen: onOpen,
        onReply: onReply,
        onLike: onLike,
        onRepost: onRepost,
        onOpenEngagement: onOpenEngagement)
    case .tombstone(let tombstone):
      ThreadTombstoneRow(tombstone: tombstone, strings: strings)
    case .readMore(let readMore):
      ThreadReadMoreRow(
        readMore: readMore, strings: strings, onTap: { onShowMoreReplies(item) })
    case .showMore:
      ThreadShowMoreRow(strings: strings, onTap: { onShowMoreReplies(item) })
    }
  }
}

/// A hydrated post row.
struct ThreadPostRow: View {
  let item: ThreadItem
  let content: ThreadPostContent
  let now: Date
  let locale: Locale
  let strings: PostThreadStrings
  let onOpen: (RichTextTarget) -> Void
  let onReply: (ThreadPostContent) -> Void
  let onLike: (ThreadPostContent) -> Void
  let onRepost: (ThreadPostContent) -> Void
  let onOpenEngagement: (String, ThreadEngagementKind) -> Void

  @Environment(\.alfTheme) private var theme

  init(
    item: ThreadItem,
    content: ThreadPostContent,
    now: Date,
    locale: Locale,
    strings: PostThreadStrings,
    onOpen: @escaping (RichTextTarget) -> Void,
    onReply: @escaping (ThreadPostContent) -> Void,
    onLike: @escaping (ThreadPostContent) -> Void,
    onRepost: @escaping (ThreadPostContent) -> Void,
    onOpenEngagement: @escaping (String, ThreadEngagementKind) -> Void
  ) {
    self.item = item
    self.content = content
    self.now = now
    self.locale = locale
    self.strings = strings
    self.onOpen = onOpen
    self.onReply = onReply
    self.onLike = onLike
    self.onRepost = onRepost
    self.onOpenEngagement = onOpenEngagement
  }

  var body: some View {
    let data = ThreadRowAdapter.viewData(
      for: content,
      now: now,
      locale: locale,
      contextLine: contextLine)
    Group {
      if item.isAnchor {
        ThreadAnchorPost(
          data: data,
          postURI: content.post.uri.rawValue,
          createdAt: content.record?.createdAt.rawValue,
          quoteCount: content.post.quoteCount,
          strings: strings,
          onOpen: onOpen,
          onOpenEngagement: onOpenEngagement,
          onOpenAuthor: { onOpen(.profile(did: $0)) },
          onReply: content.replyDisabled ? nil : { onReply(content) },
          onRepost: { onRepost(content) },
          onLike: { onLike(content) })
      } else {
        PostFeedItem(
          data: data,
          onOpen: onOpen,
          onOpenAuthor: { onOpen(.profile(did: $0)) },
          onReply: content.replyDisabled ? nil : { onReply(content) },
          onRepost: { onRepost(content) },
          onLike: { onLike(content) })
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }

  /// The context line above a row: an OP-liked reply is the case the data layer
  /// flags explicitly, since RN labels it in the thread.
  private var contextLine: String? {
    content.hasOPLike ? strings.likedByAuthor : nil
  }
}

/// The focused post uses a deliberately different visual hierarchy from feed
/// rows. Its author identity leads, while the body, media, timestamp, metrics,
/// and controls each receive the full content width.
struct ThreadAnchorPost: View {
  let data: FeedItemViewData
  let postURI: String
  let createdAt: String?
  let quoteCount: Int?
  let strings: PostThreadStrings
  let onOpen: (RichTextTarget) -> Void
  let onOpenEngagement: (String, ThreadEngagementKind) -> Void
  let onOpenAuthor: (String) -> Void
  let onReply: (() -> Void)?
  let onRepost: (() -> Void)?
  let onLike: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    ModerationMask(surface: data.moderation.content) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        authorHeader

        if !data.text.isEmpty {
          RichTextBody(segments: data.segments, scale: .lg, onOpen: onOpen)
        }

        if let embed = data.embed {
          PostEmbed(
            embed: data.postEmbed,
            info: embed,
            moderation: data.moderation.media,
            onOpen: onOpen)
        }

        if let absoluteDate {
          Text(absoluteDate)
            .font(TypeScale.sm.font())
            .foregroundStyle(theme.atomColors.textContrastMedium)
        }

        Divider()
        engagementSummary
        Divider()

        EngagementRow(
          replyCount: nil,
          repostCount: nil,
          likeCount: nil,
          isReposted: data.isReposted,
          isLiked: data.isLiked,
          onReply: onReply,
          onRepost: onRepost,
          onLike: onLike)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
  }

  private var authorHeader: some View {
    Button {
      onOpenAuthor(data.authorDid)
    } label: {
      HStack(spacing: Spacing.sm) {
        ModerationMask(surface: data.moderation.avatar) {
          Avatar(source: data.avatar, size: .lg, label: data.displayName)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(data.displayName)
            .font(TypeScale.md.font(weight: Scales.FontWeight.semiBold))
            .foregroundStyle(theme.atomColors.text)
            .lineLimit(1)
          Text(data.handle)
            .font(TypeScale.sm.font())
            .foregroundStyle(theme.atomColors.textContrastMedium)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(data.authorDid.isEmpty)
  }

  private var engagementSummary: some View {
    HStack(spacing: Spacing.lg) {
      if let repostCount = nonZero(data.repostCount) {
        stat(
          repostCount, singular: strings.repost, plural: strings.reposts, kind: .reposts)
      }
      if let quoteCount, quoteCount > 0 {
        stat(
          String(quoteCount), singular: strings.quote, plural: strings.quotes, kind: .quotes)
      }
      if let likeCount = nonZero(data.likeCount) {
        stat(likeCount, singular: strings.like, plural: strings.likes, kind: .likes)
      }
      if let replyCount = nonZero(data.replyCount) {
        stat(replyCount, singular: strings.reply, plural: strings.replies)
      }
      Spacer(minLength: 0)
    }
  }

  private func nonZero(_ count: String?) -> String? {
    guard let count, count != "0" else { return nil }
    return count
  }

  @ViewBuilder
  private func stat(
    _ value: String,
    singular: String,
    plural: String,
    kind: ThreadEngagementKind? = nil
  ) -> some View {
    if let kind {
      Button { onOpenEngagement(postURI, kind) } label: {
        statLabel(value, singular: singular, plural: plural)
      }
      .buttonStyle(.plain)
    } else {
      statLabel(value, singular: singular, plural: plural)
    }
  }

  private func statLabel(_ value: String, singular: String, plural: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(value)
        .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
        .foregroundStyle(theme.atomColors.text)
      Text(value == "1" ? singular : plural)
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
    }
  }

  private var absoluteDate: String? {
    guard let createdAt,
      let date = ISO8601DateFormatter().date(from: createdAt)
    else { return nil }
    return date.formatted(date: .long, time: .shortened)
  }
}

/// The row shown where a branch could not be hydrated: a post that was deleted,
/// a post behind a block, or one the viewer's moderation settings hide.
struct ThreadTombstoneRow: View {
  let tombstone: ThreadTombstone
  let strings: PostThreadStrings

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: icon)
        .font(TypeScale.md.font(weight: Scales.FontWeight.medium))
        .foregroundStyle(theme.atomColors.textContrastMedium)
      Text(strings.tombstone(tombstone.kind))
        .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
        .foregroundStyle(theme.atomColors.textContrastMedium)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.atomColors.bgContrast25)
    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .accessibilityElement(children: .combine)
  }

  private var icon: String {
    switch tombstone.kind {
    case .deleted: "trash"
    case .blocked: "person.crop.circle.badge.xmark"
    case .hiddenByModeration: "eye.slash"
    }
  }
}

/// A "read more" row: the affordance that widens the window either upwards (an
/// ancestor chain that was truncated) or downwards (replies the server did not
/// hydrate).
struct ThreadReadMoreRow: View {
  let readMore: ReadMoreContent
  let strings: PostThreadStrings
  let onTap: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: Spacing.sm) {
        Image(systemName: readMore.direction == .up ? "arrow.up" : "arrow.down")
          .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
        Text(label)
          .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
        Spacer(minLength: 0)
      }
      .foregroundStyle(theme.atomColors.textLink)
      .padding(Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }

  private var label: String {
    if let more = readMore.moreReplies, more > 0 {
      return String(format: strings.showMoreRepliesFormat, more)
    }
    return readMore.direction == .up ? strings.showMoreParents : strings.loadMoreReplies
  }
}

/// The terminal row of a windowed list: RN's `LOAD_MORE` sentinel, which
/// reveals another cap of replies.
struct ThreadShowMoreRow: View {
  let strings: PostThreadStrings
  let onTap: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "arrow.down.circle")
          .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
        Text(strings.loadMoreReplies)
          .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
        Spacer(minLength: 0)
      }
      .foregroundStyle(theme.atomColors.textLink)
      .padding(Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(strings.loadMoreReplies)
  }
}

/// The composer affordance at the bottom of the thread: a placeholder button
/// for the reply composer, which is a separate feature.
struct ThreadComposerRow: View {
  let strings: PostThreadStrings
  let onTap: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "square.and.pencil")
          .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
        Text(strings.replyPlaceholder)
          .font(TypeScale.sm.font())
        Spacer(minLength: 0)
      }
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.atomColors.bgContrast50)
      .clipShape(RoundedRectangle(cornerRadius: Radius.full))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(Spacing.md)
    .accessibilityLabel(strings.replyPlaceholder)
  }
}
