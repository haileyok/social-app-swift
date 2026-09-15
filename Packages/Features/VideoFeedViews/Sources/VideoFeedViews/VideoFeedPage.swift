import DesignSystem
import DesignTokens
import Moderation
import SwiftUI
import UIComponents
import UIComponentsCore
import VideoFeedLogic

/// One page of the vertical pager: the video surface, the gesture layer, the
/// scrubber and the overlay chrome.
///
/// The layout follows `VideoItemInner` in `src/screens/VideoFeed/index.tsx`: the
/// media fills the page, a tap surface sits above it, the scrubber is pinned to
/// the bottom of the media area, and the chrome is drawn in a bottom-anchored
/// VStack over a scrim.
struct VideoFeedPage: View {
  /// The item this page shows.
  let item: VideoItem
  /// The page's index in the pager.
  let index: Int
  /// Whether this page is the pager's selected one.
  let isActive: Bool
  /// The shared controller. `nil` until the screen has built its player pool.
  let controller: VideoFeedController?
  /// Links in the caption, routed to the caller.
  let onOpen: (RichTextTarget) -> Void

  @State private var isCaptionExpanded = false

  @Environment(\.alfTheme) private var theme

  /// The page's playback phase, or `.empty` before the pool exists.
  private var phase: VideoPlayerPhase {
    controller?.phase(at: index) ?? .empty
  }

  /// Whether a real player surface should be shown rather than the poster.
  private var showsPlayer: Bool {
    guard let controller else { return false }
    return controller.shouldRenderPlayer(at: index) && !phase.isFailed
  }

  /// Whether the moderation blur covers this page.
  private var isModerationBlurred: Bool {
    controller?.isBlurredByModeration(at: index) ?? false
  }

  var body: some View {
    ZStack {
      Color.black
      media
      gestureLayer
      if isActive {
        overlay
      }
      if isModerationBlurred {
        moderationOverlay
      }
    }
    .clipped()
    .accessibilityIdentifier(VideoFeedAccessibility.page(index))
    .accessibilityElement(children: .contain)
  }

  // MARK: - Media

  @ViewBuilder
  private var media: some View {
    if showsPlayer, let controller, let slot = controller.slot(for: index) {
      VideoPlayerSurface(slot: slot, fills: !item.video.isTallAspectRatio)
        .accessibilityIdentifier(VideoFeedAccessibility.player)
        .accessibilityLabel(item.accessibilityLabel)
        .ignoresSafeArea()
    } else {
      poster
    }
    if !item.isGif, isActive, phase == .loading {
      ProgressView()
        .progressViewStyle(.circular)
        .tint(.white)
        .accessibilityLabel(VideoFeedStrings.loadingVideo)
    }
  }

  /// The poster shown while the media loads, while the page is outside the
  /// preload window, and when the item has no playable source.
  private var poster: some View {
    RemoteImage(
      url: item.video.thumbnail.flatMap { URL(string: $0) },
      targetSize: nil,
      contentMode: .fill
    ) {
      VideoPosterPlaceholder(
        seed: item.post.author.handle.rawValue,
        alt: item.video.alt)
    }
    .ignoresSafeArea()
  }

  // MARK: - Gestures

  /// The tap surface. Port of the RN `Button` at the bottom of `VideoItem`:
  /// a single tap toggles play/pause, and a second tap inside the double-tap
  /// window likes the post instead.
  ///
  /// SwiftUI serialises the two recognizers - the single-tap handler only runs
  /// once the double tap has failed - so the 200 ms window the RN screen
  /// implements by hand is the system's here.
  private var gestureLayer: some View {
    Color.clear
      .contentShape(Rectangle())
      .accessibilityIdentifier(VideoFeedAccessibility.tapSurface(index))
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(VideoFeedStrings.videoHint)
      .accessibilityAddTraits(.isButton)
      .onTapGesture(count: 2) { like() }
      .onTapGesture(count: 1) { togglePlayPause() }
      .accessibilityAction(named: Text(VideoFeedStrings.play)) { togglePlayPause() }
      .accessibilityAction(named: Text(VideoFeedStrings.likeLabel)) { like() }
  }

  private func togglePlayPause() {
    controller?.togglePlayPause(at: index)
  }

  private func like() {
    controller?.like(at: index)
  }

  // MARK: - Overlay

  private var overlay: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      VideoItemOverlay(
        item: item,
        index: index,
        isExpanded: $isCaptionExpanded,
        isMuted: controller?.isMuted(at: index) ?? true,
        onToggleMuted: { toggleMuted() },
        captionOptions: controller?.captionOptions(at: index) ?? [],
        selectedCaptionID: controller?.selectedCaptionID(at: index),
        onSelectCaption: { id in controller?.selectCaption(id: id, at: index) },
        onOpen: onOpen,
        onOpenAuthor: {},
        onLike: like)
      if !item.isGif {
        VideoScrubber(
          progress: timing.progress,
          currentTime: timing.currentTime,
          remaining: timing.remaining,
          onSeek: { fraction in controller?.seek(toProgress: fraction, at: index) })
          .padding(.horizontal, Spacing.md)
          .padding(.bottom, Spacing.sm)
      }
    }
    .padding(.bottom, Spacing.md)
    .background(
      LinearGradient(
        colors: [.clear, .black.opacity(0.55)],
        startPoint: .center,
        endPoint: .bottom)
    )
  }

  private func toggleMuted() {
    guard let controller else { return }
    controller.setMuted(!controller.isMuted(at: index), at: index)
  }

  /// The blur overlay a moderation decision puts over the video.
  ///
  /// The gate itself lives in the controller: ``videoAutoplayDecision`` answers
  /// whether the item may play, and ``VideoFeedController/isBlurredByModeration(at:)``
  /// reports whether the blur is what stopped it. This is only the surface, and
  /// revealing it tells the controller the item may play.
  private var moderationOverlay: some View {
    ZStack {
      Rectangle()
        .fill(.ultraThinMaterial)
        .blur(radius: 12)
        .ignoresSafeArea()
      VStack(spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 20, weight: .semibold))
        Text(moderationDescription?.name ?? VideoFeedStrings.videoUnavailable)
          .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
          .multilineTextAlignment(.center)
        Button(VideoFeedStrings.show) {
          controller?.revealModeration(at: index)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Reveals the video")
      }
      .foregroundStyle(.white)
      .padding(.md)
    }
    .accessibilityIdentifier(VideoFeedAccessibility.moderationBlur)
    .accessibilityElement(children: .combine)
  }

  /// The copy for the blur, read from the item's moderation decision.
  private var moderationDescription: ModerationCauseDescription? {
    guard let decision = item.moderation else { return nil }
    if case .blur(let description, _) = moderationSurface(decision.ui(.contentMedia)) {
      return description
    }
    if case .blur(let description, _) = moderationSurface(decision.ui(.contentView)) {
      return description
    }
    return nil
  }

  private var timing: VideoPlayerTiming {
    controller?.timing(for: index) ?? .zero
  }

  private var accessibilityLabel: String {
    "Video from \(item.post.author.handle.rawValue). \(VideoFeedStrings.videoHint)"
  }
}

/// The stand-in poster for an item with no thumbnail, and for an item whose
/// media is not loaded yet.
struct VideoPosterPlaceholder: View {
  let seed: String
  let alt: String?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          theme.colors.primary600.opacity(0.85),
          theme.colors.contrast900.opacity(0.9),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
      VStack(spacing: Spacing.sm) {
        Text(avatarInitials(seed))
          .font(TypeScale.xxl.font(weight: Scales.FontWeight.bold))
          .foregroundStyle(theme.atomColors.textInverted)
        Text(alt?.isEmpty == false ? alt! : VideoFeedStrings.posterFallback)
          .font(TypeScale.sm.font())
          .foregroundStyle(theme.atomColors.textInverted.opacity(0.8))
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .padding(.horizontal, Spacing.xl)
      }
    }
    .ignoresSafeArea()
  }
}
