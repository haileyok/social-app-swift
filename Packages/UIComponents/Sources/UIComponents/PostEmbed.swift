#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import Moderation
import RichText
import SwiftUI
import UIComponentsCore

/// The v1 embed matrix.
///
/// One view per hydrated embed variant, dispatched on the ``EmbedVariantInfo``
/// the core derived. Each variant is wrapped in its own ``ModerationMask`` so a
/// media-only label blurs the media without touching the post text, matching the
/// engine's separate `contentMedia` context.
///
/// ```swift
/// PostEmbed(embed: item.postEmbed, info: item.embed, moderation: item.moderation.media)
/// ```
public struct PostEmbed: View {
  private let embed: PostViewEmbed?
  private let info: EmbedVariantInfo?
  private let moderation: ModerationSurface
  private let onOpen: (RichTextTarget) -> Void

  public init(
    embed: PostViewEmbed?,
    info: EmbedVariantInfo?,
    moderation: ModerationSurface = .none,
    onOpen: @escaping (RichTextTarget) -> Void = { _ in }
  ) {
    self.embed = embed
    self.info = info
    self.moderation = moderation
    self.onOpen = onOpen
  }

  public var body: some View {
    if let embed, let info {
      ModerationMask(surface: moderation) {
        variantBody(embed: embed, info: info)
      }
    }
  }

  @ViewBuilder
  private func variantBody(embed: PostViewEmbed, info: EmbedVariantInfo) -> some View {
    switch embed {
    case .images(let images):
      ImageGallery(images: images, layout: .forImageCount(images.count))
    case .gallery(let items):
      galleryItemsView(items)
    case .external(let external):
      ExternalCard(external: external, onOpen: onOpen)
    case .record(let record):
      QuotedPost(record: record, onOpen: onOpen)
    case .recordWithMedia(let value):
      VStack(spacing: Spacing.sm) {
        mediaView(value.media)
        QuotedPost(record: value.record, onOpen: onOpen)
      }
    case .video(let video):
      VideoEmbed(view: video, onOpen: onOpen)
    case .unknown(let type):
      UnsupportedEmbed(type: type)
    }
  }

  @ViewBuilder
  private func mediaView(_ media: RecordWithMediaViewMedia?) -> some View {
    switch media {
    case .images(let images):
      ImageGallery(images: images, layout: .forImageCount(images.count))
    case .gallery(let items):
      galleryItemsView(items)
    case .external(let external):
      ExternalCard(external: external, onOpen: onOpen)
    case .video(let video):
      VideoEmbed(view: video, onOpen: onOpen)
    case .unknown, .none:
      EmptyView()
    }
  }

  /// The gallery-item union carries no direct image array, so unwrap the image
  /// variants first and derive the layout from the count that survives.
  private func galleryItemsView(_ items: [EmbedGalleryItem]) -> some View {
    let images = galleryImages(items)
    return ImageGallery(images: images, layout: .forImageCount(images.count))
  }
}

/// The image gallery: one full-width cell, two up, a lead plus two, or a 2x2
/// grid, matching the RN gallery layouts.
public struct ImageGallery: View {
  private let images: [EmbedImage]
  private let layout: ImageGalleryLayout

  public init(images: [EmbedImage], layout: ImageGalleryLayout) {
    self.images = images
    self.layout = layout
  }

  public var body: some View {
    Group {
      switch layout {
      case .single:
        cell(images.first, height: 180)
      case .twoUp:
        HStack(spacing: 2) {
          cell(images.first, height: 140)
          cell(images.dropFirst().first, height: 140)
        }
      case .threeUp:
        VStack(spacing: 2) {
          cell(images.first, height: 160)
          HStack(spacing: 2) {
            cell(images.dropFirst().first, height: 100)
            cell(images.dropFirst(2).first, height: 100)
          }
        }
      case .grid:
        VStack(spacing: 2) {
          HStack(spacing: 2) {
            cell(images.first, height: 130)
            cell(images.dropFirst().first, height: 130)
          }
          HStack(spacing: 2) {
            cell(images.dropFirst(2).first, height: 130)
            cell(images.dropFirst(3).first, height: 130)
          }
        }
      }
    }
    .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func cell(_ image: EmbedImage?, height: Double) -> some View {
    if let image {
      RemoteImage(
        url: embedImageURL(image),
        targetSize: ImageTargetSize(width: 180, height: height),
        contentMode: .fill,
        placeholder: {
          Rectangle().fill(placeholderFill)
        }
      )
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .clipped()
      .accessibilityLabel(image.alt?.isEmpty == false ? image.alt! : "Image")
    }
  }

  @Environment(\.alfTheme) private var theme
  private var placeholderFill: Color { theme.atomColors.bgContrast100 }
}

/// The external link card.
public struct ExternalCard: View {
  private let external: EmbedExternal
  private let onOpen: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    external: EmbedExternal,
    onOpen: @escaping (RichTextTarget) -> Void = { _ in }
  ) {
    self.external = external
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if let host = hostLabel {
          Text(host)
            .font(TypeScale.xs.font())
            .foregroundStyle(theme.atomColors.textContrastMedium)
        }
        if let title = external.title, !title.isEmpty {
          Text(title)
            .font(TypeScale.sm.font(weight: "600"))
            .foregroundStyle(theme.atomColors.text)
            .lineLimit(3)
        }
        if let description = external.description, !description.isEmpty {
          Text(description)
            .font(TypeScale.sm.font())
            .foregroundStyle(theme.atomColors.textContrastMedium)
            .lineLimit(3)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.md)
    }
    .background(theme.atomColors.bgContrast25)
    .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        .stroke(theme.atomColors.borderContrastLow, lineWidth: 1))
    .accessibilityElement(children: .combine)
    .highPriorityGesture(
      TapGesture().onEnded {
        guard let uri = external.uri, let url = URL(string: uri) else { return }
        onOpen(.external(url))
      })
  }

  /// The display host, without the scheme or a leading `www.`.
  private var hostLabel: String? {
    guard let uri = external.uri, let url = URL(string: uri) else { return nil }
    return url.host()?.replacingOccurrences(of: "www.", with: "")
  }
}

/// The quoted post: a compact author line plus body, or the blocked/not-found
/// body when the record could not be hydrated.
public struct QuotedPost: View {
  private let record: EmbedRecordView?
  private let onOpen: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    record: EmbedRecordView?,
    onOpen: @escaping (RichTextTarget) -> Void = { _ in }
  ) {
    self.record = record
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      switch record?.record {
      case .viewRecord(let value):
        recordBody(value)
      case .viewBlocked:
        unavailable("Blocked post")
      case .viewNotFound:
        unavailable("Post not found")
      case .unknown, .none:
        unavailable("Post not available")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.md)
    .background(theme.atomColors.bgContrast25)
    .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        .stroke(theme.atomColors.borderContrastLow, lineWidth: 1))
    .highPriorityGesture(
      TapGesture().onEnded {
        guard let union = record?.record, case .viewRecord(let value) = union,
          let uri = value.uri
        else { return }
        onOpen(.post(uri: uri))
      })
  }

  @ViewBuilder
  private func recordBody(_ value: EmbedViewRecord) -> some View {
    HStack(spacing: Spacing.sm) {
      if let author = value.author {
        Avatar(
          avatar: author.avatar, handle: author.handle,
          displayName: author.displayName, size: .xs)
        Text(author.displayName?.isEmpty == false ? author.displayName! : "@\(author.handle)")
          .font(TypeScale.sm.font(weight: "600"))
          .foregroundStyle(theme.atomColors.text)
          .lineLimit(1)
        if author.displayName?.isEmpty == false {
          Text("@\(author.handle)")
            .font(TypeScale.sm.font())
            .foregroundStyle(theme.atomColors.textContrastMedium)
            .lineLimit(1)
        }
      }
    }
    if let text = value.value?.text, !text.isEmpty {
      Text(text)
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.text)
        .lineLimit(6)
    }
  }

  private func unavailable(_ message: String) -> some View {
    Text(message)
      .font(TypeScale.sm.font())
      .foregroundStyle(theme.atomColors.textContrastMedium)
  }
}

/// A video embed. v1 renders a placeholder tile; the player lands with the
/// media feature package.
public struct VideoPlaceholder: View {
  private let thumbnail: URL?
  private let label: String

  @Environment(\.alfTheme) private var theme

  public init(thumbnail: URL? = nil, label: String = "Video") {
    self.thumbnail = thumbnail
    self.label = label
  }

  public var body: some View {
    ZStack {
      RemoteImage(
        url: thumbnail,
        targetSize: ImageTargetSize(width: 360, height: 200),
        contentMode: .fill,
        placeholder: { Rectangle().fill(theme.atomColors.bgContrast100) })
      Image(systemName: "play.fill")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(theme.atomColors.textInverted)
        .padding(.xxl)
        .background(theme.atomColors.bgContrast900.opacity(0.4))
        .clipShape(.circle)
    }
    .frame(height: 200)
    .frame(maxWidth: .infinity)
    .clipped()
    .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    .accessibilityLabel(label)
  }
}

/// A video embed: the poster frame with a play affordance, filling the card's
/// width at the declared aspect (16:9 when undeclared).
struct VideoEmbed: View {
  let view: EmbedVideoView
  let onOpen: (RichTextTarget) -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    ZStack {
      RemoteImage(
        url: URL(string: view.thumbnail ?? ""),
        contentMode: .fill,
        placeholder: {
          Rectangle()
            .fill(theme.atomColors.bgContrast100)
            .overlay {
              Image(systemName: "video")
                .foregroundStyle(theme.atomColors.textContrastMedium)
            }
        },
        failure: {
          Rectangle()
            .fill(theme.atomColors.bgContrast100)
            .overlay {
              Image(systemName: "play.slash")
                .foregroundStyle(theme.atomColors.textContrastMedium)
            }
        })
      Image(systemName: "play.circle.fill")
        .font(.system(size: 44))
        .foregroundStyle(.white, .black.opacity(0.35))
        .shadow(radius: 4)
    }
    .aspectRatio(aspect, contentMode: .fit)
    .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    .accessibilityLabel(view.alt ?? "Video")
  }

  private var aspect: Double {
    guard let aspect = view.aspectRatio,
      let width = aspect.width, let height = aspect.height,
      width > 0, height > 0
    else { return 16.0 / 9.0 }
    return Double(width) / Double(height)
  }
}

/// The fallback for an embed variant this build does not render.
public struct UnsupportedEmbed: View {
  private let type: String

  @Environment(\.alfTheme) private var theme

  public init(type: String) {
    self.type = type
  }

  public var body: some View {
    Text("Unsupported embed")
      .font(TypeScale.sm.font())
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.md)
      .background(theme.atomColors.bgContrast25)
      .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
  }
}

/// A video embed built from the hydrated `EmbedVideo_View` in a
/// `recordWithMedia` payload. The engine's stand-in union has no video case, so
/// v1 exposes the placeholder for adapters that decode the full lexicon.
public func videoPlaceholderEmbed(thumbnail: URL?) -> some View {
  VideoPlaceholder(thumbnail: thumbnail)
}
#endif
