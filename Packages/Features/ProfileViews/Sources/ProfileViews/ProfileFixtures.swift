import Domain
import Foundation
import Lexicons
import Moderation
import ProfileLogic
import SwiftAtproto
import UIComponentsCore

/// Fixture profiles for previews, the fixture capture surface, and the app hook.
///
/// These build the real lexicon types (rather than a stand-in), so a fixture
/// flows through ``ProfileHeaderViewData``, the moderation engine, and the views
/// exactly as a server response would. Everything here is deterministic: no
/// network, no clock, no random.
public enum ProfileFixtures {
  /// A fixture profile, with only the fields a caller cares about set.
  public static func profile(
    did: String = "did:plc:alice",
    handle: String = "alice.bsky.social",
    displayName: String? = "Alice",
    description: String? = "Building things on the open social web.",
    avatar: String? = nil,
    banner: String? = nil,
    followersCount: Int? = 12_400,
    followsCount: Int? = 348,
    postsCount: Int? = 1_204,
    viewer: App.Bsky.ActorDefs_ViewerState? = nil,
    labeler: Bool? = nil,
    feedgens: Int? = nil,
    starterPacks: Int? = nil,
    lists: Int? = nil
  ) -> App.Bsky.ActorDefs_ProfileViewDetailed {
    App.Bsky.ActorDefs_ProfileViewDetailed(
      associated: App.Bsky.ActorDefs_ProfileAssociated(
        feedgens: feedgens, labeler: labeler, lists: lists, starterPacks: starterPacks),
      avatar: avatar.map { FormatString<URI>(rawValue: $0) },
      banner: banner.map { FormatString<URI>(rawValue: $0) },
      description: description,
      did: FormatString<DID>(rawValue: did),
      displayName: displayName,
      followersCount: followersCount,
      followsCount: followsCount,
      handle: FormatString<Handle>(rawValue: handle),
      postsCount: postsCount,
      viewer: viewer)
  }

  /// A minimal profile view, as the list queries return.
  public static func basic(
    did: String,
    handle: String? = nil,
    displayName: String? = "Someone"
  ) -> ProfileView {
    .basic(
      App.Bsky.ActorDefs_ProfileView(
        did: FormatString<DID>(rawValue: did),
        displayName: displayName,
        handle: FormatString<Handle>(rawValue: handle ?? "\(did.suffix(6)).bsky.social")))
  }

  /// A viewer state with the fields the header reads.
  public static func viewer(
    following: String? = nil,
    followedBy: String? = nil,
    muted: Bool? = nil,
    mutedOnlyReposts: Bool? = nil,
    blocking: String? = nil,
    blockedBy: Bool? = nil,
    knownFollowers: App.Bsky.ActorDefs_KnownFollowers? = nil
  ) -> App.Bsky.ActorDefs_ViewerState {
    App.Bsky.ActorDefs_ViewerState(
      blockedBy: blockedBy,
      blocking: blocking.map { FormatString<ATURI>(rawValue: $0) },
      followedBy: followedBy.map { FormatString<ATURI>(rawValue: $0) },
      following: following.map { FormatString<ATURI>(rawValue: $0) },
      knownFollowers: knownFollowers,
      muted: muted,
      mutedOnlyReposts: mutedOnlyReposts)
  }

  /// A known-followers block, as the profile view carries it.
  public static func knownFollowers(
    count: Int = 4,
    previews: [App.Bsky.ActorDefs_ProfileViewBasic] = []
  ) -> App.Bsky.ActorDefs_KnownFollowers {
    App.Bsky.ActorDefs_KnownFollowers(
      count: count,
      followers: previews.isEmpty ? [knownFollower("bob"), knownFollower("carol")] : previews)
  }

  private static func knownFollower(_ name: String)
    -> App.Bsky.ActorDefs_ProfileViewBasic {
    App.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<DID>(rawValue: "did:plc:\(name)"),
      displayName: name.capitalized,
      handle: FormatString<Handle>(rawValue: "\(name).bsky.social"))
  }

  /// Moderation options with an empty preference set, for fixture renders.
  public static func moderationOpts(userDid: String = "did:plc:me") -> ModerationOpts {
    ModerationOpts(userDid: userDid, prefs: ModerationPrefs())
  }
}

extension ProfileFixtures {
  /// The header data for a fixture profile, with no shadow and a signed-in viewer.
  public static func headerData(
    profile: App.Bsky.ActorDefs_ProfileViewDetailed,
    viewerDid: String = "did:plc:me",
    shadow: ProfileShadow? = nil
  ) -> ProfileHeaderViewData {
    ProfileHeaderViewData(
      profile: .detailed(profile),
      shadow: shadow,
      moderationOpts: moderationOpts(userDid: viewerDid),
      viewerDid: viewerDid,
      hasSession: true)
  }

  /// A header for the signed-in account's own profile.
  public static func ownProfileHeaderData(
    profile: App.Bsky.ActorDefs_ProfileViewDetailed = profile(
      did: "did:plc:me", handle: "me.bsky.social", displayName: "Me")
  ) -> ProfileHeaderViewData {
    headerData(profile: profile, viewerDid: profile.did.rawValue)
  }

  /// A header showing the "Follow" button.
  public static func notFollowingHeaderData() -> ProfileHeaderViewData {
    headerData(profile: profile(viewer: viewer()))
  }

  /// A header showing the "Following" button.
  public static func followingHeaderData() -> ProfileHeaderViewData {
    headerData(
      profile: profile(viewer: viewer(following: "at://did:plc:me/app.bsky.graph.follow/1")))
  }

  /// A header mid-follow: the button shows the target state and is disabled.
  public static func pendingFollowHeaderData() -> ProfileHeaderViewData {
    headerData(
      profile: profile(),
      shadow: ProfileShadow(followingUri: .set(FollowState.pendingSentinel)))
  }

  /// A header for an account that blocks the viewer.
  public static func blockedByHeaderData() -> ProfileHeaderViewData {
    headerData(profile: profile(viewer: viewer(blockedBy: true)))
  }

  /// A labeler profile, with the data its header variant needs.
  public static func labelerProfile() -> (
    profile: App.Bsky.ActorDefs_ProfileViewDetailed, labeler: LabelerProfileViewData
  ) {
    let labeler = App.Bsky.ActorDefs_ProfileViewDetailed(
      associated: App.Bsky.ActorDefs_ProfileAssociated(
        feedgens: 2, labeler: true, lists: 1, starterPacks: 0),
      description: "A moderation labeler service.",
      did: FormatString<DID>(rawValue: "did:plc:labeler"),
      displayName: "Skywatch",
      followersCount: 5_000,
      followsCount: 3,
      handle: FormatString<Handle>(rawValue: "skywatch.bsky.social"))
    let detail = App.Bsky.LabelerDefs_LabelerViewDetailed(
      cid: FormatString<LexLink>(rawValue: "bafyreifakelabelercid000000000000000000000000000000000"),
      creator: App.Bsky.ActorDefs_ProfileView(
        did: FormatString<DID>(rawValue: "did:plc:labeler"),
        handle: FormatString<Handle>(rawValue: "skywatch.bsky.social")),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      likeCount: 42,
      policies: App.Bsky.LabelerDefs_LabelerPolicies(labelValues: []),
      uri: FormatString<ATURI>(rawValue: "at://did:plc:labeler/app.bsky.labeler.service/self"),
      viewer: App.Bsky.LabelerDefs_LabelerViewerState())
    let data = LabelerProfileViewData(
      labeler: detail,
      subscribedLabelerDIDs: [],
      viewerDid: "did:plc:me",
      hasSession: true)!
    return (labeler, data)
  }
}
