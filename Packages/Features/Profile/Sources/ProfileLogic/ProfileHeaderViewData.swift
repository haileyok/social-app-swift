import Domain
import Foundation
import Lexicons
import Moderation
import SwiftAtproto

/// The follow relationship a header should render, after any optimistic write.
///
/// RN stores this in a `ProfileShadow` as `followingUri`, where the sentinel
/// string `'pending'` means "a follow is in flight". Swift makes the three states
/// explicit rather than overloading the URI.
public enum FollowState: Sendable, Hashable {
  /// Not following.
  case notFollowing
  /// Following, with the follow record's AT URI.
  case following(uri: String)
  /// A follow or unfollow is in flight; the UI shows the target state.
  case pending

  /// The URI to render, `nil` while a request is pending.
  public var uri: String? {
    if case .following(let uri) = self { return uri }
    return nil
  }

  /// True when the viewer follows, or is optimistically shown as following.
  public var isFollowing: Bool { self != .notFollowing }

  /// Whether the row should be interactive. A pending follow is not.
  public var isPending: Bool { self == .pending }

  /// Reads the state out of a profile's viewer block, unless a shadow value
  /// overrides it.
  public init(viewer: App.Bsky.ActorDefs_ViewerState?, shadow: ProfileShadow?) {
    if let field = shadow?.followingUri, field.isSet {
      switch field {
      case .unset: self = Self.fromViewer(viewer)
      case .cleared: self = .notFollowing
      case .set(let uri): self = uri == Self.pendingSentinel ? .pending : .following(uri: uri)
      }
    } else {
      self = Self.fromViewer(viewer)
    }
  }

  /// The sentinel RN stores while a follow or unfollow is in flight.
  public static let pendingSentinel = "pending"

  private static func fromViewer(_ viewer: App.Bsky.ActorDefs_ViewerState?) -> FollowState {
    if let uri = viewer?.following?.rawValue {
      return .following(uri: uri)
    }
    return .notFollowing
  }
}

/// A field of a profile shadow: either explicitly absent, or set to a value.
///
/// RN distinguishes `'muted' in shadow` from `shadow.muted === undefined` when it
/// merges a shadow into a profile (`mergeShadow`), which is how a shadow can
/// *clear* a field rather than leave it alone. An optional cannot express that,
/// so this small enum does.
public enum ShadowField<Value: Sendable & Hashable>: Sendable, Hashable {
  /// The shadow says nothing about this field.
  case unset
  /// The shadow clears the field.
  case cleared
  /// The shadow sets the field.
  case set(Value)

  public var value: Value? {
    if case .set(let value) = self { return value }
    return nil
  }

  public var isSet: Bool { self != .unset }
}

/// One actor's shadow: local overrides that have not been refetched.
///
/// Port of the `ProfileShadow` interface in
/// `src/state/cache/profile-shadow.ts`. The RN version is a `WeakMap` keyed by
/// the profile object identity plus an event emitter; Swift keys by DID, which is
/// the identity the emitter actually used (`emitter.emit(did, value)`) and which
/// survives a refetch that produces a new object.
public struct ProfileShadow: Sendable, Hashable {
  public var followingUri: ShadowField<String>?
  public var muted: ShadowField<Bool>?
  public var mutedOnlyReposts: ShadowField<Bool>?
  public var blockingUri: ShadowField<String>?

  public init(
    followingUri: ShadowField<String>? = nil,
    muted: ShadowField<Bool>? = nil,
    mutedOnlyReposts: ShadowField<Bool>? = nil,
    blockingUri: ShadowField<String>? = nil
  ) {
    self.followingUri = followingUri
    self.muted = muted
    self.mutedOnlyReposts = mutedOnlyReposts
    self.blockingUri = blockingUri
  }

  /// Merges `other` over this shadow, field by field.
  ///
  /// RN's `updateProfileShadow` does `{...shadows.get(profile), ...value}`, so a
  /// field present in the new value wins and an absent one is left alone.
  public func merging(_ other: ProfileShadow) -> ProfileShadow {
    ProfileShadow(
      followingUri: other.followingUri ?? followingUri,
      muted: other.muted ?? muted,
      mutedOnlyReposts: other.mutedOnlyReposts ?? mutedOnlyReposts,
      blockingUri: other.blockingUri ?? blockingUri)
  }

  /// Applies this shadow to `profile`, producing the effective header input.
  ///
  /// Port of `mergeShadow`: `viewer.following` / `muted` / `mutedOnlyReposts` /
  /// `blocking` are overridden when the shadow carries them, and left as the
  /// server sent them otherwise. `blockingByList` is not shadowed, so a shadow
  /// that sets `blocking` replaces the list-derived block as well (the generated
  /// viewer state has no `blocking`-clearing counterpart).
  public func applied(to profile: ProfileView) -> ProfileView {
    let viewer = profile.viewer ?? App.Bsky.ActorDefs_ViewerState()
    let merged = App.Bsky.ActorDefs_ViewerState(
      activitySubscription: viewer.activitySubscription,
      blockedBy: viewer.blockedBy,
      blocking: overrideURI(blockingUri, viewer.blocking),
      blockingByList: viewer.blockingByList,
      followedBy: viewer.followedBy,
      following: overrideURI(followingUri, viewer.following),
      knownFollowers: viewer.knownFollowers,
      muted: override(muted, viewer.muted),
      mutedByList: viewer.mutedByList,
      mutedOnlyQuoteposts: viewer.mutedOnlyQuoteposts,
      mutedOnlyReposts: override(mutedOnlyReposts, viewer.mutedOnlyReposts))

    switch profile {
    case .detailed(var detailed):
      detailed.viewer = merged
      return .detailed(detailed)
    case .basic(var basic):
      basic.viewer = merged
      return .basic(basic)
    }
  }

  /// Overrides the generated viewer value with a shadow field.
  private func override<Value: Sendable & Hashable>(
    _ field: ShadowField<Value>?, _ current: Value?
  ) -> Value? {
    guard let field else { return current }
    switch field {
    case .unset: return current
    case .cleared: return nil
    case .set(let value): return value
    }
  }

  /// Overrides a `FormatString<ATURI>` viewer field from a plain shadow string.
  private func overrideURI(
    _ field: ShadowField<String>?, _ current: FormatString<ATURI>?
  ) -> FormatString<ATURI>? {
    guard let field else { return current }
    switch field {
    case .unset: return current
    case .cleared: return nil
    case .set(let uri): return FormatString<ATURI>(rawValue: uri)
    }
  }
}

/// Which header variant a profile screen renders.
public enum ProfileHeaderVariant: String, Sendable, Hashable, CaseIterable {
  /// `ProfileHeaderStandard`.
  case standard
  /// `ProfileHeaderLabeler` - used when `profile.associated?.labeler` is set.
  case labeler
}

/// Everything a profile header needs, derived once.
///
/// Port of the derivation `Profile.tsx` performs before it renders
/// (`isMe`, `hasLabeler`, the `moderateProfile` call, the description's
/// emptiness) plus the metrics `ProfileHeaderMetrics` formats.
public struct ProfileHeaderViewData: Sendable {
  /// The effective profile, with any shadow applied.
  public let profile: ProfileView
  /// The raw profile, before a shadow was applied.
  public let unshadowedProfile: ProfileView
  /// The moderation decision for this profile, for `profileView`-context UI.
  public let moderation: ModerationDecision
  /// Whether this profile is the signed-in account's own.
  public let isMe: Bool
  /// Whether the viewer has a session at all.
  public let hasSession: Bool
  /// Whether the viewer is the profile owner's follower (`viewer.followedBy`).
  public let isFollowedBy: Bool
  /// The follow relationship to render.
  public let followState: FollowState
  /// Whether the viewer muted this account (fully or reposts-only).
  public let isMuted: Bool
  /// Whether the mute covers reposts only.
  public let isMutedOnlyReposts: Bool
  /// Whether the viewer blocks, or is blocked by, this account.
  public let isBlocked: Bool
  /// Whether this account blocks the viewer. RN shows a banner for this.
  public let isBlockedBy: Bool
  /// The formatted follower count, e.g. `1.2K`.
  public let followersCountLabel: String
  /// The formatted following count.
  public let followsCountLabel: String
  /// The formatted post count.
  public let postsCountLabel: String
  /// The tab set, in render order.
  public let tabs: ProfileTabVisibility
  /// The header variant to render.
  public let variant: ProfileHeaderVariant
  /// The description, or `nil` when it is empty.
  ///
  /// RN computes `hasDescription = description !== ''` and passes `null` rather
  /// than an empty string, so `nil` here means "do not render a description
  /// block".
  public let description: String?
  /// Whether the profileView context should blur the header.
  public let blursHeader: Bool

  /// True when the header must wait for the rich-text description to resolve
  /// before it renders. RN: `isPlaceholderProfile || isResolvingDescriptionRT`.
  public var showsPlaceholder: Bool { false }
}

extension ProfileHeaderViewData {
  /// Derives the header data from a loaded profile.
  ///
  /// - Parameters:
  ///   - profile: the profile the server returned.
  ///   - shadow: local overrides for this DID, if any.
  ///   - moderationOpts: the viewer's moderation options.
  ///   - viewerDid: the signed-in account's DID, or `nil` when signed out.
  ///   - hasSession: whether a session exists.
  public init(
    profile: ProfileView,
    shadow: ProfileShadow? = nil,
    moderationOpts: ModerationOpts,
    viewerDid: String?,
    hasSession: Bool
  ) {
    let effective = shadow?.applied(to: profile) ?? profile
    let viewer = effective.viewer
    let moderation = moderateProfile(effective.moderationSubject, opts: moderationOpts)

    self.unshadowedProfile = profile
    self.profile = effective
    self.moderation = moderation
    self.isMe = viewerDid != nil && effective.did == viewerDid
    self.hasSession = hasSession
    self.isFollowedBy = viewer?.followedBy != nil
    self.followState = FollowState(viewer: viewer, shadow: shadow)
    self.isMuted = viewer?.muted == true || viewer?.mutedByList != nil
    self.isMutedOnlyReposts = viewer?.mutedOnlyReposts == true
    self.isBlocked = viewer?.blocking != nil || viewer?.blockingByList != nil
    self.isBlockedBy = viewer?.blockedBy == true
    self.followersCountLabel = FormatCount.formatCount(effective.followersCount ?? 0)
    self.followsCountLabel = FormatCount.formatCount(effective.followsCount ?? 0)
    self.postsCountLabel = FormatCount.formatCount(effective.postsCount ?? 0)
    self.tabs = ProfileTabVisibility(
      profile: effective.detailedProfile ?? Self.placeholderDetailed(effective),
      viewerDid: viewerDid,
      hasSession: hasSession)
    self.variant = effective.associated?.labeler == true ? .labeler : .standard
    let text = effective.descriptionText ?? ""
    self.description = text.isEmpty ? nil : text
    self.blursHeader = moderation.ui(.profileView).blur
  }

  /// A minimal detailed view carrying just the DID, for basic views.
  ///
  /// ``ProfileTabVisibility`` reads `associated`, which only a detailed view
  /// carries; a basic view therefore yields the signed-out shape, which is what
  /// RN gets too when it renders a list row rather than a profile screen.
  private static func placeholderDetailed(_ profile: ProfileView)
    -> App.Bsky.ActorDefs_ProfileViewDetailed
  {
    App.Bsky.ActorDefs_ProfileViewDetailed(
      did: FormatString<DID>(rawValue: profile.did),
      handle: FormatString<Handle>(rawValue: profile.handle),
      viewer: profile.viewer)
  }
}

extension ProfileView {
  /// `description`, from whichever shape carries it.
  public var descriptionText: String? {
    switch self {
    case .detailed(let profile): profile.description
    case .basic: nil
    }
  }
}

/// Known-followers derivation.
///
/// Port of `shouldShowKnownFollowers` in `src/components/KnownFollowers.tsx`:
/// `knownFollowers && knownFollowers.followers.length > 0`.
public enum KnownFollowersLogic {
  /// True when the header should render the "Followed by ..." line.
  ///
  /// RN additionally requires `!isMe && !isBlockedUser` at the call site in
  /// `ProfileHeaderStandard.tsx`; that gate is exposed separately as
  /// ``shouldShow(knownFollowers:isMe:isBlocked:)``.
  public static func shouldShow(_ knownFollowers: App.Bsky.ActorDefs_KnownFollowers?)
    -> Bool
  {
    guard let knownFollowers else { return false }
    return !knownFollowers.followers.isEmpty
  }

  /// The full gate: a non-empty known-followers list, not the viewer's own
  /// profile, and not a blocked user.
  public static func shouldShow(
    knownFollowers: App.Bsky.ActorDefs_KnownFollowers?,
    isMe: Bool,
    isBlocked: Bool
  ) -> Bool {
    !isMe && !isBlocked && shouldShow(knownFollowers)
  }

  /// The follower previews to render, in order. The lexicon caps these at five.
  public static func previews(_ knownFollowers: App.Bsky.ActorDefs_KnownFollowers?)
    -> [App.Bsky.ActorDefs_ProfileViewBasic]
  {
    knownFollowers?.followers ?? []
  }

  /// The count the label reports.
  ///
  /// This is the lexicon's own `count` field, not `followers.count`: the server
  /// sends up to five previews but a total that can be larger, and the label is
  /// built from the total.
  public static func count(_ knownFollowers: App.Bsky.ActorDefs_KnownFollowers?) -> Int {
    knownFollowers?.count ?? 0
  }
}
