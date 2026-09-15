import DesignSystem
import DesignTokens
import Lexicons
import StarterPacksLogic
import SwiftUI
import UIComponents

/**
 The logged-out landing screen for a starter pack.

 Ported from `screens/StarterPack/StarterPackLandingScreen.tsx`. The screen is
 the signed-out entry point: it previews the people the viewer would follow and
 offers the join action, which on this platform continues into sign-up. All of
 the derivation (validity, the capped and labeler-filtered sample, the
 follow-count copy) is ``StarterPackViewBuilder/landingState(_:)``'s.
 */
public struct StarterPackLandingView: View {
  private let state: StarterPackLandingState
  private let descriptionLoading: Bool
  private let onJoin: () -> Void
  private let onOpenCreator: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  /// Creates the landing screen.
  ///
  /// - Parameters:
  ///   - state: the derived landing state.
  ///   - descriptionLoading: whether the description is still resolving, which
  ///     the screen shows as a placeholder rather than an empty line.
  ///   - onJoin: continues into sign-up.
  ///   - onOpenCreator: opens the creator's profile, when the host can route.
  public init(
    state: StarterPackLandingState,
    descriptionLoading: Bool = false,
    onJoin: @escaping () -> Void = {},
    onOpenCreator: (() -> Void)? = nil
  ) {
    self.state = state
    self.descriptionLoading = descriptionLoading
    self.onJoin = onJoin
    self.onOpenCreator = onOpenCreator
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        creatorLine

        VStack(alignment: .leading, spacing: Spacing.sm) {
          AlfText(state.name, scale: .xxl, weight: Scales.FontWeight.bold)
            .fixedSize(horizontal: false, vertical: true)
          if descriptionLoading {
            RoundedRectangle(cornerRadius: Radius.xs)
              .fill(theme.atomColors.bgContrast100)
              .frame(height: 16)
              .frame(maxWidth: 240)
              .accessibilityLabel("Loading description")
          } else if let description = state.description, !description.isEmpty {
            AlfText(description, scale: .sm)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        memberPreview

        followCopy

        AlfButton(
          StarterPackCopy.landingJoinAction, color: .primary, size: .large, shape: .rectangular
        ) {
          onJoin()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(StarterPackAccessibility.landingJoinButton)
      }
      .padding(Spacing.lg)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(StarterPackAccessibility.landingScreen)
  }

  private var creatorLine: some View {
    HStack(spacing: Spacing.sm) {
      Avatar(avatar: nil, handle: state.creatorHandle, displayName: nil, size: .md)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(StarterPackCopy.landingBy, scale: .xs, color: theme.atomColors.textContrastMedium)
        AlfText("@\(state.creatorHandle)", scale: .sm, weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      if let onOpenCreator {
        Button(action: onOpenCreator) {
          AlfButtonText("View")
        }
        .buttonStyle(.alf(color: .secondary, size: .tiny))
      }
    }
  }

  /// The people the viewer would follow. ``StarterPackViewBuilder/landingSample(_:)``
  /// has already dropped labeler accounts and capped the list at eight.
  @ViewBuilder private var memberPreview: some View {
    if state.sample.isEmpty {
      EmptyStateView(
        icon: "person.2",
        title: StarterPackCopy.membersEmptyTitle,
        message: StarterPackCopy.membersEmptyMessage)
        .frame(minHeight: 180)
    } else {
      StarterPackMemberCollection(members: state.sample, layout: .grid)
    }
  }

  private var followCopy: some View {
    AlfText(followCopyText, scale: .sm, weight: Scales.FontWeight.semiBold)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// The sentence ``LandingFollowCopy`` selects.
  private var followCopyText: String {
    switch state.followCopy {
    case .allOfThem: StarterPackCopy.landingFollowAll
    case .someRemainder(let count): StarterPackCopy.landingFollowRemainder(count: count)
    }
  }
}

/// The pack detail and its landing presentation in one screen, for a host that
/// routes both from the same entry point.
///
/// A pack the viewer can manage (their own) opens as the detail screen; anyone
/// else's opens as the landing preview, which is the split RN's two screens
/// make.
public struct StarterPackDetailRouter: View {
  private let detail: StarterPackDetail
  private let landingState: StarterPackLandingState?
  private let members: [Lexicons.App.Bsky.GraphDefs_ListItemView]
  private let onJoin: () -> Void
  private let onEdit: () -> Void
  private let onShare: () -> Void

  public init(
    detail: StarterPackDetail,
    landingState: StarterPackLandingState?,
    members: [Lexicons.App.Bsky.GraphDefs_ListItemView] = [],
    onJoin: @escaping () -> Void = {},
    onEdit: @escaping () -> Void = {},
    onShare: @escaping () -> Void = {}
  ) {
    self.detail = detail
    self.landingState = landingState
    self.members = members
    self.onJoin = onJoin
    self.onEdit = onEdit
    self.onShare = onShare
  }

  public var body: some View {
    if !detail.isOwn, let landingState {
      StarterPackLandingView(state: landingState, onJoin: onJoin)
    } else {
      StarterPackScreen(
        detail: detail,
        members: members,
        shareData: StarterPackShare.shareData(detail),
        onJoin: onJoin,
        onShare: onShare,
        onEdit: onEdit)
    }
  }
}
