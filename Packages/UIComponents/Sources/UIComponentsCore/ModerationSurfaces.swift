import Foundation
import Moderation

/// How a surface should render given a moderation decision.
///
/// `ModerationUI` already answers "is this blurred / filtered", but a view also
/// needs the *reason* (to label the mask and to decide whether the viewer may
/// reveal it) and the distinction between a hard filter and a dismissible blur.
/// That projection is pure, so it lives here and the SwiftUI layer stays a
/// lookup.
public enum ModerationSurface: Equatable, Sendable {
  /// Render the content normally.
  case none
  /// Blur the content behind a reveal affordance. `allowOverride` is false for
  /// causes marked no-override (e.g. `!hide`), where the viewer cannot reveal.
  case blur(ModerationCauseDescription, allowOverride: Bool)
  /// Replace the content entirely; there is no reveal.
  case filter(ModerationCauseDescription)

  /// True when the content renders at all (possibly behind a blur).
  public var isVisible: Bool {
    if case .filter = self { return false }
    return true
  }
}

/// The copy and severity a mask shows, ported from the RN app's
/// `useModerationCauseDescription`.
public struct ModerationCauseDescription: Equatable, Sendable {
  public let name: String
  public let description: String
  /// A short source label (a list name or handle) when the cause came from one.
  public let source: String?

  public init(name: String, description: String, source: String? = nil) {
    self.name = name
    self.description = description
    self.source = source
  }

  /// The generic warning shown when a blur has no describable cause.
  public static let contentWarning = ModerationCauseDescription(
    name: "Content Warning",
    description: "Moderator has chosen to set a general warning on the content.")

  /// Describes a cause the way the RN app does.
  public static func describe(_ cause: ModerationCause?) -> ModerationCauseDescription {
    guard let cause else { return contentWarning }
    switch cause.type {
    case .blocking:
      if let list = cause.source.list {
        return ModerationCauseDescription(
          name: "User Blocked by \"\(list.name)\"",
          description: "You have blocked this user. You cannot view their content.",
          source: list.name)
      }
      return ModerationCauseDescription(
        name: "User Blocked",
        description: "You have blocked this user. You cannot view their content.")
    case .blockedBy:
      return ModerationCauseDescription(
        name: "User Blocking You",
        description: "This user has blocked you. You cannot view their content.")
    case .blockOther:
      return ModerationCauseDescription(
        name: "Content Not Available",
        description:
          "This content is not available because one of the users involved has blocked the other."
      )
    case .muted:
      if let list = cause.source.list {
        return ModerationCauseDescription(
          name: "Muted by \"\(list.name)\"",
          description: "You have muted this user",
          source: list.name)
      }
      return ModerationCauseDescription(
        name: "Account Muted", description: "You have muted this account.")
    case .muteWord:
      return ModerationCauseDescription(
        name: "Post Hidden by Muted Word",
        description: "This post has been hidden by a muted word you have added.")
    case .hidden:
      return ModerationCauseDescription(
        name: "Post Hidden by You", description: "You have hidden this post")
    case .label:
      let identifier = cause.labelDef?.identifier ?? cause.label?.val ?? ""
      return ModerationCauseDescription(
        name: "Content Warning",
        description: identifier.isEmpty
          ? contentWarning.description
          : "This content has the \"\(identifier)\" label applied.",
        source: cause.label?.src)
    }
  }
}

/// Resolves a ``ModerationUI`` into a render decision.
///
/// Mirrors the RN hider's precedence: an alert/filter removes the content, a
/// blur masks it behind a reveal, and `interpretFilterAsBlur` lets a *list*
/// surface (where a filter would otherwise leave a gap) render a blur instead.
public func moderationSurface(
  _ ui: ModerationUI?,
  interpretFilterAsBlur: Bool = false,
  isOverridden: Bool = false
) -> ModerationSurface {
  guard let ui else { return .none }
  if !ui.blurs.isEmpty, let cause = ui.blurs.first {
    // A no-override cause cannot be revealed by the viewer, so the override
    // flag passed down from a parent does not apply.
    let allowOverride = !ui.noOverride && !isOverridden
    return .blur(
      ModerationCauseDescription.describe(cause), allowOverride: allowOverride)
  }
  if interpretFilterAsBlur, let cause = ui.filters.first {
    return .blur(ModerationCauseDescription.describe(cause), allowOverride: true)
  }
  if !ui.filters.isEmpty, let cause = ui.filters.first {
    return .filter(ModerationCauseDescription.describe(cause))
  }
  return .none
}

/// The moderation contexts a feed item renders across. Kept as a small struct so
/// a caller can precompute the four projections once per item.
public struct FeedItemModeration: Equatable, Sendable {
  /// The post body: display name, text and non-media embeds.
  public let content: ModerationSurface
  /// The post's media (images/video/external card).
  public let media: ModerationSurface
  /// The author's avatar.
  public let avatar: ModerationSurface
  /// The author's banner.
  public let banner: ModerationSurface

  public init(
    content: ModerationSurface,
    media: ModerationSurface,
    avatar: ModerationSurface,
    banner: ModerationSurface
  ) {
    self.content = content
    self.media = media
    self.avatar = avatar
    self.banner = banner
  }

  /// Projects a decision across the four surfaces a feed item uses.
  ///
  /// `contentMedia` is a separate context in the engine, so a media-only label
  /// blurs the gallery without blurring the post text.
  public static func project(_ decision: ModerationDecision) -> FeedItemModeration {
    FeedItemModeration(
      content: moderationSurface(decision.ui(.contentList)),
      media: moderationSurface(decision.ui(.contentMedia)),
      avatar: moderationSurface(decision.ui(.avatar)),
      banner: moderationSurface(decision.ui(.banner)))
  }
}
