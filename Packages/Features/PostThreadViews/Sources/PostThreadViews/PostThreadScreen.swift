import DesignSystem
import DesignTokens
import PostThreadLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The thread screen: one scrolling list of rows.
///
/// This is the native-first port of RN's `PostThread.tsx`. The shape is the
/// same single `FlatList`: ancestors, then the highlighted anchor, then the
/// replies, with everything the list needs - indent, connector lines, tombstone
/// kinds, the window - already resolved by ``PostThreadLogic``. The screen owns
/// only the window state that RN keeps in component state, so a scroll or a
/// "load more" tap can widen the list without refetching.
///
/// ```swift
/// PostThreadScreen(thread: ThreadFlattener.flatten(tree))
/// ```
public struct PostThreadScreen: View {
  private let window: ThreadWindow
  private let strings: PostThreadStrings
  private let now: Date
  private let locale: Locale
  private let onOpen: (RichTextTarget) -> Void
  private let onReply: () -> Void

  /// The window the caller handed us, and the one the UI widens. Local state so
  /// a "load more" tap is immediate; the parent's value is the starting point.
  @State private var current: ThreadWindow
  @Environment(\.alfTheme) private var theme

  public init(
    thread: FlattenedThread,
    showMore: ThreadShowMore = .initial(),
    strings: PostThreadStrings = .defaults,
    now: Date = Date(),
    locale: Locale = Locale(identifier: "en_US"),
    onOpen: @escaping (RichTextTarget) -> Void = { _ in },
    onReply: @escaping () -> Void = {}
  ) {
    self.window = ThreadWindow(thread: thread, showMore: showMore)
    self.strings = strings
    self.now = now
    self.locale = locale
    self.onOpen = onOpen
    self.onReply = onReply
    _current = State(initialValue: ThreadWindow(thread: thread, showMore: showMore))
  }

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(current.items.enumerated()), id: \.element.id) { index, item in
          if index > 0, item.connector?.showParentReplyLine != true {
            Divider()
              .foregroundStyle(theme.atomColors.borderContrastLow)
          }

          ThreadRow(
            item: item,
            strings: strings,
            now: now,
            locale: locale,
            onShowMoreReplies: handleShowMore,
            onOpen: onOpen)

          if item.isAnchor, canReply(to: item) {
            ThreadComposerRow(strings: strings, onTap: onReply)
          }
        }

        if current.thread.hasOtherReplies {
          ThreadOtherRepliesRow(strings: strings, count: current.thread.otherItems.count)
        }
      }
    }
    .background(theme.atomColors.bg)
    .navigationTitle(strings.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  /// The reply prompt belongs directly below a hydrated, replyable anchor.
  private func canReply(to item: ThreadItem) -> Bool {
    guard case .post(let content) = item.content else { return false }
    return !content.replyDisabled
  }

  /// A "load more" tap: widen the window in the direction the row asked for.
  ///
  /// The logic package models both directions with one type, so the row's own
  /// content decides which window grows - the view does not re-derive it.
  private func handleShowMore(_ item: ThreadItem) {
    switch item.content {
    case .readMore(let readMore) where readMore.direction == .up:
      current.revealMoreParents()
    default:
      current.revealMoreReplies()
    }
  }
}

/// The row that stands in for replies moderation moved out of the inline list.
///
/// RN buckets these behind a "show other replies" affordance rather than
/// dropping them; the data layer carries the bucket, so the row is a count.
struct ThreadOtherRepliesRow: View {
  let strings: PostThreadStrings
  let count: Int

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "eye.slash")
        .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
      Text("\(strings.otherReplies) (\(count))")
        .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
      Spacer(minLength: 0)
    }
    .foregroundStyle(theme.atomColors.textContrastMedium)
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
