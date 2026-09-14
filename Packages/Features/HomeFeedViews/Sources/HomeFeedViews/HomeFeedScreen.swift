import DesignSystem
import DesignSystemCore
import HomeFeedLogic
import RichText
import SwiftUI
import UIComponents
import UIComponentsCore

/// The Home feed screen: the feed switcher, the post list, and its states.
///
/// The structure follows the RN `HomeScreen` + `PostFeed` pair. RN pages between
/// pinned feeds with a carousel and collapses its header as you scroll; this is
/// the native-first reading of the same screen:
///
/// - the switcher is a pinned tab strip (`safeAreaInset(edge: .top)`) rather
///   than a paging carousel, so one feed's scroll state is one `List`;
/// - the list is a `List` with `.plain` style, which is what gives free cell
///   recycling and the system's scroll-edge behaviour;
/// - pull-to-refresh is `.refreshable`;
/// - infinite scroll is the last row's `onAppear`, the stand-in for RN's
///   `onEndReached`;
/// - the new-posts pill floats over the top of the list.
///
/// Everything it draws comes from ``HomeFeedViewModel``, which in turn renders
/// ``HomeFeedLogic/HomeFeedSlice`` values through `UIComponents.PostFeedItem`.
public struct HomeFeedScreen: View {
  @State private var model: HomeFeedViewModel
  private let onOpenRichText: (RichTextTarget) -> Void
  private let onSignIn: (() -> Void)?
  private let onAddFeeds: (() -> Void)?

  @Environment(\.alfTheme) private var theme
  @Environment(\.scenePhase) private var scenePhase

  /// Creates the screen.
  ///
  /// - Parameters:
  ///   - model: the view model, already built over a `HomeFeedModel`.
  ///   - onOpenRichText: link/tag/mention taps inside a post body.
  ///   - onSignIn: the logged-out call to action.
  ///   - onAddFeeds: the no-feeds-pinned call to action.
  public init(
    model: HomeFeedViewModel,
    onOpenRichText: @escaping (RichTextTarget) -> Void = { _ in },
    onSignIn: (() -> Void)? = nil,
    onAddFeeds: (() -> Void)? = nil
  ) {
    _model = State(initialValue: model)
    self.onOpenRichText = onOpenRichText
    self.onSignIn = onSignIn
    self.onAddFeeds = onAddFeeds
  }

  public var body: some View {
    Group {
      switch model.presentation {
      case .loggedOut:
        centered {
          HomeFeedEmptyState(reason: .loggedOut, action: onSignIn)
        }
      case .noFeedsPinned:
        centered {
          HomeFeedEmptyState(reason: .noFeedsPinned, action: onAddFeeds)
        }
      case .loading:
        ListSkeleton()
      case .feeds:
        feedsSurface
      }
    }
    .background(theme.atomColors.bg)
    .task { await model.onAppear() }
    .onDisappear { Task { await model.onDisappear() } }
    .onChange(of: scenePhase) { _, phase in
      // RN checks for new posts whenever the app returns to the foreground.
      guard phase == .active else { return }
      Task { await model.pollForNewPosts() }
    }
  }

  // MARK: - The feed surface

  private var feedsSurface: some View {
    VStack(spacing: 0) {
      FeedSwitcherBar(
        feeds: model.pinnedFeeds,
        selected: model.selectedDescriptor,
        onSelect: { descriptor in
          Task { await model.select(descriptor) }
        })

      content
        // The pill floats over the list rather than insetting it, so revealing
        // it does not shift the content the user is reading.
        .overlay(alignment: .top) {
          if model.hasNewPosts {
            NewPostsPill {
              Task { await model.tapNewPosts() }
            }
            .padding(.top, Spacing.md)
            .transition(.move(edge: .top).combined(with: .opacity))
          }
        }
        .animation(.easeOut(duration: 0.2), value: model.hasNewPosts)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.pageState {
    case .loading:
      ListSkeleton()
    case .empty:
      ScrollView {
        HomeFeedEmptyState(
          reason: model.selectedDescriptor == .following ? .following : .emptyFeed,
          action: { Task { await model.refresh() } })
          .frame(minHeight: 320)
      }
      .refreshable { await model.refresh() }
    case .error(let error):
      ScrollView {
        HomeFeedErrorState(error: error) {
          Task { await model.refresh() }
        }
        .frame(minHeight: 320)
      }
      .refreshable { await model.refresh() }
    case .content:
      rowList
    }
  }

  private var rowList: some View {
    List {
      ForEach(model.rows) { row in
        HomeFeedRowView(row: row, onOpenRichText: onOpenRichText)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(theme.atomColors.bg)
      }

      if model.showsLoadMore {
        LoadMoreSpinner()
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(theme.atomColors.bg)
          // The native `onEndReached`: the spinner appearing means the user is
          // within one row of the end, so the next page is fetched now.
          .onAppear { Task { await model.loadMore() } }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(theme.atomColors.bg)
    .refreshable { await model.refresh() }
  }

  /// Wraps a full-surface state so it centres on the screen.
  private func centered<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack {
      Spacer(minLength: 0)
      content()
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// One feed row: the reason line, then the slice's posts.
///
/// RN renders a merged thread as a stack with a connector between posts
/// (`showReplyLine` in `src/view/com/post/Post.tsx`); this draws the same stack.
public struct HomeFeedRowView: View {
  private let row: HomeFeedRow
  private let onOpenRichText: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  public init(row: HomeFeedRow, onOpenRichText: @escaping (RichTextTarget) -> Void = { _ in }) {
    self.row = row
    self.onOpenRichText = onOpenRichText
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let reason = row.reason {
        ReasonLine(reason: reason)
      }
      ForEach(row.items) { item in
        PostFeedItem(data: item.data, onOpen: onOpenRichText)
          .overlay(alignment: .leading) {
            if item.showsReplyLine {
              // The thread connector, inset to the avatar's centre line.
              Rectangle()
                .fill(theme.atomColors.borderContrastLow)
                .frame(width: 2)
                .padding(.leading, Spacing.xl + Spacing.md)
                .padding(.vertical, Spacing.xs)
            }
          }
        Divider()
          .overlay(theme.atomColors.borderContrastLow)
      }
    }
  }
}

/// The repost/pin attribution above a row.
struct ReasonLine: View {
  let reason: HomeFeedReasonLine

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: reason.systemImage)
        .font(.system(size: 11, weight: .semibold))
      Text(reason.text)
        .font(TypeScale.sm.font(weight: "500"))
        .lineLimit(1)
    }
    .foregroundStyle(theme.atomColors.textContrastMedium)
    .padding(.leading, Spacing.xxl + Spacing.md)
    .padding(.top, Spacing.sm)
    .accessibilityElement(children: .combine)
  }
}
