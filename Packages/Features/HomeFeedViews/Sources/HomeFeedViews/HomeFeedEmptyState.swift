import DesignSystem
import DesignSystemCore
import SwiftUI
import UIComponents

/// The Home feed's empty surfaces.
///
/// RN has one empty state per reason - `FollowingEmptyState`,
/// `CustomFeedEmptyState`, `NoFeedsPinned` and the logged-out view - because
/// each offers different actions. This view keeps one type with a reason, so the
/// copy and the action stay together and the screen is a single switch.
public struct HomeFeedEmptyState: View {
  /// Why the feed is empty.
  public enum Reason: Equatable, Sendable {
    /// A session, but every saved feed is unpinned. RN's `NoFeedsPinned`.
    case noFeedsPinned
    /// The following timeline, which is empty until the account follows someone.
    case following
    /// A feed generator or list that returned nothing.
    case emptyFeed
    /// No session.
    case loggedOut
  }

  private let reason: Reason
  private let actionLabel: String?
  private let action: (() -> Void)?

  public init(
    reason: Reason,
    actionLabel: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.reason = reason
    self.actionLabel = actionLabel
    self.action = action
  }

  public var body: some View {
    EmptyStateView(
      icon: icon,
      title: title,
      message: message,
      actionLabel: actionLabel ?? defaultActionLabel,
      action: action)
  }

  /// The empty state's icon, mirroring the RN empty states' iconography.
  private var icon: String {
    switch reason {
    case .noFeedsPinned: return "square.stack"
    case .following: return "person.2"
    case .emptyFeed: return "list.bullet"
    case .loggedOut: return "person.crop.circle"
    }
  }

  private var title: String {
    switch reason {
    case .noFeedsPinned: return HomeFeedStrings.noFeedsTitle
    case .following: return HomeFeedStrings.emptyFollowingTitle
    case .emptyFeed: return HomeFeedStrings.emptyFeedTitle
    case .loggedOut: return HomeFeedStrings.loggedOutTitle
    }
  }

  private var message: String {
    switch reason {
    case .noFeedsPinned: return HomeFeedStrings.noFeedsMessage
    case .following: return HomeFeedStrings.emptyFollowingMessage
    case .emptyFeed: return HomeFeedStrings.emptyFeedMessage
    case .loggedOut: return HomeFeedStrings.loggedOutMessage
    }
  }

  /// The action a reason suggests when the caller did not name one.
  private var defaultActionLabel: String? {
    switch reason {
    case .noFeedsPinned: return HomeFeedStrings.noFeedsAction
    case .loggedOut: return HomeFeedStrings.loggedOutAction
    case .following, .emptyFeed: return HomeFeedStrings.emptyRefreshAction
    }
  }
}

#Preview {
  VStack(spacing: Spacing.xl) {
    HomeFeedEmptyState(reason: .following)
    HomeFeedEmptyState(reason: .noFeedsPinned)
  }
  .theme(ThemePreference.light)
}
