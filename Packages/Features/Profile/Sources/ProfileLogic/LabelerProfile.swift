import Foundation
import Lexicons
import Preferences
import QueryStore
import SwiftAtproto

/// The number of labelers an account can subscribe to.
///
/// Port of `MAX_LABELERS` in `src/lib/constants.ts`.
public let maxLabelers = 20

/// Everything the labeler header variant needs.
///
/// Port of `ProfileHeaderLabeler` and `HeaderLabelerButtons` in
/// `src/screens/Profile/Header/ProfileHeaderLabeler.tsx`. The labeler branch is
/// entered when `profile.associated?.labeler` is set; it then needs the labeler
/// *service* view, which is a second request (`app.bsky.labeler.getServices`).
public struct LabelerProfileViewData: Sendable {
  /// The labeler service record, from `getServices` with `detailed: true`.
  public let labeler: App.Bsky.LabelerDefs_LabelerViewDetailed
  /// Whether the viewer is subscribed to this labeler.
  public let isSubscribed: Bool
  /// Whether the viewer has liked the labeler, and the like URI if so.
  public let likeURI: String?
  /// The labeler's like count.
  public let likeCount: Int
  /// Whether this labeler is one of the app's own labelers.
  public let isAppLabeler: Bool
  /// Whether the profile is the viewer's own.
  public let isMe: Bool
  /// Whether a session exists, which the like and subscribe buttons require.
  public let hasSession: Bool
  /// Whether the account is blocked or blocking, which hides the message button.
  public let isBlocked: Bool

  /// True when the like button should render, and be enabled.
  ///
  /// RN: `!isAppLabeler(profile.did)` gates the whole like block, and
  /// `!hasSession || isLikePending || isUnlikePending` disables the button.
  public var showsLikeButton: Bool { !isAppLabeler }

  /// True when the like button is interactive.
  public var canLike: Bool { showsLikeButton && hasSession }

  /// True when the subscribe button should render.
  ///
  /// RN hides it for the viewer's own profile, for app labelers (whose
  /// subscription is implied), and in the minimal header where the subscribed
  /// state is not shadowed.
  public var showsSubscribeButton: Bool { !isMe && !isAppLabeler }

  /// True when the message button should render.
  public var showsMessageButton: Bool { hasSession && !isMe && !isBlocked }

  /// True when the edit-profile button should render instead.
  public var showsEditProfileButton: Bool { isMe }

  /// The labeler's creator handle, which the liked-by route falls back to a DID
  /// for when the handle is absent.
  public var creatorIdentifier: String {
    let handle = labeler.creator.handle.rawValue
    return handle.isEmpty ? labeler.creator.did.rawValue : handle
  }
}

extension LabelerProfileViewData {
  /// Derives the labeler header data.
  ///
  /// - Parameters:
  ///   - labeler: the service view, or `nil` while it is loading - in which case
  ///     the caller should render the standard header instead.
  ///   - subscribedLabelerDIDs: the DIDs the viewer is subscribed to, i.e.
  ///     `preferences.moderationPrefs.labelers.map(\.did)`. Passed as a plain
  ///     list rather than the preferences value so this feature does not depend
  ///     on how preferences are stored.
  ///   - viewerDid: the signed-in account's DID, or `nil` when signed out.
  ///   - hasSession: whether a session exists.
  public init?(
    labeler: App.Bsky.LabelerDefs_LabelerViewDetailed?,
    subscribedLabelerDIDs: [String] = [],
    viewerDid: String?,
    hasSession: Bool
  ) {
    guard let labeler else { return nil }
    let labelerDid = labeler.creator.did.rawValue
    self.labeler = labeler
    self.isSubscribed = subscribedLabelerDIDs.contains(labelerDid)
    self.likeURI = labeler.viewer?.like?.rawValue
    self.likeCount = labeler.likeCount ?? 0
    self.isAppLabeler = LabelerSubscription.isAppLabeler(did: labelerDid)
    self.isMe = viewerDid != nil && labelerDid == viewerDid
    self.hasSession = hasSession
    self.isBlocked = labeler.creator.viewer?.blocking != nil
  }
}

/// Subscription rules for labelers.
///
/// Port of `isAppLabeler` / `isSubscribed` in `src/lib/moderation.ts` and the
/// validation inside `useLabelerSubscriptionMutation`.
public enum LabelerSubscription {
  /// The app's own moderation labeler DID.
  ///
  /// Kept in step with `Preferences.BlueskyModerationLabeler.did`; written out
  /// here because the `Preferences` module and the `Preferences` type share a
  /// name, so a qualified reference from this file would be ambiguous.
  public static let appModerationLabelerDID = "did:plc:ar7c4by46qjdydhdevvrndac"

  /// The DIDs of the app's own labelers.
  ///
  /// The RN app reads `Client.appLabelers`, a static on the lexicon client. The
  /// Swift port takes the one DID the preferences engine already registers
  /// (`BlueskyModerationLabeler`), and exposes the list so it can be extended
  /// without touching the call sites.
  public static let appLabelerDIDs: [String] = [BlueskyModerationLabeler.did]

  /// True when `did` is one of the app's labelers.
  public static func isAppLabeler(did: String) -> Bool { appLabelerDIDs.contains(did) }

  /// True when `dids` lists this labeler.
  public static func isSubscribed(did: String, subscribedLabelerDIDs: [String]) -> Bool {
    subscribedLabelerDIDs.contains(did)
  }
}

/// Why a subscription change was refused before a request was sent.
public enum LabelerSubscriptionError: Error, Sendable, Equatable {
  /// The viewer is already at ``maxLabelers``.
  ///
  /// RN signals this by throwing `new Error('MAX_LABELERS')` and the UI compares
  /// the message string; Swift throws a typed error carrying the count so the
  /// copy can be built without parsing.
  case tooManyLabelers(count: Int, limit: Int)
  /// The viewer is not signed in.
  case notSignedIn
}

/// A labeler that should be unsubscribed before another can be added.
public struct InvalidLabeler: Sendable, Equatable {
  /// The labeler's DID.
  public let did: String
  /// Why it is invalid.
  public let reason: Reason

  /// Why a subscribed labeler no longer counts.
  public enum Reason: String, Sendable, Equatable {
    /// The profile came back but is not a labeler service.
    case notALabeler
    /// No profile came back, so it may be deactivated or taken down.
    case unreachable
  }
}

/// The subscription bookkeeping `useLabelerSubscriptionMutation` performs.
///
/// The RN mutation does more than add or remove one labeler:
///
/// 1. It re-reads the profiles of every subscribed labeler.
/// 2. It removes any that are no longer valid labelers, so a stale subscription
///    does not occupy a slot.
/// 3. It re-checks `MAX_LABELERS` *after* that removal, which is why the count
///    is computed against the pruned list.
/// 4. Only then does it add or remove the target.
///
/// Steps 1-3 are pure once the profile list is supplied, so they live here and
/// the request sequence is left to the caller.
public enum LabelerSubscriptionPlanner {
  /// Finds subscribed labelers that are no longer valid.
  ///
  /// A subscribed DID that is missing from `profiles` is treated as unreachable
  /// (RN: "no response came back, might be deactivated or takedown"). A DID whose
  /// profile exists but carries no `associated.labeler` is treated as not a
  /// labeler (RN tests `exists.associated && !exists.associated.labeler`).
  public static func invalidLabelers(
    subscribed: [String],
    profiles: [App.Bsky.ActorDefs_ProfileViewDetailed]
  ) -> [InvalidLabeler] {
    var invalid: [InvalidLabeler] = []
    for did in subscribed where !LabelerSubscription.isAppLabeler(did: did) {
      guard let profile = profiles.first(where: { $0.did.rawValue == did }) else {
        invalid.append(InvalidLabeler(did: did, reason: .unreachable))
        continue
      }
      if profile.associated?.labeler != true {
        invalid.append(InvalidLabeler(did: did, reason: .notALabeler))
      }
    }
    return invalid
  }

  /// The count a subscription check runs against: current labelers, less the
  /// invalid ones that are about to be removed.
  public static func effectiveCount(subscribed: [String], invalid: [InvalidLabeler]) -> Int {
    subscribed.count - invalid.count
  }

  /// Validates adding `did` to the subscription list.
  ///
  /// - Throws: ``LabelerSubscriptionError/tooManyLabelers(count:limit:)`` when the
  ///   pruned count has already reached the limit.
  public static func validateAdd(
    did: String,
    subscribed: [String],
    invalid: [InvalidLabeler],
    limit: Int = maxLabelers
  ) throws {
    guard !subscribed.contains(did) else { return }
    let count = effectiveCount(subscribed: subscribed, invalid: invalid)
    guard count < limit else {
      throw LabelerSubscriptionError.tooManyLabelers(count: count, limit: limit)
    }
  }
}
