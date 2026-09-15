import DesignTokens
import ProfileLogic
import UIComponentsCore

/// The follow-button variants a profile header can render.
///
/// Derived from ``FollowState`` plus the viewer's relationship, matching the RN
/// `HeaderStandardButtons`: a pending write disables the button and shows the
/// target state, and `followedBy` is only ever conveyed by the known-followers
/// line rather than by a badge on the button.
public enum ProfileFollowButtonState: Sendable, Equatable {
  /// The viewer may follow.
  case follow
  /// The viewer follows; the button unfollows.
  case following
  /// A follow or unfollow is in flight; the button shows the target state and
  /// is not interactive.
  case pendingFollowing
  /// A pending unfollow.
  case pendingUnfollow

  /// Derives the state from the header's follow state.
  public init(followState: FollowState) {
    switch followState {
    case .notFollowing: self = .follow
    case .following: self = .following
    case .pending: self = .pendingFollowing
    }
  }

  /// The label the button renders.
  public func label(using strings: any ProfileStrings) -> String {
    switch self {
    case .follow, .pendingUnfollow: strings.follow
    case .following, .pendingFollowing: strings.following
    }
  }

  /// The ALF colour the button uses. Following is the subtle variant so the
  /// destructive unfollow does not read as the primary action.
  public var color: ButtonColor {
    switch self {
    case .follow, .pendingUnfollow: .primary
    case .following, .pendingFollowing: .primarySubtle
    }
  }

  /// Whether the button accepts interaction.
  public var isEnabled: Bool {
    self == .follow || self == .following
  }
}
