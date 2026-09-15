import DesignSystem
import Lexicons
import RichText
import SwiftUI
import SwiftAtproto
import UIComponents
import UIComponentsCore
import VideoFeedLogic

/// The chrome drawn over a video: author, caption, engagement affordances and the
/// mute control.
///
/// Follows the bottom-anchored layout of `VideoItemInner` in
/// `src/screens/VideoFeed/index.tsx`: a scrim, then the author row, an optional
/// follow button, the expandable caption, and the engagement controls. The
/// controls RN renders (`PostControls`) are reduced to the three the immersive
/// feed shows, since this screen has no reply or repost composer of its own.
struct VideoItemOverlay: View {
  /// The item being drawn.
  let item: VideoItem
  /// The item's index, for accessibility identifiers.
  let index: Int
  /// Whether the post is expanded past the caption's line limit.
  @Binding var isExpanded: Bool
  /// The current mute state, so the mute control can show the right affordance.
  let isMuted: Bool
  /// Toggles the mute state.
  let onToggleMuted: () -> Void
  /// Opens a rich-text link in the caption.
  let onOpen: (RichTextTarget) -> Void
  /// Opens the author's profile.
  let onOpenAuthor: () -> Void
  /// Likes the post.
  let onLike: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      muteControl
      authorRow
      if !captionSegments.isEmpty {
        caption
      }
      engagementRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(VideoFeedAccessibility.overlay)
    .accessibilityElement(children: .contain)
  }

  /// The mute toggle, right-aligned above the author row, where RN places its
  /// volume `ControlButton`.
  private var muteControl: some View {
    HStack {
      Spacer(minLength: 0)
      if !item.isGif {
        Button(action: onToggleMuted) {
          Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.atomColors.textInverted)
            .padding(Spacing.sm)
            .background(theme.atomColors.bgContrast1000.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? VideoFeedStrings.unmute : VideoFeedStrings.mute)
      }
    }
  }

  /// The author line: avatar, display name and handle.
  private var authorRow: some View {
    Button(action: onOpenAuthor) {
      HStack(spacing: Spacing.sm) {
        Avatar(
          source: AvatarSource.resolve(
            avatar: item.post.author.avatar?.rawValue,
            handle: item.post.author.handle.rawValue,
            displayName: item.post.author.displayName),
          size: .md,
          label: displayName)
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(displayName)
            .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
            .foregroundStyle(theme.atomColors.textInverted)
            .lineLimit(1)
          Text(handle)
            .font(TypeScale.xs.font())
            .foregroundStyle(theme.atomColors.textInverted.opacity(0.75))
            .lineLimit(1)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(displayName), \(handle)")
    .accessibilityHint(VideoFeedStrings.openProfileLabel)
  }

  /// The caption, rendered through the shared rich-text renderer.
  private var caption: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      RichTextBody(segments: captionSegments, scale: .sm, onOpen: onOpen)
        .lineLimit(isExpanded ? nil : 3)
      Button {
        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
      } label: {
        Text(isExpanded ? VideoFeedStrings.lessLabel : VideoFeedStrings.moreLabel)
          .font(TypeScale.xs.font(weight: Scales.FontWeight.semiBold))
          .foregroundStyle(theme.atomColors.textInverted.opacity(0.85))
      }
      .buttonStyle(.plain)
    }
  }

  /// The reply, like and share affordances.
  private var engagementRow: some View {
    HStack(spacing: Spacing.xl) {
      VideoEngagementButton(
        systemImage: "bubble.left",
        count: formatOptionalCount(item.post.replyCount),
        label: VideoFeedStrings.replyLabel,
        action: nil)
      VideoEngagementButton(
        systemImage: "heart",
        count: formatOptionalCount(item.post.likeCount),
        label: VideoFeedStrings.likeLabel,
        action: onLike)
      VideoEngagementButton(
        systemImage: "square.and.arrow.up",
        count: nil,
        label: VideoFeedStrings.shareLabel,
        action: nil)
      Spacer(minLength: 0)
    }
    .accessibilityIdentifier(VideoFeedAccessibility.engagementRow)
  }

  /// The caption's rich-text segments, built from the post record.
  private var captionSegments: [RichTextSegment] {
    guard case .record(let value) = item.post.record,
      let post = value as? App.Bsky.FeedPost
    else { return [] }
    return richTextFromRecord(FeedPostRecord(text: post.text)).segments()
  }

  /// The author's display name, falling back to the handle.
  private var displayName: String {
    let name = item.post.author.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (name?.isEmpty == false ? name! : handle)
  }

  /// The author's handle, with the leading `@`.
  private var handle: String { "@\(item.post.author.handle.rawValue)" }
}

/// One icon-and-count engagement affordance in the overlay.
struct VideoEngagementButton: View {
  let systemImage: String
  let count: String?
  let label: String
  let action: (() -> Void)?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Button {
      action?()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: systemImage)
          .font(.system(size: 16))
        if let count {
          Text(count)
            .font(TypeScale.xs.font())
        }
      }
      .foregroundStyle(theme.atomColors.textInverted)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(action == nil)
    .accessibilityLabel(count.map { "\(label), \($0)" } ?? label)
  }
}
