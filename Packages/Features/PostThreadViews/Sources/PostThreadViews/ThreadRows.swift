import DesignSystem
import DesignTokens
import PostThreadLogic
import SwiftUI
import UIComponents

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
        onOpen: onOpen)
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

  @Environment(\.alfTheme) private var theme

  init(
    item: ThreadItem,
    content: ThreadPostContent,
    now: Date,
    locale: Locale,
    strings: PostThreadStrings,
    onOpen: @escaping (RichTextTarget) -> Void
  ) {
    self.item = item
    self.content = content
    self.now = now
    self.locale = locale
    self.strings = strings
    self.onOpen = onOpen
  }

  var body: some View {
    let data = ThreadRowAdapter.viewData(
      for: content,
      now: now,
      locale: locale,
      contextLine: contextLine)
    PostFeedItem(data: data, onOpen: onOpen)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(item.isAnchor ? theme.atomColors.bgContrast25 : .clear)
      .overlay(alignment: .leading) {
        if item.isAnchor {
          Rectangle()
            .fill(theme.atomColors.textLink)
            .frame(width: 3)
        }
      }
      .accessibilityElement(children: .contain)
  }

  /// The context line above a row: an OP-liked reply is the case the data layer
  /// flags explicitly, since RN labels it in the thread.
  private var contextLine: String? {
    content.hasOPLike ? strings.likedByAuthor : nil
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
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(strings.tombstone(tombstone.kind))
          .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
          .foregroundStyle(theme.atomColors.textContrastMedium)
        Text(tombstone.uri)
          .font(TypeScale.xs.font())
          .foregroundStyle(theme.atomColors.textContrastLow)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
    }
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.atomColors.bgContrast25)
    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .accessibilityElement(children: .combine)
  }

  private var icon: String {
    switch tombstone.kind {
    case .deleted: "questionmark.circle"
    case .blocked: "hand.raised"
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
