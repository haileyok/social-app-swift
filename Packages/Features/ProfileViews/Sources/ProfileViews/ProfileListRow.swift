import DesignSystem
import DesignTokens
import Lexicons
import Moderation
import ProfileLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// One actor in a followers / follows / known-followers list.
///
/// Port of the RN `ProfileCard` row: avatar, display name, handle, and an inline
/// follow button. Moderation is projected for the `profileList` context, which is
/// what the engine uses for rows rather than the `profileView` context a full
/// screen uses.
public struct ProfileListRow: View {
  private let profile: ProfileView
  private let moderationOpts: ModerationOpts?
  private let strings: any ProfileStrings
  private let onSelect: () -> Void
  private let onToggleFollow: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  public init(
    profile: ProfileView,
    moderationOpts: ModerationOpts? = nil,
    strings: any ProfileStrings = defaultProfileStrings,
    onSelect: @escaping () -> Void = {},
    onToggleFollow: (() -> Void)? = nil
  ) {
    self.profile = profile
    self.moderationOpts = moderationOpts
    self.strings = strings
    self.onSelect = onSelect
    self.onToggleFollow = onToggleFollow
  }

  /// The row's moderation surface, derived for the list context.
  private var surface: ModerationSurface {
    guard let moderationOpts else { return .none }
    let decision = moderateProfile(profile.moderationSubject, opts: moderationOpts)
    return moderationSurface(decision.ui(.profileList), interpretFilterAsBlur: true)
  }

  private var followState: ProfileFollowButtonState {
    ProfileFollowButtonState(followState: FollowState(viewer: profile.viewer, shadow: nil))
  }

  public var body: some View {
    ModerationMask(surface: surface) {
      Button(action: onSelect) {
        HStack(spacing: Spacing.md) {
          Avatar(
            avatar: profile.avatarURL,
            handle: profile.handle,
            displayName: profile.displayName,
            size: .md)
          identity
          Spacer(minLength: Spacing.sm)
          if let onToggleFollow, followState != .pendingFollowing {
            AlfButton(
              followState.label(using: strings),
              color: followState.color,
              size: .tiny,
              action: onToggleFollow)
            .disabled(!followState.isEnabled)
          }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
    }
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(profile.displayName ?? "@\(profile.handle)")
        .font(TypeScale.md.font(weight: Scales.FontWeight.semiBold))
        .foregroundStyle(theme.atomColors.text)
        .lineLimit(1)
      Text("@\(profile.handle)")
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .lineLimit(1)
    }
  }
}
