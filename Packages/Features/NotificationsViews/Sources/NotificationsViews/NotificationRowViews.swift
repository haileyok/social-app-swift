import DesignSystem
import Lexicons
import DesignTokens
import Moderation
import SwiftUI
import UIComponents
import UIComponentsCore

import NotificationsLogic

/**
 One sentence row in the notifications list: a leading reason glyph or avatar, an
 author line, the reason sentence, and the timestamp.

 Ported from the RN `NotificationFeedItem`: the icon column is fixed-width, the
 author name leads the sentence in bold, the timestamp trails it behind a
 middot, and an unread row carries the primary-tinted background plus a leading
 unread bar. Replies, mentions and quotes do not use this view at all - they draw
 the subject post through ``NotificationPostRow``.
 */
public struct NotificationSentenceRow: View {
  private let row: FeedNotification
  private let highlightUnread: Bool
  private let now: Date
  private let onOpenAuthor: (String) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    row: FeedNotification,
    highlightUnread: Bool = true,
    now: Date = Date(),
    onOpenAuthor: @escaping (String) -> Void = { _ in }
  ) {
    self.row = row
    self.highlightUnread = highlightUnread
    self.now = now
    self.onOpenAuthor = onOpenAuthor
  }

  public var body: some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      glyphColumn
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        sentenceLine
        if let subject = row.subjectPost {
          subjectPreview(subject)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.md)
    .background(row.isUnread && highlightUnread ? theme.colors.primary25 : theme.atomColors.bg)
    .overlay(alignment: .leading) {
      if row.isUnread && highlightUnread {
        Rectangle()
          .fill(theme.colors.primary500)
          .frame(width: Spacing.xxs)
          .accessibilityIdentifier(NotificationsAccessibility.unreadIndicator)
      }
    }
    .contentShape(.rect)
    .onTapGesture { onOpenAuthor(notificationAuthorHandle) }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(NotificationsAccessibility.row(notificationAuthorHandle))
    .accessibilityLabel(row.accessibilitySentence(relativeTime: relativeTime))
  }

  /// The fixed-width leading column: the reason icon, or the author avatar for
  /// the reasons the RN item draws an avatar for.
  @ViewBuilder
  private var glyphColumn: some View {
    if let glyph = NotificationReasonGlyph.glyph(for: row.type) {
      Image(systemName: glyph.systemImage)
        .font(.system(size: 22))
        .foregroundStyle(glyph.tint.color(in: theme))
        .frame(width: 34, height: 34)
        .accessibilityIdentifier(NotificationsAccessibility.rowIcon)
    } else {
      Avatar(
        avatar: row.notification.author.avatar?.rawValue,
        handle: row.notification.author.handle.rawValue,
        displayName: row.notification.author.displayName,
        size: .md)
        .accessibilityIdentifier(NotificationsAccessibility.rowAvatar)
    }
  }

  /// `Alice liked your post · 2h`, with the name and the "and N others" clause
  /// bold, matching the RN `Text` nesting.
  private var sentenceLine: Text {
    let authors = NotificationRowAuthors(row: row)
    let name = NotificationsCopy.displayName(authors.first)
    let head = Text(name).font(TypeScale.md.font(weight: Scales.FontWeight.semiBold))
    let clause = Text(" " + trailingClause(authors: authors)).font(TypeScale.md.font())
    let meta = Text("  ·  " + relativeTime)
      .font(TypeScale.md.font())
      .foregroundColor(theme.atomColors.textContrastMedium)
    return head + clause + meta
  }

  /// Everything after the first author's name: the grouped clause plus the verb.
  private func trailingClause(authors: NotificationRowAuthors) -> String {
    if authors.isGrouped {
      let others = NotificationStrings.othersCount(authors.additionalCount)
      switch row.type {
      case .feedgenLike: return "\(others) liked your custom feed"
      case .subscribedPost: return "\(others) posted"
      default: return "\(others) \(NotificationsCopy.verb(for: row.type) ?? "")"
      }
    }
    if let count = row.subjectPost.map({ _ in 1 + row.additional.count }), row.type == .subscribedPost {
      return count == 1 ? "posted a new post" : "posted \(count) new posts"
    }
    return NotificationsCopy.verb(for: row.type) ?? ""
  }

  /// The inline preview of the notification's subject post: the RN item renders
  /// the subject text under the sentence for likes, reposts and subscriptions.
  @ViewBuilder
  private func subjectPreview(_ post: Lexicons.App.Bsky.FeedDefs_PostView) -> some View {
    NotificationSubjectPreview(post: post, now: now)
  }

  /// The relative timestamp, through the shared formatter so it matches the
  /// feed rows.
  private var relativeTime: String {
    relativeTimeString(row.notification.indexedAt.rawValue, now: now)
  }

  private var notificationAuthorHandle: String {
    row.notification.author.handle.rawValue
  }
}

/**
 The one-line preview of a notification's subject post.

 Kept tiny on purpose: the row's sentence already carries the meaning, so this
 is the RN `AdditionalPostText` - the post body, truncated, without the author
 or engagement rows a full ``UIComponents/PostFeedItem`` would draw.
 */
public struct NotificationSubjectPreview: View {
  private let post: Lexicons.App.Bsky.FeedDefs_PostView
  private let now: Date

  @Environment(\.alfTheme) private var theme

  public init(post: Lexicons.App.Bsky.FeedDefs_PostView, now: Date = Date()) {
    self.post = post
    self.now = now
  }

  public var body: some View {
    Text(previewText)
      .font(TypeScale.md.font())
      .lineLimit(3)
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .accessibilityIdentifier(NotificationsAccessibility.rowSubject)
  }

  /// The post's text, falling back to the shared "unavailable" string when the
  /// record carries none - the same fallback the logic package exposes for a
  /// subject that did not resolve.
  private var previewText: String {
    guard let record = NotificationReasons.postRecord(post.record) else {
      return NotificationStrings.missingSubject
    }
    let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? NotificationStrings.missingSubject : text
  }
}

/**
 A reply/mention/quote row: the subject post rendered through the shared
 ``UIComponents/PostFeedItem``, tinted when unread.

 The RN item renders the same shared `Post` component here rather than a bespoke
 view, so the port does too: a notification that points at a post looks like that
 post, and the feed layout stays in one place.
 */
public struct NotificationPostRow: View {
  private let row: FeedNotification
  private let highlightUnread: Bool
  private let now: Date
  private let onOpen: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    row: FeedNotification,
    highlightUnread: Bool = true,
    now: Date = Date(),
    onOpen: @escaping (RichTextTarget) -> Void = { _ in }
  ) {
    self.row = row
    self.highlightUnread = highlightUnread
    self.now = now
    self.onOpen = onOpen
  }

  public var body: some View {
    Group {
      if let post = row.subjectPost {
        PostFeedItem(
          data: feedItemViewData(
            NotificationReasons.postView(post),
            options: FeedItemRenderOptions(now: now)),
          onOpen: onOpen)
      } else {
        missingSubject
      }
    }
    .background(row.isUnread && highlightUnread ? theme.colors.primary25 : theme.atomColors.bg)
    .overlay(alignment: .leading) {
      if row.isUnread && highlightUnread {
        Rectangle()
          .fill(theme.colors.primary500)
          .frame(width: Spacing.xxs)
          .accessibilityIdentifier(NotificationsAccessibility.unreadIndicator)
      }
    }
    .accessibilityIdentifier(NotificationsAccessibility.row(row.notification.author.handle.rawValue))
  }

  /// The RN item returns null for a reply whose subject is gone; a list row that
  /// renders nothing is invisible to VoiceOver, so this shows the shared
  /// unavailable string instead.
  private var missingSubject: some View {
    Text(NotificationStrings.missingSubject)
      .font(TypeScale.md.font())
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.md)
  }
}

/// The engagement-count helper the post row needs, re-exported so callers of
/// this package do not have to import `UIComponentsCore` for one function.
public func notificationPostData(
  _ post: Lexicons.App.Bsky.FeedDefs_PostView,
  now: Date = Date()
) -> FeedItemViewData {
  feedItemViewData(
    NotificationReasons.postView(post),
    options: FeedItemRenderOptions(now: now))
}
