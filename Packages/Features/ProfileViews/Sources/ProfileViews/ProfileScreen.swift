import DesignSystem
import DesignTokens
import ProfileLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The record identity and viewer state needed to mutate a profile-feed post.
public struct ProfilePostInteraction: Sendable {
  public let uri: String
  public let cid: String
  public let likeURI: String?
  public let repostURI: String?

  public init(uri: String, cid: String, likeURI: String?, repostURI: String?) {
    self.uri = uri
    self.cid = cid
    self.likeURI = likeURI
    self.repostURI = repostURI
  }
}

/// The paged content a profile screen shows, keyed by tab.
///
/// The screen is a render: it does not own a query store or a client, so the
/// caller supplies the already-fetched rows and states. That is what lets the
/// same screen back the fixture surface (which supplies fixture rows) and a live
/// screen (which supplies rows from an ``InfiniteQuery``) without the view
/// knowing which it is.
public struct ProfileScreenContent: Sendable {
  /// The rows per feed tab.
  public var feedItems: [ProfileTab: [FeedItemViewData]]
  /// Mutation targets parallel to `feedItems`; fixture-only content may omit them.
  public var interactions: [ProfileTab: [ProfilePostInteraction]]
  /// The list state per section. A section with no entry reads as ``.content``
  /// when it has rows and ``.empty`` when it does not.
  public var states: [ProfileSection: ListState]

  public init(
    feedItems: [ProfileTab: [FeedItemViewData]] = [:],
    interactions: [ProfileTab: [ProfilePostInteraction]] = [:],
    states: [ProfileSection: ListState] = [:]
  ) {
    self.feedItems = feedItems
    self.interactions = interactions
    self.states = states
  }

  /// The rows for a section's feed tab, empty for a non-feed section.
  public func items(for section: ProfileSection) -> [FeedItemViewData] {
    guard let tab = Self.tab(for: section) else { return [] }
    return feedItems[tab] ?? []
  }

  public func interaction(for section: ProfileSection, at index: Int) -> ProfilePostInteraction? {
    guard let tab = Self.tab(for: section),
      let targets = interactions[tab],
      targets.indices.contains(index)
    else { return nil }
    return targets[index]
  }

  /// The state for a section, derived from its rows when not given explicitly.
  public func state(for section: ProfileSection) -> ListState {
    if let state = states[section] { return state }
    return items(for: section).isEmpty ? .empty : .content
  }

  /// The feed tab a section renders, or `nil` for the non-feed sections.
  ///
  /// The profile's `filters`, `feeds`, `lists`, and `starterPacks` sections are
  /// served by other features (labeler feeds, feed generators, lists, starter
  /// packs); they stay in the tab set but render a placeholder here.
  public static func tab(for section: ProfileSection) -> ProfileTab? {
    switch section {
    case .posts: .posts
    case .replies: .replies
    case .media: .media
    case .videos: .videos
    case .likes: .likes
    case .filters, .lists, .feeds, .starterPacks: nil
    }
  }
}

/// The profile screen: header, tab bar, and paged content.
///
/// Port of `src/view/screens/Profile.tsx`. The header is ``ProfileHeader``, the
/// bar is driven by ``ProfileTabVisibility/sections``, and the pages are a
/// native `TabView` in `.page` style so a swipe moves between tabs.
///
/// The screen takes its whole state from ``ProfileHeaderViewData`` and
/// ``ProfileScreenContent``, so the fixture surface can render any variant
/// (labeler, blocked, blurred, pending follow) without a network.
///
/// ```swift
/// ProfileScreen(headerData: data, content: content)
/// ```
public struct ProfileScreen: View {
  private let headerData: ProfileHeaderViewData
  private let labeler: LabelerProfileViewData?
  private let content: ProfileScreenContent
  private let strings: any ProfileStrings
  private let onOpen: (RichTextTarget) -> Void
  private let onLikePost: (ProfilePostInteraction) async -> Void
  private let onRepostPost: (ProfilePostInteraction) async -> Void
  private let onAction: (ProfileHeaderAction) -> Void

  @Environment(\.alfTheme) private var theme
  @State private var selected: ProfileSection

  public init(
    headerData: ProfileHeaderViewData,
    labeler: LabelerProfileViewData? = nil,
    content: ProfileScreenContent = ProfileScreenContent(),
    strings: any ProfileStrings = defaultProfileStrings,
    onOpen: @escaping (RichTextTarget) -> Void = { _ in },
    onLikePost: @escaping (ProfilePostInteraction) async -> Void = { _ in },
    onRepostPost: @escaping (ProfilePostInteraction) async -> Void = { _ in },
    onAction: @escaping (ProfileHeaderAction) -> Void = { _ in }
  ) {
    self.headerData = headerData
    self.labeler = labeler
    self.content = content
    self.strings = strings
    self.onOpen = onOpen
    self.onLikePost = onLikePost
    self.onRepostPost = onRepostPost
    self.onAction = onAction
    _selected = State(initialValue: headerData.tabs.sections.first ?? .posts)
  }

  private var sections: [ProfileSection] { headerData.tabs.sections }

  public var body: some View {
    VStack(spacing: 0) {
      ProfileHeader(
        data: headerData,
        labeler: labeler,
        strings: strings,
        onAction: onAction)
      ProfileTabBar(
        sections: sections,
        selected: selected,
        strings: strings) { section in
        selected = section
      }
      pager
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier("profileScreen")
  }

  /// The paged body. `.page` style gives the native horizontal swipe between
  /// sections; the index indicator is hidden because the tab bar is the
  /// indicator.
  private var pager: some View {
    TabView(selection: $selected) {
      ForEach(sections, id: \.rawValue) { section in
        page(for: section)
          .tag(section)
      }
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
  }

  @ViewBuilder
  private func page(for section: ProfileSection) -> some View {
    let items = content.items(for: section)
    switch content.state(for: section) {
    case .loading where items.isEmpty:
      ListSkeleton()
    case .error(let error) where items.isEmpty:
      ErrorStateView(error: error) { onAction(.reload) }
    case .empty where !Self.isFeedSection(section):
      placeholderPage(section)
    case .empty:
      EmptyStateView(
        icon: "text.bubble",
        title: section.title,
        message: strings.emptyList(section.title))
    default:
      feedPage(section, items: items)
    }
  }

  private static func isFeedSection(_ section: ProfileSection) -> Bool {
    ProfileScreenContent.tab(for: section) != nil
  }

  private func feedPage(_ section: ProfileSection, items: [FeedItemViewData]) -> some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          let interaction = content.interaction(for: section, at: index)
          PostFeedItem(
            data: item,
            onOpen: onOpen,
            onOpenAuthor: { onOpen(.profile(did: $0)) },
            onReply: interaction.map { target in { onOpen(.post(uri: target.uri)) } },
            onRepost: interaction.map { target in { Task { await onRepostPost(target) } } },
            onLike: interaction.map { target in { Task { await onLikePost(target) } } })
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
          Divider().padding(.leading, Spacing.xxl)
        }
        if case .loadingMore = content.state(for: section) {
          LoadMoreSpinner().padding(.vertical, Spacing.md)
        }
      }
    }
  }

  /// A section whose content another feature owns.
  private func placeholderPage(_ section: ProfileSection) -> some View {
    EmptyStateView(
      icon: "square.grid.2x2",
      title: section.title,
      message: strings.emptyList(section.title))
  }
}
