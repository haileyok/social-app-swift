import Foundation

/// Accessibility identifiers for the immersive video feed.
///
/// Mirrors `ShellAccessibility`: the app and its XCUITest bundle read the
/// identifiers from one place rather than duplicating string literals, so a
/// screenshot or smoke test can address a specific surface.
public enum VideoFeedAccessibility {
  /// The pager's root container.
  public static let screen = "videoFeed.screen"
  /// The vertical pager itself.
  public static let pager = "videoFeed.pager"
  /// The overlay chrome for one page.
  public static let overlay = "videoFeed.overlay"
  /// The tap surface that toggles play/pause and likes on a double tap.
  public static let tapSurface = "videoFeed.tapSurface"
  /// The poster/played video surface.
  public static let player = "videoFeed.player"
  /// The moderation blur overlay.
  public static let moderationBlur = "videoFeed.moderationBlur"
  /// The engagement row.
  public static let engagementRow = "videoFeed.engagement"

  /// The identifier for the page at `index`.
  public static func page(_ index: Int) -> String { "videoFeed.page.\(index)" }

  /// The identifier for the tap surface of the page at `index`.
  public static func tapSurface(_ index: Int) -> String { "videoFeed.tapSurface.\(index)" }

  /// The identifier for the like control of the page at `index`.
  public static func like(_ index: Int) -> String { "videoFeed.like.\(index)" }
}
