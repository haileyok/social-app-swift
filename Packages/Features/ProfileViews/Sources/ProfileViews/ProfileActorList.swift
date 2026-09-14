import DesignSystem
import DesignTokens
import Lexicons
import Moderation
import ProfileLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// A paginated list of actors: the followers, follows, and known-followers
/// screens all render through this.
///
/// The list itself is passive: the page items, the load-more state, and the
/// errors all arrive from the caller, because the data lives in an
/// ``InfiniteQuery`` the screen owns. That keeps the view reusable across the
/// three screens (which differ only in title, sort control, and the
/// known-followers header row) and testable without a query store.
public struct ProfileActorList: View {
  private let title: String
  private let items: [ProfileView]
  private let state: ListState
  private let strings: any ProfileStrings
  private let moderationOpts: ModerationOpts?
  private let sort: ActorListSort?
  private let onSelectSort: ((ActorListSort) -> Void)?
  private let onSelect: (ProfileView) -> Void
  private let onLoadMore: () -> Void
  private let onRetry: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    title: String,
    items: [ProfileView],
    state: ListState = .loading,
    strings: any ProfileStrings = defaultProfileStrings,
    moderationOpts: ModerationOpts? = nil,
    sort: ActorListSort? = nil,
    onSelectSort: ((ActorListSort) -> Void)? = nil,
    onSelect: @escaping (ProfileView) -> Void = { _ in },
    onLoadMore: @escaping () -> Void = {},
    onRetry: @escaping () -> Void = {}
  ) {
    self.title = title
    self.items = items
    self.state = state
    self.strings = strings
    self.moderationOpts = moderationOpts
    self.sort = sort
    self.onSelectSort = onSelectSort
    self.onSelect = onSelect
    self.onLoadMore = onLoadMore
    self.onRetry = onRetry
  }

  public var body: some View {
    Group {
      switch state {
      case .loading where items.isEmpty:
        ListSkeleton()
      case .error(let error) where items.isEmpty:
        ErrorStateView(error: error, retry: onRetry)
      case .empty:
        EmptyStateView(
          icon: "person.2",
          title: title,
          message: strings.emptyList(title))
      default:
        list
      }
    }
    .navigationTitle(title)
  }

  private var list: some View {
    List {
      if let sort, let onSelectSort {
        sortRow(sort: sort, onSelectSort: onSelectSort)
      }
      ForEach(items, id: \.did) { item in
        ProfileListRow(
          profile: item,
          moderationOpts: moderationOpts,
          strings: strings,
          onSelect: { onSelect(item) })
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
      }
      if case .loadingMore = state {
        LoadMoreSpinner()
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
      }
      if case .error(let error) = state, error.hasContent {
        RetryRow(message: error.message, retry: onLoadMore)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
      }
    }
    .listStyle(.plain)
    .onAppear {
      if case .loadingMore = state { onLoadMore() }
    }
  }

  /// The Latest / Top segmented control the follows and followers screens carry.
  private func sortRow(
    sort: ActorListSort,
    onSelectSort: @escaping (ActorListSort) -> Void
  ) -> some View {
    Picker("Sort", selection: Binding(get: { sort }, set: onSelectSort)) {
      Text("Latest").tag(ActorListSort.latest)
      Text("Top").tag(ActorListSort.top)
    }
    .pickerStyle(.segmented)
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.sm)
    .listRowInsets(EdgeInsets())
    .listRowSeparator(.hidden)
  }
}
