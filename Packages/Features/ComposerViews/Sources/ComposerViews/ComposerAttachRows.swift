#if canImport(SwiftUI)
import ComposerLogic
import DesignSystem
import DesignTokens
import Moderation
import SwiftUI
import UIComponents
import UIKit
import UIComponentsCore

/// One attached image, with its alt-text field and its remove control.
///
/// The RN composer shows alt text inline in an `ImageAltTextDialog`
/// (`photos/ImageAltTextDialog.tsx`); native-first, the row keeps the thumbnail
/// and the alt field together, so the alt text is visible without opening a
/// dialog and the "missing alt text" block is obvious at a glance.
struct ComposerImageAttachRow: View {
  /// The image as the post holds it.
  let image: ComposerImage
  /// Whether the account requires alt text, so an empty field reads as an error.
  let requireAltText: Bool
  /// Called with the edited alt text.
  let onAltChanged: (String) -> Void
  /// Called when the remove control is tapped.
  let onRemove: () -> Void

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale

  /// Whether this image is missing the alt text the account requires.
  private var isMissingAlt: Bool { requireAltText && image.alt.isEmpty }

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      thumbnail
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(
          ComposerCopy.altTextPlaceholder,
          scale: .xs,
          color: isMissingAlt ? theme.colors.negative400 : theme.atomColors.textContrastMedium)
        altField
      }
      removeButton
    }
    .padding(Spacing.sm)
    .background(theme.atomColors.bgContrast25)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        .strokeBorder(
          isMissingAlt ? theme.colors.negative400 : theme.atomColors.borderContrastLow,
          lineWidth: 1)
    }
    .cornerRadius(.md)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(ComposerAccessibility.imageRow(image.id))
  }

  /// The local thumbnail, falling back to a themed placeholder when decoding fails.
  @ViewBuilder
  private var thumbnail: some View {
    if let platformImage = UIImage(contentsOfFile: image.sourcePath) {
      Image(uiImage: platformImage)
        .resizable()
        .scaledToFill()
        .frame(width: 72, height: 72)
        .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityLabel(image.alt.isEmpty ? "Image without a description" : image.alt)
    } else {
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(theme.atomColors.bgContrast100)
        .frame(width: 72, height: 72 * aspectRatio)
        .overlay {
          Image(systemName: "photo")
            .foregroundStyle(theme.atomColors.textContrastLow)
        }
        .accessibilityLabel(image.alt.isEmpty ? "Image without a description" : image.alt)
    }
  }

  /// The image's height/width ratio, clamped so a panorama cannot blow up the row.
  private var aspectRatio: Double {
    guard image.width > 0 else { return 1 }
    return min(1.5, max(0.5, image.height / image.width))
  }

  private var altField: some View {
    TextField(ComposerCopy.altTextPlaceholder, text: altBinding, axis: .vertical)
      .font(TypeScale.sm.font(fontScale: fontScale, family: family, weight: Scales.FontWeight.normal))
      .foregroundStyle(theme.atomColors.text)
      .tint(theme.colors.primary500)
      .lineLimit(1...4)
      .accessibilityLabel(ComposerCopy.altTextLabel)
      .accessibilityIdentifier(ComposerAccessibility.imageAltField(image.id))
  }

  private var altBinding: Binding<String> {
    Binding(get: { image.alt }, set: onAltChanged)
  }

  private var removeButton: some View {
    AlfIconButton(
      systemImage: "xmark",
      label: ComposerCopy.removeImageAction,
      color: .secondary,
      size: .tiny,
      shape: .round,
      action: onRemove
    )
    .accessibilityIdentifier(ComposerAccessibility.imageRemove(image.id))
  }
}

/// The attached-video row, in whichever pipeline state the video is in.
///
/// Ported from `videos/VideoPreview.tsx` and `VideoTranscodeProgress.tsx`: while
/// the pipeline runs the row shows the monotonic global progress, and once it is
/// done or failed the alt-text field appears (or stays).
struct ComposerVideoAttachRow: View {
  /// The video, in its current state.
  let video: ComposerVideo
  /// Whether the account requires alt text.
  let requireAltText: Bool
  /// Called with the edited alt text.
  let onAltChanged: (String) -> Void
  /// Called when the remove control is tapped.
  let onRemove: () -> Void

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale

  private var isFailed: Bool {
    if case .error = video { return true }
    return false
  }

  /// Whether the pipeline is still running.
  private var isWorking: Bool {
    switch video {
    case .compressing, .uploading, .processing: true
    case .error, .done: false
    }
  }

  private var isMissingAlt: Bool { requireAltText && !isFailed && video.altText.isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        videoThumbnail
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          AlfText(
            ComposerCopy.videoStatus(video.status),
            scale: .sm,
            weight: Scales.FontWeight.medium,
            color: statusColor)
          if let asset = video.asset {
            AlfText(
              durationLabel(asset),
              scale: .xs,
              color: theme.atomColors.textContrastMedium)
          }
          if case .error(let state) = video {
            AlfText(state.error, scale: .xs, color: theme.colors.negative500)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        removeButton
      }

      if isWorking {
        progressBar
      }

      if !isFailed {
        altFieldGroup
      }
    }
    .padding(Spacing.sm)
    .background(theme.atomColors.bgContrast25)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        .strokeBorder(borderColor, lineWidth: 1)
    }
    .cornerRadius(.md)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(ComposerAccessibility.videoRow)
  }

  private var statusColor: Color {
    isFailed ? theme.colors.negative500 : theme.atomColors.text
  }

  private var borderColor: Color {
    if isFailed || isMissingAlt { return theme.colors.negative400 }
    return theme.atomColors.borderContrastLow
  }

  private var videoThumbnail: some View {
    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
      .fill(theme.atomColors.bgContrast100)
      .frame(width: 56, height: 56)
      .overlay {
        Image(systemName: isFailed ? "exclamationmark.triangle" : "video")
          .foregroundStyle(isFailed ? theme.colors.negative500 : theme.atomColors.textContrastLow)
      }
  }

  private var progressBar: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(theme.atomColors.bgContrast100)
        Capsule()
          .fill(theme.colors.primary500)
          .frame(width: proxy.size.width * min(1, max(0, video.progress)))
      }
    }
    .frame(height: 4)
    .accessibilityIdentifier(ComposerAccessibility.videoProgress)
    .accessibilityLabel(ComposerCopy.videoStatus(video.status))
    .accessibilityValue("\(Int(video.progress * 100))%")
  }

  private var altFieldGroup: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      AlfText(
        ComposerCopy.videoAltPlaceholder,
        scale: .xs,
        color: isMissingAlt ? theme.colors.negative400 : theme.atomColors.textContrastMedium)
      TextField(ComposerCopy.videoAltPlaceholder, text: altBinding, axis: .vertical)
        .font(TypeScale.sm.font(fontScale: fontScale, family: family, weight: Scales.FontWeight.normal))
        .foregroundStyle(theme.atomColors.text)
        .tint(theme.colors.primary500)
        .lineLimit(1...4)
        .accessibilityLabel(ComposerCopy.altTextLabel)
        .accessibilityIdentifier(ComposerAccessibility.videoAltField)
    }
  }

  private var altBinding: Binding<String> {
    Binding(get: { video.altText }, set: onAltChanged)
  }

  private var removeButton: some View {
    AlfIconButton(
      systemImage: "xmark",
      label: ComposerCopy.removeVideoAction,
      color: .secondary,
      size: .tiny,
      shape: .round,
      action: onRemove
    )
    .accessibilityIdentifier(ComposerAccessibility.videoRemove)
  }

  /// `mm:ss` for the asset's duration, or the byte size when there is no duration.
  private func durationLabel(_ asset: ComposerVideoAsset) -> String {
    guard let durationMs = asset.durationMs else {
      return ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)
    }
    let totalSeconds = durationMs / 1000
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}

/// The attached-GIF row.
///
/// A GIF is small enough to preview from its resolved URL, so unlike images and
/// video this row renders the real media through the shared `RemoteImage` loader.
struct ComposerGifAttachRow: View {
  /// The GIF attachment.
  let gif: GifMedia
  /// Whether the account requires alt text.
  let requireAltText: Bool
  /// Called with the edited alt text.
  let onAltChanged: (String) -> Void
  /// Called when the remove control is tapped.
  let onRemove: () -> Void

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale

  private var isMissingAlt: Bool { requireAltText && gif.alt.isEmpty }

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      RemoteImage(
        url: URL(string: gif.gif.url),
        targetSize: ImageTargetSize(width: 56, height: 56),
        contentMode: .fill,
        placeholder: { Rectangle().fill(theme.atomColors.bgContrast100) },
        failure: {
          Rectangle()
            .fill(theme.atomColors.bgContrast100)
            .overlay {
              Image(systemName: "photo").foregroundStyle(theme.atomColors.textContrastLow)
            }
        }
      )
      .frame(width: 56, height: 56)
      .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText("GIF", scale: .sm, weight: Scales.FontWeight.medium)
        TextField(ComposerCopy.gifAltPlaceholder, text: altBinding, axis: .vertical)
          .font(TypeScale.sm.font(fontScale: fontScale, family: family, weight: Scales.FontWeight.normal))
          .foregroundStyle(theme.atomColors.text)
          .tint(theme.colors.primary500)
          .lineLimit(1...3)
          .accessibilityLabel(ComposerCopy.altTextLabel)
      }

      AlfIconButton(
        systemImage: "xmark",
        label: ComposerCopy.removeImageAction,
        color: .secondary,
        size: .tiny,
        shape: .round,
        action: onRemove
      )
    }
    .padding(Spacing.sm)
    .background(theme.atomColors.bgContrast25)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        .strokeBorder(
          isMissingAlt ? theme.colors.negative400 : theme.atomColors.borderContrastLow,
          lineWidth: 1)
    }
    .cornerRadius(.md)
  }

  private var altBinding: Binding<String> {
    Binding(get: { gif.alt }, set: onAltChanged)
  }
}

/// The detected link card, with its remove control.
///
/// Ported from `ExternalEmbed.tsx`: the RN composer shows the card the link
/// resolved to, above the media, and a control to drop it. The card itself is
/// the shared ``ExternalCard``, so the composer and the feed render a link the
/// same way.
struct ComposerLinkCardRow: View {
  /// The detected link's URI.
  let uri: String
  /// Called when the card is removed.
  let onRemove: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack {
        AlfText(
          ComposerCopy.linkCardLabel,
          scale: .xs,
          color: theme.atomColors.textContrastMedium)
        Spacer(minLength: Spacing.sm)
        Button(ComposerCopy.removeAction, action: onRemove)
          .font(.caption)
          .foregroundStyle(theme.colors.primary500)
      }
      ExternalCard(
        external: EmbedExternal(
          uri: uri,
          title: nil,
          description: nil))
    }
    .padding(Spacing.sm)
    .background(theme.atomColors.bgContrast25)
    .cornerRadius(.md)
    .accessibilityIdentifier(ComposerAccessibility.linkCardRow)
  }
}
#endif
