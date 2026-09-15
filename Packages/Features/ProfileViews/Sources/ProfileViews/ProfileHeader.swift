import DesignSystem
import DesignTokens
import Lexicons
import Moderation
import ProfileLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// What a tap in the header asked for.
///
/// The header does not navigate or mutate anything itself: it derives its state
/// from ``ProfileHeaderViewData`` and reports intent, so the same header serves
/// the fixture surface and a live screen.
public enum ProfileHeaderAction: Sendable, Equatable {
  /// Follow the profile.
  case follow
  /// Unfollow the profile.
  case unfollow
  /// Open the edit-profile sheet.
  case editProfile
  /// Open the followers list.
  case showFollowers
  /// Open the follows list.
  case showFollows
  /// Open the known-followers list.
  case showKnownFollowers
  /// Reveal the header behind its moderation blur.
  case showAnyway
  /// Reload the current tab after a failure.
  case reload
  /// Toggle the viewer's subscription to a labeler.
  case toggleLabelerSubscription(subscribed: Bool)
  /// Toggle the viewer's like on a labeler.
  case toggleLabelerLike(liked: Bool)
}

/// The profile header: banner, avatar, identity, metrics, description, and the
/// action row.
///
/// Port of `ProfileHeaderStandard` and `ProfileHeaderLabeler`. The variant is
/// taken from ``ProfileHeaderViewData/variant``, which itself comes from
/// `profile.associated.labeler`; the labeler branch renders the subscribe/like
/// buttons instead of the follow button and is fed by ``LabelerProfileViewData``.
///
/// ```swift
/// ProfileHeader(data: headerData) { action in handle(action) }
/// ```
public struct ProfileHeader: View {
  private let data: ProfileHeaderViewData
  private let labeler: LabelerProfileViewData?
  private let strings: any ProfileStrings
  private let onAction: (ProfileHeaderAction) -> Void

  @Environment(\.alfTheme) private var theme

  /// The moderation projection. Derived here so callers do not repeat it.
  private var moderation: ProfileHeaderModeration {
    ProfileHeaderModeration(decision: data.moderation)
  }

  public init(
    data: ProfileHeaderViewData,
    labeler: LabelerProfileViewData? = nil,
    strings: any ProfileStrings = defaultProfileStrings,
    onAction: @escaping (ProfileHeaderAction) -> Void = { _ in }
  ) {
    self.data = data
    self.labeler = labeler
    self.strings = strings
    self.onAction = onAction
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      ProfileHeaderBanner(
        profile: data.profile,
        moderation: moderation,
        isMe: data.isMe)
      identity
      if data.isBlockedBy {
        blockedByNotice
      } else {
        metricsAndDescription
      }
      actions
    }
    .padding(.bottom, Spacing.md)
    // A blurred profileView hides the description and fires the reveal, which is
    // the RN behaviour: the header chrome stays visible so the viewer can decide.
    .overlay(alignment: .top) {
      if moderation.blursHeader {
        revealBanner
      }
    }
  }

  // MARK: - Identity

  private var identity: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      ModerationMask(surface: moderation.displayName) {
        Text(data.profile.displayName ?? "@\(data.profile.handle)")
          .font(TypeScale.xl.font(weight: Scales.FontWeight.bold))
          .foregroundStyle(theme.atomColors.text)
          .lineLimit(2)
      }
      Text("@\(data.profile.handle)")
        .font(TypeScale.md.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
    }
    .padding(.horizontal, Spacing.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Metrics and description

  private var metricsAndDescription: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      ProfileHeaderMetrics(data: data, strings: strings) { metric in
        switch metric {
        case .followers: onAction(.showFollowers)
        case .follows: onAction(.showFollows)
        case .posts: break
        }
      }
      if let description = data.description, !moderation.blursHeader {
        Text(description)
          .font(TypeScale.md.font())
          .foregroundStyle(theme.atomColors.text)
          .lineLimit(15)
          .padding(.horizontal, Spacing.lg)
      }
      if showsKnownFollowers, let knownFollowers = data.profile.viewer?.knownFollowers {
        KnownFollowersLine(knownFollowers: knownFollowers, strings: strings) {
          onAction(.showKnownFollowers)
        }
        .padding(.horizontal, Spacing.lg)
      }
    }
  }

  /// The known-followers gate: a non-empty list, not the viewer's own profile,
  /// and not a blocked account.
  private var showsKnownFollowers: Bool {
    KnownFollowersLogic.shouldShow(
      knownFollowers: data.profile.viewer?.knownFollowers,
      isMe: data.isMe,
      isBlocked: data.isBlocked)
  }

  // MARK: - Blocked-by notice

  private var blockedByNotice: some View {
    Text(strings.blockedByNotice)
      .font(TypeScale.sm.font())
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Spacing.lg)
  }

  // MARK: - Actions

  @ViewBuilder
  private var actions: some View {
    if data.variant == .labeler, let labeler {
      LabelerHeaderActions(labeler: labeler, strings: strings, onAction: onAction)
        .padding(.horizontal, Spacing.lg)
    } else if data.hasSession || data.isMe {
      standardActions
        .padding(.horizontal, Spacing.lg)
    }
  }

  @ViewBuilder
  private var standardActions: some View {
    HStack(spacing: Spacing.sm) {
      if data.isMe {
        AlfButton(strings.editProfile, color: .secondary, size: .small) {
          onAction(.editProfile)
        }
      } else if !data.isBlocked && !data.isBlockedBy {
        followButton
      }
      Spacer(minLength: 0)
    }
  }

  private var followButton: some View {
    let state = ProfileFollowButtonState(followState: data.followState)
    return AlfButton(state.label(using: strings), color: state.color, size: .small) {
      switch state {
      case .follow: onAction(.follow)
      case .following: onAction(.unfollow)
      case .pendingFollowing, .pendingUnfollow: break
      }
    }
    .disabled(!state.isEnabled)
  }

  // MARK: - Moderation reveal

  private var revealBanner: some View {
    VStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
      Text(moderation.profileView.cause?.name ?? "")
        .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
      if moderation.profileView.allowsOverride {
        Button(strings.showAnyway) { onAction(.showAnyway) }
          .buttonStyle(.alf(color: .secondary, size: .small))
      }
    }
    .foregroundStyle(theme.atomColors.textInverted)
    .padding(Spacing.md)
    .frame(maxWidth: .infinity)
    .background(theme.atomColors.bgContrast900.opacity(0.75))
    .accessibilityElement(children: .combine)
  }
}
