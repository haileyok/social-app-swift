import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents
import UIComponentsCore

import NotificationsLogic

/**
 The notifications list screen: reason rows, an unread treatment, the
 All/Mentions/Priority filter, and the empty state.

 ```swift
 NotificationsScreen(rows: fixtureRows)
 ```

 The screen is a render of ``NotificationsListModel``. It fetches nothing and
 decides nothing: whoever owns the session hands it the rows the feed query
 produced, and it draws them. That keeps the surface mountable from the fixture
 hook today and from the real feed once the app shell has a session, without a
 second implementation of the list.

 The RN reference is `~/bluesky/social-app/src/view/screens/Notifications.tsx`
 (two pager tabs, an unread bell, the empty state) plus
 `NotificationFeedItem.tsx` for the row layout.
 */
public struct NotificationsScreen: View {
  private let rows: [FeedNotification]
  private let isInitialLoading: Bool
  private let error: ListState.ListErrorState?
  private let showsFilterBar: Bool
  private let onRefresh: () async -> Void
  private let onOpenPost: (String) -> Void

  @State private var selection: NotificationsFilterTab = .all

  @Environment(\.alfTheme) private var theme

  public init(
    rows: [FeedNotification] = [],
    isInitialLoading: Bool = false,
    error: ListState.ListErrorState? = nil,
    showsFilterBar: Bool = true,
    onRefresh: @escaping () async -> Void = {},
    onOpenPost: @escaping (String) -> Void = { _ in }
  ) {
    self.rows = rows
    self.isInitialLoading = isInitialLoading
    self.error = error
    self.showsFilterBar = showsFilterBar
    self.onRefresh = onRefresh
    self.onOpenPost = onOpenPost
  }

  public var body: some View {
    VStack(spacing: 0) {
      if showsFilterBar {
        NotificationsFilterBar(selection: $selection, unread: model.unread)
      }
      content
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(NotificationsAccessibility.screen)
  }

  /// The rows the current tab shows. The filter is applied by the caller's
  /// query; when the fixture supplies an unfiltered list, the mentions tab still
  /// narrows it here so the control does something.
  private var model: NotificationsListModel {
    let filtered = filteredRows
    return NotificationsListModel(rows: filtered, state: resolvedState(for: filtered))
  }

  private var filteredRows: [FeedNotification] {
    selection == .mentions ? rows.filter { $0.isReplyShaped } : rows
  }

  private func resolvedState(for filtered: [FeedNotification]) -> ListState {
    ListState.resolve(
      itemCount: filtered.count, isInitialLoading: isInitialLoading, error: error)
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      ListSkeleton()
    case .empty:
      emptyState
    case .error(let err):
      ErrorStateView(error: err) {}
    case .content, .loadingMore:
      rowList
    }
  }

  private var rowList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(model.drawableRows, id: \.reactKey) { row in
          rowView(row)
          Divider()
            .foregroundStyle(theme.atomColors.borderContrastLow)
        }
      }
    }
    .refreshable { await onRefresh() }
    .accessibilityIdentifier(NotificationsAccessibility.list)
  }

  /// One row, dispatched by reason: reply-shaped rows draw the subject post,
  /// the rest draw the sentence row.
  @ViewBuilder
  private func rowView(_ row: FeedNotification) -> some View {
    if row.isReplyShaped {
      NotificationPostRow(row: row) { target in
        switch target {
        case .external(let url): onOpenPost(url.absoluteString)
        case .profile(let did): onOpenPost(did)
        case .hashtag(let tag): onOpenPost(tag)
        }
      }
    } else {
      NotificationSentenceRow(row: row, onOpenAuthor: onOpenPost)
    }
  }

  /// The empty state, using the shared notifications copy and bell icon.
  private var emptyState: some View {
    EmptyStateView(
      strings: NotificationsListModel.strings,
      icon: "bell")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier(NotificationsAccessibility.emptyState)
  }
}

#Preview {
  NavigationStack {
    NotificationsScreen(rows: NotificationsFixtures.rows)
      .navigationTitle("Notifications")
      .navigationBarTitleDisplayMode(.inline)
  }
}
