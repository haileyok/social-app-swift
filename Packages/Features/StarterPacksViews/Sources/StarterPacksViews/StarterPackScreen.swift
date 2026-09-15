import DesignSystem
import DesignTokens
import Lexicons
import StarterPacksLogic
import SwiftUI
import UIComponents

/**
 The starter pack detail screen: the header, the tab set, and the tab bodies.

 Ported from `screens/StarterPack/StarterPackScreen.tsx`. The screen derives
 nothing: the tab set comes from ``StarterPackTabs``, the joined line from
 ``StarterPackViewBuilder/joinedLine(_:)``, the sample and follow copy from the
 landing builders, and membership from ``StarterPackMembership``. What is left
 here is layout and the affordances themselves.
 */
public struct StarterPackScreen: View {
  private let detail: StarterPackDetail
  private let members: [App.Bsky.GraphDefs_ListItemView]
  private let optedOutDIDs: Set<String>
  private let membership: StarterPackMembership?
  private let shareData: StarterPackShareData?
  private let isDeletedListOwned: Bool
  private let isProcessing: Bool

  private let onJoin: () -> Void
  private let onLeave: () -> Void
  private let onFollowAll: () -> Void
  private let onShare: () -> Void
  private let onEdit: () -> Void
  private let onLoadMoreMembers: (() -> Void)?

  @State private var selectedTab: Tab = .people
  @State private var isSharePresented = false

  @Environment(\.alfTheme) private var theme

  /// The tabs the screen can show.
  public enum Tab: String, CaseIterable, Hashable, Sendable {
    /// The member list.
    case people
    /// The pinned feeds.
    case feeds
    /// The posts the backing list backs, rendered by the feed surface.
    case posts

    /// The tab's label.
    public var label: String {
      switch self {
      case .people: StarterPackCopy.peopleTab
      case .feeds: StarterPackCopy.feedsTab
      case .posts: StarterPackCopy.postsTab
      }
    }

    /// The tab's accessibility identifier.
    public var identifier: String {
      switch self {
      case .people: StarterPackAccessibility.peopleTab
      case .feeds: StarterPackAccessibility.feedsTab
      case .posts: StarterPackAccessibility.postsTab
      }
    }
  }

  /// Creates the screen.
  ///
  /// - Parameters:
  ///   - detail: the presentation-ready pack.
  ///   - members: the members to render. The caller pages
  ///     ``StarterPackMembersQuery`` and passes the merged list.
  ///   - optedOutDIDs: members who opted out, from
  ///     ``StarterPackMemberSelection/optedOutDIDs(_:)``.
  ///   - membership: the viewer's membership, or nil when unknown.
  ///   - shareData: the share payload, built by ``StarterPackShare/shareData(_:shortLink:)``.
  ///   - isDeletedListOwned: whether the viewer owns a pack whose list is gone.
  ///   - isProcessing: whether a membership write is in flight.
  ///   - onJoin / onLeave: the membership write.
  ///   - onFollowAll: the bulk follow, whose targets the caller derives with
  ///     ``StarterPackMembersQuery/followAllTargets(items:viewerDID:)``.
  ///   - onShare: opens the platform share sheet with
  ///     ``StarterPackShare/shareURL(_:)``.
  ///   - onEdit: opens the edit wizard.
  ///   - onLoadMoreMembers: appends the next member page, or nil when there is
  ///     only one page.
  public init(
    detail: StarterPackDetail,
    members: [App.Bsky.GraphDefs_ListItemView] = [],
    optedOutDIDs: Set<String> = [],
    membership: StarterPackMembership? = nil,
    shareData: StarterPackShareData? = nil,
    isDeletedListOwned: Bool = false,
    isProcessing: Bool = false,
    onJoin: @escaping () -> Void = {},
    onLeave: @escaping () -> Void = {},
    onFollowAll: @escaping () -> Void = {},
    onShare: @escaping () -> Void = {},
    onEdit: @escaping () -> Void = {},
    onLoadMoreMembers: (() -> Void)? = nil
  ) {
    self.detail = detail
    self.members = members
    self.optedOutDIDs = optedOutDIDs
    self.membership = membership
    self.shareData = shareData
    self.isDeletedListOwned = isDeletedListOwned
    self.isProcessing = isProcessing
    self.onJoin = onJoin
    self.onLeave = onLeave
    self.onFollowAll = onFollowAll
    self.onShare = onShare
    self.onEdit = onEdit
    self.onLoadMoreMembers = onLoadMoreMembers
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if isDeletedListOwned {
          deletedListState
        }
        header
        if availableTabs.count > 1 {
          tabBar
        }
        tabBody
      }
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(StarterPackAccessibility.screen)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if shareData != nil {
          Button {
            isSharePresented = true
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel(StarterPackCopy.shareAction)
          .accessibilityIdentifier(StarterPackAccessibility.shareButton)
        }
      }
    }
    .sheet(isPresented: $isSharePresented) {
      if let shareData {
        StarterPackShareSheet(
          detail: detail,
          data: shareData,
          onShareLink: {
            onShare()
            isSharePresented = false
          })
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
    }
    .onAppear(perform: selectDefaultTab)
  }

  // MARK: - Sections

  /// The tabs this pack actually has, in RN's order: people, feeds, posts.
  var availableTabs: [Tab] {
    var tabs: [Tab] = []
    if StarterPackTabs.showsPeople(detail) { tabs.append(.people) }
    if StarterPackTabs.showsFeeds(detail) { tabs.append(.feeds) }
    if StarterPackTabs.showsPosts(detail) { tabs.append(.posts) }
    return tabs.isEmpty ? [.people] : tabs
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      if let banner = detail.listItemsSample.first?.subject.avatar?.rawValue {
        Banner(banner: banner, height: 84)
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        AlfText(detail.name, scale: .xxl, weight: Scales.FontWeight.bold)
          .fixedSize(horizontal: false, vertical: true)
        AlfText(
          StarterPackCopy.landingBy + " @\(detail.creatorHandle)", scale: .sm,
          color: theme.atomColors.textContrastMedium)
          .lineLimit(1)
        if let description = detail.description, !description.isEmpty {
          AlfText(description, scale: .sm)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      statLine
      actionRow
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.md)
    .padding(.bottom, Spacing.md)
    .accessibilityIdentifier(StarterPackAccessibility.header)
    .accessibilityElement(children: .contain)
  }

  /// The "N people joined" line, which ``StarterPackViewBuilder/joinedLine(_:)``
  /// gates at the threshold. The member count always shows.
  private var statLine: some View {
    HStack(spacing: Spacing.md) {
      if StarterPackViewBuilder.joinedLine(detail) != nil {
        AlfText(
          StarterPackCopy.joinedLine(count: detail.joinedAllTimeCount), scale: .xs
        )
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .accessibilityIdentifier(StarterPackAccessibility.joinedLine)
      }
      if StarterPackTabs.showsPeople(detail) {
        AlfText(
          "\(detail.listItemCount) \(StarterPackCopy.membersHeading.lowercased())", scale: .xs,
          color: theme.atomColors.textContrastMedium)
      }
      Spacer(minLength: 0)
    }
  }

  private var actionRow: some View {
    HStack(spacing: Spacing.sm) {
      membershipButton
      if StarterPackTabs.showsPeople(detail), !members.isEmpty {
        AlfButton(StarterPackCopy.followAllAction, color: .secondary, size: .small) {
          onFollowAll()
        }
        .accessibilityIdentifier(StarterPackAccessibility.followAllButton)
      }
      if detail.isOwn {
        AlfButton(StarterPackCopy.editAction, color: .secondary, size: .small) {
          onEdit()
        }
        .accessibilityIdentifier(StarterPackAccessibility.editButton)
      }
      Spacer(minLength: 0)
    }
  }

  /// The join/joined control. When there is no membership to read, the screen
  /// offers the join affordance rather than guessing.
  @ViewBuilder private var membershipButton: some View {
    if membership?.isMember == true {
      AlfButton(
        isProcessing ? StarterPackCopy.leaveAction : StarterPackCopy.joinedAction,
        color: .secondary, size: .small
      ) {
        onLeave()
      }
      .disabled(isProcessing)
      .accessibilityIdentifier(StarterPackAccessibility.joinButton)
    } else {
      AlfButton(StarterPackCopy.joinAction, color: .primary, size: .small) {
        onJoin()
      }
      .disabled(isProcessing || !StarterPackTabs.showsPeople(detail))
      .accessibilityIdentifier(StarterPackAccessibility.joinButton)
    }
  }

  private var deletedListState: some View {
    // The owner can still open the pack, but its members are unreachable; RN
    // shows the same call-out above the header.
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(StarterPackCopy.deletedListTitle, scale: .sm, weight: Scales.FontWeight.semiBold)
        AlfText(
          StarterPackCopy.deletedListMessage, scale: .xs,
          color: theme.atomColors.textContrastMedium)
      }
      Spacer(minLength: 0)
    }
    .padding(Spacing.md)
    .background(theme.atomColors.bgContrast50)
    .accessibilityIdentifier(StarterPackAccessibility.deletedListState)
  }

  private var tabBar: some View {
    VStack(spacing: 0) {
      HStack(spacing: Spacing.lg) {
        ForEach(availableTabs, id: \.self) { tab in
          Button {
            selectedTab = tab
          } label: {
            VStack(spacing: Spacing.xs) {
              AlfText(
                tab.label, scale: .sm,
                weight: selectedTab == tab
                  ? Scales.FontWeight.semiBold : Scales.FontWeight.normal,
                color: selectedTab == tab
                  ? theme.atomColors.text : theme.atomColors.textContrastMedium)
              Rectangle()
                .fill(selectedTab == tab ? theme.atomColors.text : .clear)
                .frame(height: 2)
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(tab.identifier)
          .accessibilityAddTraits(selectedTab == tab ? AccessibilityTraits.isSelected : [])
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.lg)
      Divider()
        .overlay(theme.atomColors.borderContrastLow)
    }
    .accessibilityIdentifier(StarterPackAccessibility.tabBar)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var tabBody: some View {
    switch selectedTab {
    case .people: peopleTab
    case .feeds: feedsTab
    case .posts: postsTab
    }
  }

  private var peopleTab: some View {
    VStack(alignment: .leading, spacing: 0) {
      if members.isEmpty {
        EmptyStateView(
          icon: "person.2",
          title: StarterPackCopy.membersEmptyTitle,
          message: StarterPackCopy.membersEmptyMessage)
          .frame(minHeight: 240)
      } else {
        StarterPackMemberCollection(
          members: members, layout: .grid, optedOutDIDs: optedOutDIDs)
        if onLoadMoreMembers != nil {
          Button {
            onLoadMoreMembers?()
          } label: {
            AlfButtonText("Load more")
          }
          .buttonStyle(.alf(color: .secondary, size: .small, shape: .rectangular))
          .frame(maxWidth: .infinity)
          .padding(Spacing.md)
        }
      }
    }
  }

  private var feedsTab: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(detail.feeds, id: \.uri.rawValue) { feed in
        StarterPackFeedRow(feed: feed)
        Divider()
          .overlay(theme.atomColors.borderContrastLow)
      }
    }
  }

  /// The posts tab feeds the backing list to the feed surface. That surface is
  /// owned by the feed feature, so the screen shows the list-backed placeholder
  /// rather than re-implementing a post list here.
  private var postsTab: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if let listURI = StarterPackViewBuilder.postsListURI(detail) {
        AlfText("Posts", scale: .sm, weight: Scales.FontWeight.semiBold)
        AlfText(listURI, scale: .xs, color: theme.atomColors.textContrastMedium)
          .lineLimit(2)
      }
      EmptyStateView(
        icon: "text.bubble",
        title: StarterPackCopy.postsTab,
        message: "Posts from this pack's list are shown by the feed surface.")
        .frame(minHeight: 200)
    }
    .padding(Spacing.md)
  }

  /// Selects the first tab the pack actually has, once the pack is known.
  private func selectDefaultTab() {
    if !availableTabs.contains(selectedTab), let first = availableTabs.first {
      selectedTab = first
    }
  }
}
