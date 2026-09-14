import Foundation
import Moderation

/// The autoplay inputs, as data.
///
/// Port of the three signals RN reads before it will start a video:
///
/// - `useAutoplayDisabled()` (`src/state/preferences/autoplay.tsx`), backed by
///   the `disableAutoplay` persisted flag, which defaults to the platform's
///   reduced-motion setting (`src/state/persisted/schema.ts`);
/// - the video mute state (`src/components/Post/Embed/VideoEmbed/VideoVolumeContext.tsx`),
///   which starts muted;
/// - whether the item is inside a message thread, where autoplay is suppressed
///   (`isWithinMessage` in `VideoEmbedInnerNative.tsx`).
public struct VideoAutoplaySettings: Sendable, Equatable {
  /// `disableAutoplay`. RN: `useAutoplayDisabled()`.
  public var autoplayDisabled: Bool
  /// The current mute state. RN: `useVideoMuteState()[0]`, initialised `true`.
  public var muted: Bool
  /// True for a video rendered inside a message thread. RN: `isWithinMessage`.
  public var isWithinMessage: Bool

  public init(
    autoplayDisabled: Bool = false,
    muted: Bool = true,
    isWithinMessage: Bool = false
  ) {
    self.autoplayDisabled = autoplayDisabled
    self.muted = muted
    self.isWithinMessage = isWithinMessage
  }

  /// The value the persisted `disableAutoplay` flag defaults to.
  ///
  /// RN: `PlatformInfo.getIsReducedMotionEnabled()`. The Logic layer cannot read
  /// the platform setting, so callers pass the result in; this constant documents
  /// the default rather than deciding it.
  public static let reducedMotionDefault = false
}

/// Whether an item is allowed to play, and why not if it is not.
///
/// This is the port of the two separate gates RN applies, unified into one
/// derivation so a caller cannot accidentally apply only one of them:
///
/// - the **autoplay** gate (`autoplay = !autoplayDisabled && !isWithinMessage`
///   in `VideoEmbedInnerNative.tsx`);
/// - the **moderation** gate, which in the immersive feed pauses the active
///   player when the decision blurs either `contentView` or `contentMedia`
///   (`updateVideoState` in `src/screens/VideoFeed/index.tsx`).
public enum VideoAutoplayDecision: Sendable, Equatable {
  /// Start (or keep) playing.
  case play
  /// Play only because the viewer started it - autoplay is off. The video still
  /// renders and is tappable.
  case playOnDemand
  /// Do not play: the viewer is inside a message thread.
  case suppressedInMessage
  /// Do not play: a moderation label blurs this video. The overlay shows instead.
  case blockedByModeration

  /// True when the player should be started without a tap.
  public var autoplays: Bool { self == .play }

  /// True when the item may play at all (autoplay or by tap).
  public var isPlayable: Bool {
    switch self {
    case .play, .playOnDemand: return true
    case .suppressedInMessage, .blockedByModeration: return false
    }
  }

  /// True when playback is held back by moderation rather than a preference, so
  /// the view can show the blur overlay instead of a paused frame.
  public var isModerationBlocked: Bool { self == .blockedByModeration }

  /// True when the item is rendered but will not start on its own.
  public var requiresTapToPlay: Bool { self == .playOnDemand }
}

/// Derives the autoplay decision for a video item.
///
/// The ordering is load-bearing and matches RN: a moderation blur wins over the
/// autoplay preference, because RN pauses an already-playing player when the
/// decision blurs (`updateVideoState` checks the decision *inside* the
/// `if (currVideo)` branch, after the preference has already been applied by the
/// player component). A message-thread video is likewise never started.
public func videoAutoplayDecision(
  settings: VideoAutoplaySettings,
  moderation: ModerationDecision?
) -> VideoAutoplayDecision {
  if isBlurredByModeration(moderation) { return .blockedByModeration }
  if settings.isWithinMessage { return .suppressedInMessage }
  if settings.autoplayDisabled { return .playOnDemand }
  return .play
}

/// True when `decision` blurs either of the two surfaces the immersive feed
/// gates playback on.
///
/// RN: `moderation.ui('contentView').blur || moderation.ui('contentMedia').blur`.
/// Both contexts are checked because a label can target the whole post (leaving
/// the media visible under a blurred card) or the media alone (leaving the text
/// visible) - either way the video must not start.
public func isBlurredByModeration(_ decision: ModerationDecision?) -> Bool {
  guard let decision else { return false }
  return decision.ui(.contentView).blur || decision.ui(.contentMedia).blur
}

/// The muted state a video should begin playback in.
///
/// Port of `beginMuted={isGif || (autoplayDisabled ? false : muted)}` in
/// `VideoEmbedInnerNative.tsx`. Read it carefully: a GIF always starts muted,
/// but when autoplay is *disabled* the video starts **unmuted**, because the
/// user initiated playback by tapping and expects to hear it.
public func videoBeginMuted(
  settings: VideoAutoplaySettings,
  isGif: Bool
) -> Bool {
  if isGif { return true }
  return settings.autoplayDisabled ? false : settings.muted
}
