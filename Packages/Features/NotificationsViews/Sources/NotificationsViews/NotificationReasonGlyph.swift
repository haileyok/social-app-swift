import DesignSystem
import SwiftUI

import NotificationsLogic

/**
 The leading glyph for a notification reason.

 The RN item (`~/bluesky/social-app/src/view/com/notifications/NotificationFeedItem.tsx`)
 chooses one icon component and one palette colour per reason branch; this type
 keeps that table as data, so the row view is a draw and the mapping reads at a
 glance. Icons are the SF Symbol stand-in for the RN icon set, the same
 substitution the app shell makes for its tab icons.
 */
public struct NotificationReasonGlyph: Equatable, Sendable {
  /// The SF Symbol name.
  public let systemImage: String
  /// Which palette entry the tint comes from, as a token the view resolves
  /// against the active theme.
  public let tint: NotificationGlyphTint

  /// The glyph for a reason, or `nil` when the row draws a post instead of an
  /// icon (replies, mentions, quotes) or when the reason is unknown.
  public static func glyph(for type: NotificationType) -> NotificationReasonGlyph? {
    switch type {
    case .postLike, .feedgenLike, .likeViaRepost:
      NotificationReasonGlyph(systemImage: "heart.fill", tint: .pink)
    case .repost, .repostViaRepost:
      NotificationReasonGlyph(systemImage: "arrow.2.squarepath", tint: .positive)
    case .follow:
      NotificationReasonGlyph(systemImage: "person.badge.plus", tint: .primary)
    case .contactMatch:
      NotificationReasonGlyph(systemImage: "person.crop.circle.badge.checkmark", tint: .primary)
    case .starterpackJoined:
      NotificationReasonGlyph(systemImage: "square.stack.3d.up.fill", tint: .primary)
    case .verified:
      NotificationReasonGlyph(systemImage: "checkmark.seal.fill", tint: .primary)
    case .unverified:
      NotificationReasonGlyph(systemImage: "checkmark.seal", tint: .neutral)
    case .subscribedPost:
      NotificationReasonGlyph(systemImage: "bell.badge.fill", tint: .primary)
    case .mention, .reply, .quote, .unknown:
      nil
    }
  }
}

/// The palette entries a reason glyph can be tinted with.
///
/// A token rather than a `Color` so the mapping stays theme-independent and the
/// view resolves it against whatever theme is active.
public enum NotificationGlyphTint: String, Sendable, CaseIterable {
  /// The RN `t.palette.pink`, used for likes.
  case pink
  /// The RN `t.palette.positive_500`, used for reposts.
  case positive
  /// The RN `t.palette.primary_500`, used for follows and system notices.
  case primary
  /// The RN `t.palette.contrast_500`, used for the removed-verification glyph.
  case neutral

  /// Resolves the token against a theme's palette.
  public func color(in theme: Theme) -> Color {
    switch self {
    case .pink: theme.colors.pink
    case .positive: theme.colors.positive500
    case .primary: theme.colors.primary500
    case .neutral: theme.colors.contrast500
    }
  }
}
