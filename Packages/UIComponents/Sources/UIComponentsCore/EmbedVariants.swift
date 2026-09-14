import Foundation
import Moderation

/// The v1 embed matrix, as data.
///
/// The RN app has one component per hydrated embed variant and a switch to pick
/// between them (`src/components/Post/Embed/`). This port keeps the switch in
/// the pure core so the dispatch table can be tested without a view hierarchy,
/// and so the SwiftUI layer is a set of small, dumb views keyed by
/// ``EmbedVariant``.
public enum EmbedVariant: String, Sendable, CaseIterable {
  /// `app.bsky.embed.images#view` - the image gallery.
  case images
  /// `app.bsky.embed.external#view` - the link card.
  case external
  /// `app.bsky.embed.record#view` - the quoted post.
  case record
  /// `app.bsky.embed.recordWithMedia#view` - quoted post plus media.
  case recordWithMedia
  /// `app.bsky.embed.gallery#view` - the newer multi-image gallery.
  case gallery
  /// `app.bsky.embed.video#view` - video. v1 renders a placeholder.
  case video
  /// A variant this build does not know how to render.
  case unsupported
}

/// What the embed layer needs to know about a hydrated embed, lifted out of the
/// lexicon union so views and tests share one shape.
public struct EmbedVariantInfo: Equatable, Sendable {
  public let variant: EmbedVariant
  /// Number of images in an `images`/`gallery` embed; 0 otherwise.
  public let imageCount: Int
  /// Whether this variant has media that needs its own moderation surface
  /// (`contentMedia`), separate from the post body (`contentList`).
  public let hasMedia: Bool
  /// Whether this variant nests another post, which is moderated by the
  /// *quoting* post's decision rather than its own.
  public let hasQuotedPost: Bool
  /// Whether the media is a video (placeholder in v1).
  public let isVideo: Bool

  public init(
    variant: EmbedVariant,
    imageCount: Int = 0,
    hasMedia: Bool = false,
    hasQuotedPost: Bool = false,
    isVideo: Bool = false
  ) {
    self.variant = variant
    self.imageCount = imageCount
    self.hasMedia = hasMedia
    self.hasQuotedPost = hasQuotedPost
    self.isVideo = isVideo
  }
}

/// Dispatches a hydrated ``PostViewEmbed`` to its variant.
public func embedVariantInfo(_ embed: PostViewEmbed?) -> EmbedVariantInfo? {
  guard let embed else { return nil }
  switch embed {
  case .images(let images):
    return EmbedVariantInfo(
      variant: .images, imageCount: images.count, hasMedia: true)
  case .gallery(let items):
    return EmbedVariantInfo(
      variant: .gallery, imageCount: items.count, hasMedia: true)
  case .external:
    return EmbedVariantInfo(
      variant: .external, hasMedia: true)
  case .record(let record):
    // A quote with no recognisable record (blocked/not-found) still renders
    // as the record variant, with the "not available" body.
    let hasQuoted = record.record?.viewRecord != nil
    return EmbedVariantInfo(
      variant: .record, hasQuotedPost: hasQuoted)
  case .recordWithMedia(let value):
    let info = mediaInfo(value.media)
    return EmbedVariantInfo(
      variant: .recordWithMedia,
      imageCount: info.imageCount,
      hasMedia: info.hasMedia,
      hasQuotedPost: value.record?.record?.viewRecord != nil,
      isVideo: info.isVideo)
  case .unknown:
    return EmbedVariantInfo(variant: .unsupported)
  }
}

/// The `media` half of a `recordWithMedia` view.
private func mediaInfo(_ media: RecordWithMediaViewMedia?) -> (
  imageCount: Int, hasMedia: Bool, isVideo: Bool
) {
  guard let media else { return (0, false, false) }
  switch media {
  case .images(let images): return (images.count, true, false)
  case .gallery(let items): return (items.count, true, false)
  case .external: return (0, true, false)
  case .unknown: return (0, false, false)
  }
}

/// The gallery layout the RN app uses for an image embed: one image fills the
/// card, two render side by side, three or four use the 2x2 grid with the last
/// cell spanning the remainder.
public enum ImageGalleryLayout: String, Sendable, CaseIterable {
  /// A single image, full width.
  case single
  /// Two images, side by side.
  case twoUp
  /// Three images: a full-width lead plus two up.
  case threeUp
  /// Four or more images: a 2x2 grid (extras are dropped in v1).
  case grid

  /// The number of cells the layout actually renders.
  public var cellCount: Int {
    switch self {
    case .single: 1
    case .twoUp: 2
    case .threeUp: 3
    case .grid: 4
    }
  }
}

extension ImageGalleryLayout {
  /// Picks the layout for an image count, matching the RN gallery's breakpoints.
  /// Zero images is not a gallery, but callers that reach this with 0 get
  /// ``single`` so the type stays total.
  public static func forImageCount(_ count: Int) -> ImageGalleryLayout {
    switch count {
    case ..<2: .single
    case 2: .twoUp
    case 3: .threeUp
    default: .grid
    }
  }
}

/// The slice of images a layout actually shows, so views do not each re-derive
/// the "drop extras" rule.
public func galleryImages(_ images: [EmbedImage], layout: ImageGalleryLayout) -> [EmbedImage] {
  Array(images.prefix(layout.cellCount))
}

/// A URL string for an embed image, preferring the full-size render.
///
/// The hydrated image carries `image` (the view URL) in the engine's stand-in
/// type; the generated lexicon's `fullsize`/`thumb` pair is not reachable from
/// here, so a future full-lexicon adapter supplies its own.
public func embedImageURL(_ image: EmbedImage) -> URL? {
  guard let raw = image.image, !raw.isEmpty else { return nil }
  return URL(string: raw)
}
