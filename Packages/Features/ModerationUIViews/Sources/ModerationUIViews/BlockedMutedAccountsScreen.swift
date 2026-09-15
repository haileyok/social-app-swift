import ATProtoClient
import DesignSystem
import DesignTokens
import Lexicons
import ModerationUILogic
import SwiftUI
import UIComponents

/// Which of the two account lists a screen instance is showing.
///
/// The two lists are the same surface with different copy and a different
/// verb, so they share one implementation rather than two near-identical files.
/// The distinction that actually matters - block records live in the viewer's
/// repo while mutes are an appview procedure - is already encoded in
/// ``BlockedMutedRemoval``.
public enum AccountListKind: String, Sendable, Hashable, CaseIterable {
  case blocked
  case muted

  /// The screen title.
  public var title: String {
    switch self {
    case .blocked: return ModerationCopy.blockedAccountsTitle
    case .muted: return ModerationCopy.mutedAccountsTitle
    }
  }

  /// The line under the title.
  public var description: String {
    switch self {
    case .blocked: return ModerationCopy.blockedAccountsDescription
    case .muted: return ModerationCopy.mutedAccountsDescription
    }
  }

  /// The empty-state title.
  public var emptyTitle: String {
    switch self {
    case .blocked: return ModerationCopy.blockedAccountsEmptyTitle
    case .muted: return ModerationCopy.mutedAccountsEmptyTitle
    }
  }

  /// The empty-state message.
  public var emptyMessage: String {
    switch self {
    case .blocked: return ModerationCopy.blockedAccountsEmptyMessage
    case .muted: return ModerationCopy.mutedAccountsEmptyMessage
    }
  }

  /// The action that removes an entry.
  public var removalAction: String {
    switch self {
    case .blocked: return ModerationCopy.unblockAction
    case .muted: return ModerationCopy.unmuteAction
    }
  }

  /// The accessibility identifier for the screen.
  public var screenIdentifier: String {
    switch self {
    case .blocked: return ModerationAccessibility.blockedAccountsScreen
    case .muted: return ModerationAccessibility.mutedAccountsScreen
    }
  }
}

/// The viewer's blocked or muted accounts, with the action that removes each.
///
/// A paginated list of profile rows. The rows come from the caller (which owns
/// the ``BlockedAccountsQuery`` / ``MutedAccountsQuery``); this view shows them,
/// offers the removal, and asks for the next page when the last row appears.
///
/// Ported from `screens/Moderation/BlockedAccounts.tsx` and
/// `screens/Moderation/MutedAccounts.tsx`.
public struct BlockedMutedAccountsScreen: View {
  private let kind: AccountListKind
  private let items: [ModerationProfileView]
  private let isLoading: Bool
  private let isLoadingMore: Bool
  private let hasMore: Bool
  private let errorMessage: String?
  private let onRemove: (ModerationProfileView) -> Void
  private let onLoadMore: () -> Void
  private let onRetry: () -> Void

  /// Creates the list screen.
  ///
  /// - Parameters:
  ///   - kind: which list this is.
  ///   - items: the profiles to show, in page order.
  ///   - isLoading: true while the first page is in flight.
  ///   - isLoadingMore: true while a later page is in flight.
  ///   - hasMore: whether another page exists.
  ///   - errorMessage: a failure to surface in place of the list.
  ///   - onRemove: the unblock/unmute request for one row.
  ///   - onLoadMore: asked for when the last row appears.
  ///   - onRetry: asked for after a failure.
  public init(
    kind: AccountListKind,
    items: [ModerationProfileView] = [],
    isLoading: Bool = false,
    isLoadingMore: Bool = false,
    hasMore: Bool = false,
    errorMessage: String? = nil,
    onRemove: @escaping (ModerationProfileView) -> Void = { _ in },
    onLoadMore: @escaping () -> Void = {},
    onRetry: @escaping () -> Void = {}
  ) {
    self.kind = kind
    self.items = items
    self.isLoading = isLoading
    self.isLoadingMore = isLoadingMore
    self.hasMore = hasMore
    self.errorMessage = errorMessage
    self.onRemove = onRemove
    self.onLoadMore = onLoadMore
    self.onRetry = onRetry
  }

  @Environment(\.alfTheme) private var theme

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        header

        if let errorMessage, items.isEmpty {
          ErrorStateView(
            title: "Something went wrong",
            message: errorMessage,
            retry: onRetry)
        } else if isLoading && items.isEmpty {
          ListSkeleton()
        } else if items.isEmpty {
          EmptyStateView(
            icon: kind == .blocked ? "hand.raised" : "speaker.slash",
            title: kind.emptyTitle,
            message: kind.emptyMessage)
        } else {
          list
        }
      }
      .padding(.xl)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(kind.screenIdentifier)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(kind.title, scale: .xxl, weight: Scales.FontWeight.bold)
      AlfText(kind.description, scale: .sm, color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var list: some View {
    VStack(spacing: 0) {
      // Identity is expressed as a closure rather than a chained key path
      // (`\.did.rawValue`): a two-hop key path through `FormatString<DID>` is not
      // inferable from the `ForEach` element type here.
      ForEach(items, id: { $0.did.rawValue }) { profile in
        accountRow(profile)
        ModerationDivider()
      }

      if isLoadingMore {
        LoadMoreSpinner()
      } else if hasMore {
        // A zero-height sentinel: the spinner only appears once a page is
        // actually in flight, so the list does not reserve space for it.
        Color.clear
          .frame(height: 1)
          .onAppear(perform: onLoadMore)
      }

      if let errorMessage {
        RetryRow(message: errorMessage, retry: onRetry)
      }
    }
  }

  private func accountRow(_ profile: ModerationProfileView) -> some View {
    let did = profile.did.rawValue
    return ModerationRow(title: profile.displayName ?? profile.handle.rawValue, subtitle: "@\(profile.handle.rawValue)") {
      Button(kind.removalAction) { onRemove(profile) }
        .buttonStyle(.alf(color: .secondary, size: .small, shape: .default))
        .accessibilityLabel("\(kind.removalAction) @\(profile.handle.rawValue)")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(ModerationAccessibility.accountRow(did))
  }
}

#Preview {
  BlockedMutedAccountsScreen(
    kind: AccountListKind.blocked, items: ModerationFixtures.profileViews(), hasMore: true)
}
