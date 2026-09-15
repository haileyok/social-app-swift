import DesignSystem
import SwiftUI

/// The draggable progress control drawn over a standard video.
///
/// Port of `src/screens/VideoFeed/components/Scrubber.tsx` reduced to its
/// essentials: a progress track that responds to a horizontal drag. RN's version
/// also coordinates with the parent's scroll gesture (`blocksExternalGesture`) so
/// a scrub does not page the feed; SwiftUI resolves that itself, because a drag
/// on this view wins over the pager's scroll.
struct VideoScrubber: View {
  /// The playback position as a `0...1` fraction.
  let progress: Double
  /// The playhead position in seconds.
  let currentTime: Double
  /// The time left, in seconds.
  let remaining: Double
  /// Called with the new `0...1` fraction when the viewer drags.
  let onSeek: (Double) -> Void

  /// The fraction currently under the finger, which overrides `progress` while a
  /// drag is in flight so the bar tracks the finger rather than the playhead.
  @State private var dragProgress: Double?

  @Environment(\.alfTheme) private var theme

  /// The fraction the bar draws: the drag position while dragging, else the
  /// reported progress.
  private var displayedProgress: Double {
    min(1, max(0, dragProgress ?? progress))
  }

  var body: some View {
    VStack(spacing: Spacing.xs) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.3))
          Capsule()
            .fill(.white)
            .frame(width: max(0, geometry.size.width * displayedProgress))
        }
        .frame(height: 4)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard self.geometryWidth > 0 else { return }
              dragProgress = min(1, max(0, value.location.x / self.geometryWidth))
            }
            .onEnded { value in
              guard self.geometryWidth > 0 else {
                dragProgress = nil
                return
              }
              let fraction = min(1, max(0, value.location.x / self.geometryWidth))
              dragProgress = nil
              onSeek(fraction)
            }
        )
        .onAppear { geometryWidth = geometry.size.width }
        .onChange(of: geometry.size.width) { _, width in geometryWidth = width }
      }
      .frame(height: 4)
      HStack {
        Text(timeLabel(currentTime))
        Spacer(minLength: Spacing.sm)
        Text("-\(timeLabel(remaining))")
      }
      .font(TypeScale.xxs.font())
      .foregroundStyle(theme.atomColors.textInverted.opacity(0.85))
    }
    .accessibilityElement()
    .accessibilityLabel(VideoFeedStrings.scrubberLabel)
    .accessibilityHint(VideoFeedStrings.scrubberHint)
    .accessibilityValue("\(timeLabel(currentTime)) of \(timeLabel(currentTime + remaining))")
    .accessibilityAdjustableAction { direction in
      let step = 0.05
      switch direction {
      case .increment: onSeek(min(1, displayedProgress + step))
      case .decrement: onSeek(max(0, displayedProgress - step))
      @unknown default: break
      }
    }
  }

  /// The last observed track width, so the drag handlers can convert a location
  /// into a fraction without re-reading the geometry inside the gesture closure.
  @State private var geometryWidth: Double = 0

  /// Formats a duration as `m:ss`, matching the RN time indicator.
  private func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let minutes = total / 60
    let remainder = total % 60
    return "\(minutes):\(remainder < 10 ? "0" : "")\(remainder)"
  }
}
