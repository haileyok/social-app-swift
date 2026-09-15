import Foundation
import Lexicons
import Testing

@testable import ProfileLogic

/// The profile pager's tab gating and ordering.
@Suite("Profile tab visibility") struct ProfileTabVisibilityTests {

  /// The default profile: posts always, replies with a session, no labeler.
  @Test func defaultProfileShowsPostsAndReplies() {
    let tabs = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: false)
    #expect(tabs.showPostsTab)
    #expect(tabs.showRepliesTab)
    #expect(tabs.showMediaTab)
    #expect(tabs.showVideosTab)
    #expect(!tabs.showLikesTab, "likes are the viewer's own")
    #expect(!tabs.showFeedsTab)
    #expect(!tabs.showListsTab)
    #expect(!tabs.showFiltersTab)
    #expect(tabs.sections == [.posts, .replies, .media, .videos])
  }

  /// A labeler profile swaps the feed tabs for the labels tab.
  @Test func labelerProfileShowsFiltersAndHidesMediaAndVideos() {
    let tabs = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: true)
    #expect(tabs.showFiltersTab, "a labeler shows its labels")
    #expect(!tabs.showMediaTab)
    #expect(!tabs.showVideosTab)
    #expect(tabs.showPostsTab)
    #expect(tabs.sections == [.filters, .posts, .replies])
  }

  /// Signed out, the replies tab is gone; the rest follow the same rules.
  @Test func signedOutHidesReplies() {
    let tabs = ProfileTabVisibility(isMe: false, hasSession: false, hasLabeler: false)
    #expect(!tabs.showRepliesTab)
    #expect(tabs.sections == [.posts, .media, .videos])
  }

  /// The viewer's own profile adds likes, feeds and starter packs.
  @Test func ownProfileShowsLikesFeedsAndStarterPacks() {
    let tabs = ProfileTabVisibility(isMe: true, hasSession: true, hasLabeler: false)
    #expect(tabs.showLikesTab)
    #expect(tabs.showFeedsTab)
    #expect(tabs.showStarterPacksTab)
    #expect(tabs.showListsTab)
    #expect(tabs.sections == [.posts, .replies, .media, .videos, .likes, .feeds, .starterPacks, .lists])
  }

  /// The feeds tab appears for another account that has feed generators.
  @Test func feedsTabAppearsForNonEmptyFeedgenCount() {
    let none = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: false, feedGeneratorCount: 0)
    let some = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: false, feedGeneratorCount: 2)
    #expect(!none.showFeedsTab)
    #expect(some.showFeedsTab)
  }

  /// The starter-packs tab behaves the same way.
  @Test func starterPacksTabAppearsForNonEmptyCount() {
    let none = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: false, starterPackCount: 0)
    let some = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: false, starterPackCount: 1)
    #expect(!none.showStarterPacksTab)
    #expect(some.showStarterPacksTab)
  }

  /// Starter packs are a kind of list, so the list count subtracts them - which
  /// is the arithmetic RN does to decide whether the lists tab appears.
  @Test func listCountSubtractsStarterPacks() {
    let starterPacksOnly = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: false,
      starterPackCount: 3, rawListCount: 3)
    #expect(starterPacksOnly.listCount == 0)
    #expect(!starterPacksOnly.showListsTab, "starter packs alone are not lists")

    let withRealLists = ProfileTabVisibility(
      isMe: false, hasSession: true, hasLabeler: false,
      starterPackCount: 3, rawListCount: 5)
    #expect(withRealLists.listCount == 2)
    #expect(withRealLists.showListsTab)
  }

  /// A labeler profile places the lists section early; a normal one places it
  /// last. Both come from the same `showListsTab`.
  @Test func listsSectionMovesForLabelers() {
    let labeler = ProfileTabVisibility(
      isMe: true, hasSession: true, hasLabeler: true, rawListCount: 1)
    #expect(labeler.sections.prefix(2) == [.filters, .lists])

    let normal = ProfileTabVisibility(
      isMe: true, hasSession: true, hasLabeler: false, rawListCount: 1)
    #expect(normal.sections.last == .lists)
  }

  /// Signed out, the lists tab never shows even when the profile has lists.
  @Test func signedOutHasNoListsTab() {
    let tabs = ProfileTabVisibility(
      isMe: false, hasSession: false, hasLabeler: false, rawListCount: 9)
    #expect(!tabs.showListsTab)
  }

  /// The feed tabs are the ordered subset of the sections that issue a feed
  /// query.
  @Test func feedTabsAreTheOrderedFeedSectionSubset() {
    let tabs = ProfileTabVisibility(isMe: true, hasSession: true, hasLabeler: false)
    #expect(tabs.feedTabs == [.posts, .replies, .media, .videos, .likes])
  }

  /// The visibility derives from the profile's associated block.
  @Test func visibilityDerivesFromTheProfile() {
    let profile = makeProfile(feedgens: 4, starterPacks: 2, lists: 3)
    let tabs = ProfileTabVisibility(profile: profile, viewerDid: "did:plc:me", hasSession: true)
    #expect(tabs.feedGeneratorCount == 4)
    #expect(tabs.starterPackCount == 2)
    #expect(tabs.listCount == 1)
    #expect(tabs.showFeedsTab)
    #expect(tabs.showStarterPacksTab)
    #expect(tabs.showListsTab)
    #expect(!tabs.isMe)
  }

  /// The viewer's own DID sets `isMe`.
  @Test func isMeComparesTheViewerDid() {
    let profile = makeProfile(did: "did:plc:alice")
    #expect(ProfileTabVisibility(profile: profile, viewerDid: "did:plc:alice", hasSession: true).isMe)
    #expect(!ProfileTabVisibility(profile: profile, viewerDid: "did:plc:bob", hasSession: true).isMe)
    #expect(!ProfileTabVisibility(profile: profile, viewerDid: nil, hasSession: false).isMe)
  }

  /// The labeler flag comes from `associated.labeler`.
  @Test func hasLabelerComesFromAssociated() {
    let labeler = makeProfile(labeler: true)
    let plain = makeProfile(labeler: false)
    #expect(ProfileTabVisibility(profile: labeler, viewerDid: nil, hasSession: true).hasLabeler)
    #expect(!ProfileTabVisibility(profile: plain, viewerDid: nil, hasSession: true).hasLabeler)
  }
}
