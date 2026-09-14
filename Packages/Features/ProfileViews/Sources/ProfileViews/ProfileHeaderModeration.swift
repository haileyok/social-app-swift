import Moderation
import SwiftUI
import UIComponentsCore

/// Projects `ProfileHeaderViewData`'s moderation decision onto the header's
/// masked surfaces.
///
/// `ProfileHeaderViewData` already carries the `ModerationDecision`; this maps it
/// onto the four surfaces the RN header masks (`profileView`, `avatar`,
/// `displayName`, `banner`) using the same `moderationSurface` projection
/// `PostFeedItem` uses, so a profile and a post blur for the same reasons.
public struct ProfileHeaderModeration: Sendable {
  /// The header as a whole. Drives the description's blur and the reveal state.
  public let profileView: ModerationSurface
  /// The avatar.
  public let avatar: ModerationSurface
  /// The display name.
  public let displayName: ModerationSurface
  /// The banner.
  public let banner: ModerationSurface

  public init(
    profileView: ModerationSurface = .none,
    avatar: ModerationSurface = .none,
    displayName: ModerationSurface = .none,
    banner: ModerationSurface = .none
  ) {
    self.profileView = profileView
    self.avatar = avatar
    self.displayName = displayName
    self.banner = banner
  }

  /// Derives the four surfaces from a decision.
  ///
  /// `profileList` is not projected: the RN profile screen uses `profileView`
  /// for the header and `profileList` only in list rows, which
  /// `ProfileListRow` computes for itself.
  public init(decision: ModerationDecision, isOverridden: Bool = false) {
    self.profileView = moderationSurface(
      decision.ui(.profileView), isOverridden: isOverridden)
    self.avatar = moderationSurface(decision.ui(.avatar), isOverridden: isOverridden)
    self.displayName = moderationSurface(
      decision.ui(.displayName), isOverridden: isOverridden)
    self.banner = moderationSurface(decision.ui(.banner), isOverridden: isOverridden)
  }

  /// True when the whole header (rather than a single surface) is blurred, which
  /// is what the reveal affordance keys off.
  public var blursHeader: Bool {
    if case .blur = profileView { return true }
    return false
  }
}
