import Foundation

/// The view-owned copy for the immersive video feed.
///
/// The same seam `LoginViews` uses (`LoginCopy`): every user-facing string a
/// video screen shows is read through one of these members, so swapping them for
/// `String(localized:)` calls later is a single-file change and no view carries
/// a scattered literal. Strings the logic layer already owns (a post's text, an
/// error description) are deliberately absent.
public enum VideoFeedStrings {
  // MARK: - Screen chrome

  /// The screen's title.
  public static let screenTitle = "Video"
  /// The scrim label for the scrubbable video surface.
  public static let scrubberLabel = "Video position"
  /// The hint attached to the scrubbable video surface.
  public static let scrubberHint = "Adjusts the video position"

  // MARK: - Playback controls

  /// The play affordance.
  public static let play = "Play"
  /// The pause affordance.
  public static let pause = "Pause"
  /// The unmute affordance.
  public static let unmute = "Unmute"
  /// The mute affordance.
  public static let mute = "Mute"
  /// The caption track picker's label.
  public static let captions = "Captions"
  /// The caption picker's "no captions" option.
  public static let captionsOff = "Off"
  /// The hint on the video surface explaining the tap gestures.
  public static let videoHint = "Tap to play or pause the video"
  /// The hint that a double tap likes the post.
  public static let likeHint = "Double tap to like"

  // MARK: - Overlay chrome

  /// The engagement row's reply label.
  public static let replyLabel = "Reply"
  /// The engagement row's like label.
  public static let likeLabel = "Like"
  /// The engagement row's share label.
  public static let shareLabel = "Share"
  /// The label on the author line.
  public static let openProfileLabel = "Open profile"
  /// The reveal affordance on a moderation blur.
  public static let show = "Show"
  /// The expand affordance for a truncated caption.
  public static let moreLabel = "More"
  /// The collapse affordance for an expanded caption.
  public static let lessLabel = "Less"

  // MARK: - Playback states

  /// Shown while the media loads.
  public static let loadingVideo = "Loading video"
  /// Shown when the media cannot be played.
  public static let videoUnavailable = "Video unavailable"
  /// Shown in place of controls when the video has no media yet.
  public static let posterFallback = "Video"
}
