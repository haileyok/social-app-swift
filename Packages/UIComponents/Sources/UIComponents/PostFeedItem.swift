#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import Moderation
import RichText
import SwiftUI
import UIComponentsCore

/// A post in a feed.
///
/// The layout follows the RN `Post` component: an optional repost/context line,
/// then avatar + name + handle + relative time, the RichText body, the embed,
/// and the engagement row. Everything it draws comes from
/// ``FeedItemViewData``, which the core derives from a ``PostView`` - so the
/// view is a pure render and the interesting logic is testable on Linux.
///
/// ```swift
/// PostFeedItem(data: feedItemViewData(post, counts: counts))
/// ```
public struct PostFeedItem: View {
  private let data: FeedItemViewData
  private let onOpen: (RichTextTarget) -> Void
  private let onOpenAuthor: ((String) -> Void)?
  private let onReply: (() -> Void)?
  private let onRepost: (() -> Void)?
  private let onLike: (() -> Void)?

  public init(
    data: FeedItemViewData,
    onOpen: @escaping (RichTextTarget) -> Void = { _ in },
    onOpenAuthor: ((String) -> Void)? = nil,
    onReply: (() -> Void)? = nil,
    onRepost: (() -> Void)? = nil,
    onLike: (() -> Void)? = nil
  ) {
    self.data = data
    self.onOpen = onOpen
    self.onOpenAuthor = onOpenAuthor
    self.onReply = onReply
    self.onRepost = onRepost
    self.onLike = onLike
  }

  public var body: some View {
    ModerationMask(surface: data.moderation.content) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        if let contextLine = data.contextLine {
          ContextLine(text: contextLine)
        }
        HStack(alignment: .top, spacing: Spacing.sm) {
          Button {
            onOpenAuthor?(data.authorDid)
          } label: {
            ModerationMask(surface: data.moderation.avatar) {
              Avatar(source: data.avatar, size: .md, label: data.displayName)
            }
          }
          .buttonStyle(.plain)
          .disabled(onOpenAuthor == nil || data.authorDid.isEmpty)
          VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
              onOpenAuthor?(data.authorDid)
            } label: {
              AuthorLine(
                displayName: data.displayName,
                handle: data.handle,
                relativeTime: data.relativeTime)
            }
            .buttonStyle(.plain)
            .disabled(onOpenAuthor == nil || data.authorDid.isEmpty)
            if !data.text.isEmpty {
              RichTextBody(segments: data.segments, onOpen: onOpen)
            }
            if let embed = data.embed {
              embedBody(embed)
            }
            EngagementRow(
              replyCount: data.replyCount,
              repostCount: data.repostCount,
              likeCount: data.likeCount,
              onReply: onReply,
              onRepost: onRepost,
              onLike: onLike)
          }
        }
      }
      .padding(.md)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func embedBody(_ embed: EmbedVariantInfo) -> some View {
    PostEmbed(
      embed: data.postEmbed,
      info: embed,
      moderation: data.moderation.media,
      onOpen: onOpen)
  }
}

/// The repost/context header above a post.
public struct ContextLine: View {
  private let text: String

  @Environment(\.alfTheme) private var theme

  public init(text: String) {
    self.text = text
  }

  public var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "arrow.2.square.path")
        .font(.system(size: 13, weight: .semibold))
      Text(text)
        .font(TypeScale.xs.font(weight: "600"))
        .lineLimit(1)
    }
    .foregroundStyle(theme.atomColors.textContrastMedium)
    .padding(.leading, AvatarSize.md.side + Spacing.sm)
  }
}

/// The display name + handle + relative time line.
public struct AuthorLine: View {
  private let displayName: String
  private let handle: String
  private let relativeTime: String

  @Environment(\.alfTheme) private var theme

  public init(displayName: String, handle: String, relativeTime: String) {
    self.displayName = displayName
    self.handle = handle
    self.relativeTime = relativeTime
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
      Text(displayName)
        .font(TypeScale.sm.font(weight: "600"))
        .foregroundStyle(theme.atomColors.text)
        .lineLimit(1)
        .truncationMode(.tail)
      Text(handle)
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .lineLimit(1)
        .truncationMode(.middle)
      if !relativeTime.isEmpty {
        Text(relativeTime)
          .font(TypeScale.sm.font())
          .foregroundStyle(theme.atomColors.textContrastMedium)
        Spacer(minLength: 0)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(displayName), \(handle), \(relativeTime)")
  }
}

/// The reply / repost / like row.
///
/// Counts come in pre-formatted from the core (``formatOptionalCount``), and a
/// nil count renders no label - matching the RN `PostControl`, which omits a
/// zero metric rather than showing `0`.
public struct EngagementRow: View {
  private let replyCount: String?
  private let repostCount: String?
  private let likeCount: String?
  private let onReply: (() -> Void)?
  private let onRepost: (() -> Void)?
  private let onLike: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  public init(
    replyCount: String?,
    repostCount: String?,
    likeCount: String?,
    onReply: (() -> Void)? = nil,
    onRepost: (() -> Void)? = nil,
    onLike: (() -> Void)? = nil
  ) {
    self.replyCount = replyCount
    self.repostCount = repostCount
    self.likeCount = likeCount
    self.onReply = onReply
    self.onRepost = onRepost
    self.onLike = onLike
  }

  public var body: some View {
    HStack(spacing: Spacing.lg) {
      EngagementButton(
        systemImage: "bubble.left", count: replyCount, label: "Reply", action: onReply)
      EngagementButton(
        systemImage: "arrow.2.squarepath", count: repostCount, label: "Repost", action: onRepost)
      EngagementButton(
        systemImage: "heart", count: likeCount, label: "Like", action: onLike)
      Spacer(minLength: 0)
    }
    .padding(.top, Spacing.xs)
  }
}

/// One metric button in the engagement row.
public struct EngagementButton: View {
  private let systemImage: String
  private let count: String?
  private let label: String
  private let action: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  public init(systemImage: String, count: String?, label: String, action: (() -> Void)?) {
    self.systemImage = systemImage
    self.count = count
    self.label = label
    self.action = action
  }

  public var body: some View {
    Button {
      action?()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: systemImage)
          .font(.system(size: 17, weight: .medium))
        if let count {
          Text(count)
            .font(TypeScale.xs.font())
        }
      }
      .foregroundStyle(theme.atomColors.textContrastMedium)
    }
    .buttonStyle(.plain)
    .disabled(action == nil)
    .accessibilityLabel(count.map { "\(label), \($0)" } ?? label)
  }
}

/// A post with the feed row's loading treatment, for list placeholders.
public struct PostSkeletonRow: View {
  @Environment(\.alfTheme) private var theme

  public init() {}

  public var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Circle()
        .fill(theme.atomColors.bgContrast100)
        .frame(width: AvatarSize.md.side, height: AvatarSize.md.side)
      VStack(alignment: .leading, spacing: Spacing.sm) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(theme.atomColors.bgContrast100)
          .frame(width: 140, height: 10)
        ForEach([1.0, 0.85, 0.6], id: \.self) { fraction in
          GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(theme.atomColors.bgContrast50)
              .frame(width: proxy.size.width * fraction, height: 10)
          }
          .frame(height: 10)
        }
      }
    }
    .padding(.md)
    .accessibilityHidden(true)
    .redacted(reason: .placeholder)
  }
}
#endif
