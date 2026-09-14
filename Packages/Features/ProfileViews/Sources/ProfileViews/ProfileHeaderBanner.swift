import DesignSystem
import DesignTokens
import Lexicons
import ProfileLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The banner + avatar overlap header shared by the standard and labeler
/// variants.
///
/// The look follows the RN `ProfileHeaderShell`: a full-bleed banner with the
/// avatar pulled down over its lower edge, and the avatar drawn from the
/// unshadowed profile so a shadow edit does not move it.
///
/// ```swift
/// ProfileHeaderBanner(profile: data.profile, moderation: moderation)
/// ```
public struct ProfileHeaderBanner: View {
  private let profile: ProfileView
  private let moderation: ProfileHeaderModeration
  private let isMe: Bool

  /// How far the avatar's centre sits above the banner's bottom edge.
  public static let avatarOverlap: Double = 32

  public init(
    profile: ProfileView,
    moderation: ProfileHeaderModeration = ProfileHeaderModeration(),
    isMe: Bool = false
  ) {
    self.profile = profile
    self.moderation = moderation
    self.isMe = isMe
  }

  public var body: some View {
    ZStack(alignment: .bottomLeading) {
      ModerationMask(surface: moderation.banner) {
        Banner(banner: profile.bannerURL)
      }
      ModerationMask(surface: moderation.avatar) {
        Avatar(
          avatar: profile.avatarURL,
          handle: profile.handle,
          displayName: profile.displayName,
          size: .xl)
      }
      .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: isMe ? 2 : 1))
      .offset(x: Spacing.lg, y: Self.avatarOverlap)
    }
    .padding(.bottom, Self.avatarOverlap)
  }
}

extension ProfileHeaderBanner {
  /// The distance the header's text block must clear beneath the banner.
  public var textInset: Double { Self.avatarOverlap + Spacing.md }
}
