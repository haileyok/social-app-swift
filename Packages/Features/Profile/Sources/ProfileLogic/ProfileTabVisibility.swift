import Lexicons
import Foundation

/// Which tabs a profile screen shows, and in what order.
///
/// Port of the tab gating in `src/view/screens/Profile.tsx`:
///
/// ```ts
/// const hasLabeler = !!profile.associated?.labeler
/// const showFiltersTab = hasLabeler
/// const showPostsTab = true
/// const showRepliesTab = hasSession
/// const showMediaTab = !hasLabeler
/// const showVideosTab = !hasLabeler
/// const showLikesTab = isMe
/// const showFeedsTab = isMe || feedGenCount > 0
/// const showStarterPacksTab = isMe || starterPackCount > 0
/// const listCount = (profile.associated?.lists || 0) - starterPackCount
/// const showListsTab = hasSession && (isMe || listCount > 0)
/// ```
///
/// The RN screen also has a `Labels` (filters) tab and `Feeds` / `Starter Packs`
/// / `Lists` tabs. They do not issue a feed query, but they are part of the same
/// section list, so the derivation is kept whole and the extra sections are
/// modelled as ``ProfileSection`` cases rather than dropped.
public struct ProfileTabVisibility: Sendable, Equatable {
  /// Whether the profile is the signed-in account's own.
  public let isMe: Bool
  /// Whether there is a signed-in session at all.
  public let hasSession: Bool
  /// `profile.associated?.labeler`.
  public let hasLabeler: Bool
  /// `profile.associated?.feedgens ?? 0`.
  public let feedGeneratorCount: Int
  /// `profile.associated?.starterPacks ?? 0`.
  public let starterPackCount: Int
  /// `profile.associated?.lists ?? 0`, before the starter-pack subtraction.
  public let rawListCount: Int

  /// Derives the visibility inputs from a loaded profile.
  public init(profile: App.Bsky.ActorDefs_ProfileViewDetailed, viewerDid: String?, hasSession: Bool)
  {
    self.isMe = viewerDid != nil && profile.did.rawValue == viewerDid
    self.hasSession = hasSession
    self.hasLabeler = profile.associated?.labeler == true
    self.feedGeneratorCount = profile.associated?.feedgens ?? 0
    self.starterPackCount = profile.associated?.starterPacks ?? 0
    self.rawListCount = profile.associated?.lists ?? 0
  }

  /// Direct initialiser, for tests that exercise the gating without a profile.
  public init(
    isMe: Bool,
    hasSession: Bool,
    hasLabeler: Bool,
    feedGeneratorCount: Int = 0,
    starterPackCount: Int = 0,
    rawListCount: Int = 0
  ) {
    self.isMe = isMe
    self.hasSession = hasSession
    self.hasLabeler = hasLabeler
    self.feedGeneratorCount = feedGeneratorCount
    self.starterPackCount = starterPackCount
    self.rawListCount = rawListCount
  }

  /// `(associated.lists || 0) - starterPackCount`, because starter packs are a
  /// kind of list and would otherwise be counted twice.
  public var listCount: Int { rawListCount - starterPackCount }

  public var showFiltersTab: Bool { hasLabeler }
  public var showPostsTab: Bool { true }
  public var showRepliesTab: Bool { hasSession }
  public var showMediaTab: Bool { !hasLabeler }
  public var showVideosTab: Bool { !hasLabeler }
  public var showLikesTab: Bool { isMe }
  public var showFeedsTab: Bool { isMe || feedGeneratorCount > 0 }
  public var showStarterPacksTab: Bool { isMe || starterPackCount > 0 }
  public var showListsTab: Bool { hasSession && (isMe || listCount > 0) }

  /// The section list, in render order.
  ///
  /// RN builds `sectionTitles` positionally and then locates each index by
  /// re-walking the same flags; producing the ordered list once removes that
  /// duplication while keeping the order identical.
  public var sections: [ProfileSection] {
    var result: [ProfileSection] = []
    if showFiltersTab { result.append(.filters) }
    if showListsTab && hasLabeler { result.append(.lists) }
    if showPostsTab { result.append(.posts) }
    if showRepliesTab { result.append(.replies) }
    if showMediaTab { result.append(.media) }
    if showVideosTab { result.append(.videos) }
    if showLikesTab { result.append(.likes) }
    if showFeedsTab { result.append(.feeds) }
    if showStarterPacksTab { result.append(.starterPacks) }
    if showListsTab && !hasLabeler { result.append(.lists) }
    return result
  }

  /// The tabs whose content is an author feed, in render order.
  public var feedTabs: [ProfileTab] {
    [ProfileTab.posts, .replies, .media, .videos, .likes].filter { tab in
      switch tab {
      case .posts: showPostsTab
      case .replies: showRepliesTab
      case .media: showMediaTab
      case .videos: showVideosTab
      case .likes: showLikesTab
      }
    }
  }
}

/// One section of the profile pager.
public enum ProfileSection: String, Sendable, Hashable, CaseIterable {
  case filters
  case lists
  case posts
  case replies
  case media
  case videos
  case likes
  case feeds
  case starterPacks
}
