import Foundation

/// A single image the user has attached, before it is compressed and uploaded.
///
/// Ported from `ComposerImage` in `state/gallery`. Only the fields the composer
/// state machine reads are kept: the source dimensions and mime type (used to
/// build `aspectRatio`), the alt text, and - when editing a draft - the
/// localRef path the media was restored from.
public struct ComposerImage: Hashable, Sendable, Identifiable {
  /// A stable identity for the image within the composer session. Set from the
  /// picker or generated when a draft is hydrated.
  public var id: String
  /// A local file path or URI the image bytes can be read from.
  public var path: String
  /// The path of the transformed (compressed/edited) image, when one exists.
  /// ``sourcePath`` returns this in preference to ``path``.
  public var transformedPath: String?
  /// Source width in pixels, as reported by the picker.
  public var width: Double
  /// Source height in pixels, as reported by the picker.
  public var height: Double
  /// The image's mime type.
  public var mime: String
  /// Alt text. An empty string means "not yet described".
  public var alt: String
  /// The `localRef.path` this image came from when a draft was restored, so a
  /// re-save reuses the same ref instead of orphaning the cached file.
  public var localRefPath: String?

  public init(
    id: String,
    path: String,
    transformedPath: String? = nil,
    width: Double,
    height: Double,
    mime: String = "image/jpeg",
    alt: String = "",
    localRefPath: String? = nil
  ) {
    self.id = id
    self.path = path
    self.transformedPath = transformedPath
    self.width = width
    self.height = height
    self.mime = mime
    self.alt = alt
    self.localRefPath = localRefPath
  }

  /// The path whose bytes should be uploaded: the transformed image when it
  /// exists, otherwise the source. Matches `image.transformed?.path ||
  /// image.source.path` in `drafts/state/api.ts`.
  public var sourcePath: String { transformedPath ?? path }
}

/// Which embed variant a set of images maps to.
///
/// The RN composer models these as two struct members of a union
/// (`ImagesMedia`/`GalleryMedia`) that differ only by tag; here the tag is the
/// enum case.
public enum ImagesMedia: Hashable, Sendable {
  /// `app.bsky.embed.images` - up to ``ComposerConstants/legacyImagesEmbedMax``
  /// items.
  case images([ComposerImage])
  /// `app.bsky.embed.gallery` - more than the legacy cap.
  case gallery([ComposerImage])

  /// The attached images, whichever variant holds them.
  public var images: [ComposerImage] {
    switch self {
    case .images(let images), .gallery(let images): images
    }
  }

  /// Picks the variant for a set of images and applies the matching hard cap.
  ///
  /// Ported from `imagesToMediaVariant`. Anything beyond the gallery cap is
  /// dropped by the slice; callers are expected to have enforced the cap
  /// upstream (see ``ComposerConstants/maxGalleryImages``).
  public static func variant(for images: [ComposerImage]) -> ImagesMedia {
    if images.count <= ComposerConstants.legacyImagesEmbedMax {
      return .images(Array(images.prefix(ComposerConstants.legacyImagesEmbedMax)))
    }
    return .gallery(Array(images.prefix(ComposerConstants.maxGalleryImages)))
  }
}

/// A GIF selected from the picker, described by its resolved URL and dimensions.
///
/// The RN `Gif` type carries a Tenor media-format blob; the composer only ever
/// reads the chosen format's URL and dims, so that is what is modelled here.
public struct ComposerGif: Hashable, Sendable {
  /// The GIF's media URL.
  public var url: String
  /// Width in pixels.
  public var width: Int
  /// Height in pixels.
  public var height: Int

  public init(url: String, width: Int, height: Int) {
    self.url = url
    self.width = width
    self.height = height
  }
}

/// A GIF attachment plus its alt text.
public struct GifMedia: Hashable, Sendable {
  public var gif: ComposerGif
  public var alt: String

  public init(gif: ComposerGif, alt: String = "") {
    self.gif = gif
    self.alt = alt
  }
}

/// What media a post carries. At most one of these is ever attached.
public enum ComposerMedia: Hashable, Sendable {
  case images(ImagesMedia)
  case video(ComposerVideo)
  case gif(GifMedia)

  /// The images attached, when this is an image embed of either variant.
  public var images: [ComposerImage]? {
    if case .images(let media) = self { return media.images }
    return nil
  }
}
