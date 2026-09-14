import Lexicons
import Moderation
import ProfileLogic
import SwiftUI
import UIComponentsCore

/// The followers screen.
///
/// Port of `src/view/com/profile/ProfileFollowers.tsx`: a sort control, an
/// optional known-followers header, and the paginated actor list. The paging
/// state arrives from the caller's ``InfiniteQuery``, so this screen is a render
/// over ``ProfileActorList``.
public struct FollowersScreen: View {
  private let actor: String
  private let items: [ProfileView]
  private let state: ListState
  private let sort: ActorListSort
  private let knownFollowersCount: Int
  private let moderationOpts: ModerationOpts?
  private let strings: any ProfileStrings
  private let onSelectSort: (ActorListSort) -> Void
  private let onSelectKnownFollowers: () -> Void
  private let onSelect: (ProfileView) -> Void
  private let onLoadMore: () -> Void
  private let onRetry: () -> Void

  public init(
    actor: String,
    items: [ProfileView] = [],
    state: ListState = .loading,
    sort: ActorListSort = .latest,
    knownFollowersCount: Int = 0,
    moderationOpts: ModerationOpts? = nil,
    strings: any ProfileStrings = defaultProfileStrings,
    onSelectSort: @escaping (ActorListSort) -> Void = { _ in },
    onSelectKnownFollowers: @escaping () -> Void = {},
    onSelect: @escaping (ProfileView) -> Void = { _ in },
    onLoadMore: @escaping () -> Void = {},
    onRetry: @escaping () -> Void = {}
  ) {
    self.actor = actor
    self.items = items
    self.state = state
    self.sort = sort
    self.knownFollowersCount = knownFollowersCount
    self.moderationOpts = moderationOpts
    self.strings = strings
    self.onSelectSort = onSelectSort
    self.onSelectKnownFollowers = onSelectKnownFollowers
    self.onSelect = onSelect
    self.onLoadMore = onLoadMore
    self.onRetry = onRetry
  }

  public var body: some View {
    VStack(spacing: 0) {
      if knownFollowersCount > 0 {
        KnownFollowersPill(count: knownFollowersCount, onSelect: onSelectKnownFollowers)
      }
      ProfileActorList(
        title: strings.followers,
        items: items,
        state: state,
        strings: strings,
        moderationOpts: moderationOpts,
        sort: sort,
        onSelectSort: onSelectSort,
        onSelect: onSelect,
        onLoadMore: onLoadMore,
        onRetry: onRetry)
    }
  }
}

/// The follows screen.
///
/// Port of `src/view/com/profile/ProfileFollows.tsx`. It is the followers screen
/// without the known-followers header and with the `Following` title.
public struct FollowsScreen: View {
  private let actor: String
  private let items: [ProfileView]
  private let state: ListState
  private let sort: ActorListSort
  private let moderationOpts: ModerationOpts?
  private let strings: any ProfileStrings
  private let onSelectSort: (ActorListSort) -> Void
  private let onSelect: (ProfileView) -> Void
  private let onLoadMore: () -> Void
  private let onRetry: () -> Void

  public init(
    actor: String,
    items: [ProfileView] = [],
    state: ListState = .loading,
    sort: ActorListSort = .latest,
    moderationOpts: ModerationOpts? = nil,
    strings: any ProfileStrings = defaultProfileStrings,
    onSelectSort: @escaping (ActorListSort) -> Void = { _ in },
    onSelect: @escaping (ProfileView) -> Void = { _ in },
    onLoadMore: @escaping () -> Void = {},
    onRetry: @escaping () -> Void = {}
  ) {
    self.actor = actor
    self.items = items
    self.state = state
    self.sort = sort
    self.moderationOpts = moderationOpts
    self.strings = strings
    self.onSelectSort = onSelectSort
    self.onSelect = onSelect
    self.onLoadMore = onLoadMore
    self.onRetry = onRetry
  }

  public var body: some View {
    ProfileActorList(
      title: strings.follows,
      items: items,
      state: state,
      strings: strings,
      moderationOpts: moderationOpts,
      sort: sort,
      onSelectSort: onSelectSort,
      onSelect: onSelect,
      onLoadMore: onLoadMore,
      onRetry: onRetry)
  }
}

/// The known-followers screen.
///
/// Port of the known-followers list the profile header links to: the same actor
/// list, with its own title and no sort control (the API takes no `sort`).
public struct KnownFollowersScreen: View {
  private let items: [ProfileView]
  private let state: ListState
  private let moderationOpts: ModerationOpts?
  private let strings: any ProfileStrings
  private let onSelect: (ProfileView) -> Void
  private let onLoadMore: () -> Void
  private let onRetry: () -> Void

  public init(
    items: [ProfileView] = [],
    state: ListState = .loading,
    moderationOpts: ModerationOpts? = nil,
    strings: any ProfileStrings = defaultProfileStrings,
    onSelect: @escaping (ProfileView) -> Void = { _ in },
    onLoadMore: @escaping () -> Void = {},
    onRetry: @escaping () -> Void = {}
  ) {
    self.items = items
    self.state = state
    self.moderationOpts = moderationOpts
    self.strings = strings
    self.onSelect = onSelect
    self.onLoadMore = onLoadMore
    self.onRetry = onRetry
  }

  public var body: some View {
    ProfileActorList(
      title: "Followers you know",
      items: items,
      state: state,
      strings: strings,
      moderationOpts: moderationOpts,
      onSelect: onSelect,
      onLoadMore: onLoadMore,
      onRetry: onRetry)
  }
}
