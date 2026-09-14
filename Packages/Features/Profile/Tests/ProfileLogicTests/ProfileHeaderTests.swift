import Foundation
import Lexicons
import Moderation
import SwiftAtproto
import Testing

@testable import ProfileLogic

/// A table-driven check of the header derivation, including the moderation
/// cases.
///
/// The table is the point: each row is a named profile fixture plus the header
/// fields it must produce, so a regression in any single derivation shows up as
/// one failing row rather than a diff somewhere downstream.
@Suite("Profile header derivation") struct ProfileHeaderDerivationTests {

  /// One row of the table.
  struct Row {
    let name: String
    let profile: App.Bsky.ActorDefs_ProfileViewDetailed
    let viewerDid: String?
    let hasSession: Bool
    let shadow: ProfileShadow?
    let expectIsMe: Bool
    let expectFollowState: FollowState
    let expectIsFollowedBy: Bool
    let expectIsMuted: Bool
    let expectIsMutedOnlyReposts: Bool
    let expectIsBlocked: Bool
    let expectIsBlockedBy: Bool
    let expectVariant: ProfileHeaderVariant
    let expectDescription: String?
    let expectFollowersLabel: String
  }

  static func table() -> [Row] {
    [
      Row(
        name: "own profile, no shadow",
        profile: makeProfile(viewer: nil),
        viewerDid: "did:plc:alice",
        hasSession: true,
        shadow: nil,
        expectIsMe: true,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "following",
        profile: makeProfile(viewer: makeViewerState(following: "at://did:plc:me/app.bsky.graph.follow/1")),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .following(uri: "at://did:plc:me/app.bsky.graph.follow/1"),
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "mutual follow",
        profile: makeProfile(viewer: makeViewerState(
          following: "at://did:plc:me/app.bsky.graph.follow/1",
          followedBy: "at://did:plc:alice/app.bsky.graph.follow/2")),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .following(uri: "at://did:plc:me/app.bsky.graph.follow/1"),
        expectIsFollowedBy: true,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "muted",
        profile: makeProfile(viewer: makeViewerState(muted: true)),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: true,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "muted reposts only",
        profile: makeProfile(viewer: makeViewerState(mutedOnlyReposts: true)),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: true,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "muted by list",
        profile: makeProfile(viewer: makeViewerState(mutedByList: true)),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: true,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "blocking",
        profile: makeProfile(viewer: makeViewerState(blocking: "at://did:plc:me/app.bsky.graph.block/1")),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: true,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "blocked by",
        profile: makeProfile(viewer: makeViewerState(blockedBy: true)),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: true,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "labeler profile",
        profile: makeProfile(labeler: true),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .labeler,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "signed out",
        profile: makeProfile(viewer: nil),
        viewerDid: nil,
        hasSession: false,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "empty description",
        profile: makeProfile(description: ""),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: nil,
        expectFollowersLabel: "100"),

      Row(
        name: "large follower count is formatted",
        profile: makeProfile(followersCount: 12345),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: nil,
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "12.3K"),

      Row(
        name: "shadow overrides an unfollowed server state",
        profile: makeProfile(viewer: nil),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: ProfileShadow(followingUri: .set("at://did:plc:me/app.bsky.graph.follow/9")),
        expectIsMe: false,
        expectFollowState: .following(uri: "at://did:plc:me/app.bsky.graph.follow/9"),
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "shadow clears a following server state",
        profile: makeProfile(viewer: makeViewerState(following: "at://did:plc:me/app.bsky.graph.follow/1")),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: ProfileShadow(followingUri: .cleared),
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "pending follow reads as pending",
        profile: makeProfile(viewer: nil),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: ProfileShadow(followingUri: .set(FollowState.pendingSentinel)),
        expectIsMe: false,
        expectFollowState: .pending,
        expectIsFollowedBy: false,
        expectIsMuted: false,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),

      Row(
        name: "shadow mute over a clear server state",
        profile: makeProfile(viewer: nil),
        viewerDid: "did:plc:me",
        hasSession: true,
        shadow: ProfileShadow(muted: .set(true)),
        expectIsMe: false,
        expectFollowState: .notFollowing,
        expectIsFollowedBy: false,
        expectIsMuted: true,
        expectIsMutedOnlyReposts: false,
        expectIsBlocked: false,
        expectIsBlockedBy: false,
        expectVariant: .standard,
        expectDescription: "Hello",
        expectFollowersLabel: "100"),
    ]
  }

  /// Every row of the table produces exactly the header fields named.
  @Test func headerDerivationTable() throws {
    for row in Self.table() {
      let data = ProfileHeaderViewData(
        profile: .detailed(row.profile),
        shadow: row.shadow,
        moderationOpts: makeModerationOpts(),
        viewerDid: row.viewerDid,
        hasSession: row.hasSession)
      #expect(data.isMe == row.expectIsMe, "\(row.name): isMe")
      #expect(data.followState == row.expectFollowState, "\(row.name): followState")
      #expect(data.isFollowedBy == row.expectIsFollowedBy, "\(row.name): isFollowedBy")
      #expect(data.isMuted == row.expectIsMuted, "\(row.name): isMuted")
      #expect(data.isMutedOnlyReposts == row.expectIsMutedOnlyReposts, "\(row.name): mutedOnlyReposts")
      #expect(data.isBlocked == row.expectIsBlocked, "\(row.name): isBlocked")
      #expect(data.isBlockedBy == row.expectIsBlockedBy, "\(row.name): isBlockedBy")
      #expect(data.variant == row.expectVariant, "\(row.name): variant")
      #expect(data.description == row.expectDescription, "\(row.name): description")
      #expect(data.followersCountLabel == row.expectFollowersLabel, "\(row.name): followers label")
    }
  }

  /// A basic (non-detailed) view has no counts, so the labels fall back to zero
  /// rather than crashing - which is what RN's `|| 0` achieves.
  @Test func basicProfileViewHasZeroCounts() {
    let data = ProfileHeaderViewData(
      profile: .basic(makeBasicProfile(did: "did:plc:alice")),
      moderationOpts: makeModerationOpts(),
      viewerDid: "did:plc:me",
      hasSession: true)
    #expect(data.followersCountLabel == "0")
    #expect(data.followsCountLabel == "0")
    #expect(data.postsCountLabel == "0")
    #expect(data.description == nil, "a basic view carries no description")
  }

  /// A shadow does not mutate the profile it was applied to.
  @Test func shadowApplicationIsNonMutating() {
    let profile = makeProfile(viewer: nil)
    let shadow = ProfileShadow(followingUri: .set("at://follow/1"), muted: .set(true))
    let view = ProfileView.detailed(profile)
    let effective = shadow.applied(to: view)
    #expect(effective.viewer?.muted == true)
    #expect(effective.viewer?.following?.rawValue == "at://follow/1")
    #expect(view.viewer?.muted == nil, "the original view must be untouched")
  }

  /// Shadow fields merge field-by-field, so a later update does not clear an
  /// earlier one.
  @Test func shadowMergingKeepsEarlierFields() {
    let first = ProfileShadow(followingUri: .set("at://follow/1"))
    let second = ProfileShadow(muted: .set(true))
    let merged = first.merging(second)
    #expect(merged.followingUri?.value == "at://follow/1")
    #expect(merged.muted?.value == true)
  }
}

/// The moderation cases of the header derivation.
@Suite("Profile header moderation") struct ProfileHeaderModerationTests {

  /// A profile with no labels and no viewer state produces a clean decision.
  @Test func cleanProfileIsUnblurred() {
    let data = ProfileHeaderViewData(
      profile: .detailed(makeProfile()),
      moderationOpts: makeModerationOpts(),
      viewerDid: "did:plc:me",
      hasSession: true)
    #expect(!data.moderation.blocked)
    #expect(!data.moderation.muted)
    #expect(data.moderation.causes.isEmpty)
    #expect(!data.blursHeader)
  }

  /// A block lands on the decision, which is what drives the blocked banner.
  @Test func blockingProfileProducesABlockCause() {
    let data = ProfileHeaderViewData(
      profile: .detailed(makeProfile(
        viewer: makeViewerState(blocking: "at://did:plc:me/app.bsky.graph.block/1"))),
      moderationOpts: makeModerationOpts(),
      viewerDid: "did:plc:me",
      hasSession: true)
    #expect(data.moderation.blocked)
    #expect(data.isBlocked)
  }

  /// A mute lands on the decision.
  @Test func mutingProfileProducesAMuteCause() {
    let data = ProfileHeaderViewData(
      profile: .detailed(makeProfile(viewer: makeViewerState(muted: true))),
      moderationOpts: makeModerationOpts(),
      viewerDid: "did:plc:me",
      hasSession: true)
    #expect(data.moderation.muted)
    #expect(data.isMuted)
  }

  /// A `!hide` label blurs the header, which is the flag the profile screen
  /// reads to decide whether to cover the content.
  ///
  /// `!hide` is used rather than `porn` because it is the global label whose
  /// definition carries a `profileView: .blur` behavior; `porn` blurs only the
  /// avatar and banner.
  @Test func hideLabelBlursTheHeader() {
    // The label's source labeler must be subscribed, or the engine skips it
    // (resolveLabeler drops labels from unconfigured labelers).
    let prefs = ModerationPrefs(
      labels: [:], labelers: [Moderation.LabelerPrefs(did: "did:plc:labeler")])
    let opts = ModerationOpts(userDid: "did:plc:me", prefs: prefs)
    let data = ProfileHeaderViewData(
      profile: .detailed(makeProfile(labels: [makeLabel("!hide")])),
      moderationOpts: opts,
      viewerDid: "did:plc:me",
      hasSession: true)
    #expect(data.blursHeader, "a !hide label must blur the header")
    #expect(!data.moderation.labelCauses.isEmpty)
  }

  /// An `ignore` preference leaves the header alone.
  @Test func ignoreLabelLeavesTheHeaderClear() {
    let prefs = ModerationPrefs(
      labels: ["!hide": .ignore], labelers: [Moderation.LabelerPrefs(did: "did:plc:labeler")])
    let opts = ModerationOpts(userDid: "did:plc:me", prefs: prefs)
    let data = ProfileHeaderViewData(
      profile: .detailed(makeProfile(labels: [makeLabel("!hide")])),
      moderationOpts: opts,
      viewerDid: "did:plc:me",
      hasSession: true)
    #expect(!data.blursHeader, "an ignored label must not blur")
    #expect(data.moderation.labelCauses.isEmpty)
  }

  /// A shadow mute reaches the moderation decision, because the decision is
  /// computed from the *effective* profile.
  @Test func shadowMuteReachesTheModerationDecision() {
    let data = ProfileHeaderViewData(
      profile: .detailed(makeProfile(viewer: nil)),
      shadow: ProfileShadow(muted: .set(true)),
      moderationOpts: makeModerationOpts(),
      viewerDid: "did:plc:me",
      hasSession: true)
    #expect(data.moderation.muted, "the shadow must be applied before moderating")
  }
}

/// Known-follower derivation.
@Suite("Known followers") struct KnownFollowersTests {
  private func known(_ count: Int, previews: Int) -> App.Bsky.ActorDefs_KnownFollowers {
    App.Bsky.ActorDefs_KnownFollowers(
      count: count,
      followers: (0..<previews).map { index in
        App.Bsky.ActorDefs_ProfileViewBasic(
          did: FormatString<DID>(rawValue: "did:plc:f\(index)"),
          handle: FormatString<Handle>(rawValue: "f\(index).example.com"))
      })
  }

  /// A non-empty preview list shows the line.
  @Test func nonEmptyListShows() {
    #expect(KnownFollowersLogic.shouldShow(known(3, previews: 3)))
  }

  /// A missing or empty list does not.
  @Test func emptyListHides() {
    #expect(!KnownFollowersLogic.shouldShow(nil))
    #expect(!KnownFollowersLogic.shouldShow(known(0, previews: 0)))
  }

  /// The header gate also excludes the viewer's own profile and blocked users.
  @Test func headerGateExcludesSelfAndBlocked() {
    let followers = known(2, previews: 2)
    #expect(KnownFollowersLogic.shouldShow(knownFollowers: followers, isMe: false, isBlocked: false))
    #expect(!KnownFollowersLogic.shouldShow(knownFollowers: followers, isMe: true, isBlocked: false))
    #expect(!KnownFollowersLogic.shouldShow(knownFollowers: followers, isMe: false, isBlocked: true))
  }

  /// The reported count is the lexicon's own total, not the preview count - the
  /// server sends up to five previews but a larger total.
  @Test func countUsesTheLexiconTotalNotThePreviewCount() {
    let followers = known(37, previews: 5)
    #expect(KnownFollowersLogic.count(followers) == 37)
    #expect(KnownFollowersLogic.previews(followers).count == 5)
  }
}
