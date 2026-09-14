import Foundation

/// Where an in-flight image is in its lifecycle.
public enum ImageLoadPhase: Equatable, Sendable {
  case idle
  case loading
  case loaded
  case failed

  /// True while a placeholder should stand in for the real image.
  public var isPlaceholder: Bool {
    self != .loaded
  }
}

/// A byte-level image source.
///
/// The component library does not ship an image loader: the app owns its cache,
/// its request stack and its downsampling pipeline, and a package that imported
/// a third-party one would force that choice on every consumer. Instead the
/// views take an ``ImageLoading`` and a URL, and the app supplies an
/// implementation. The protocol is deliberately byte-level so a test double is
/// trivial and the app is free to downsample before handing the data back.
public protocol ImageLoading: Sendable {
  /// Fetches the bytes behind `url`.
  ///
  /// - Parameter targetSize: the point size the image will be displayed at, so
  ///   an implementation can downsample rather than decode full-resolution
  ///   bytes. `nil` means "no size hint".
  func loadImage(at url: URL, targetSize: ImageTargetSize?) async throws -> Data
}

/// A display-size hint, in points, for downsampling.
public struct ImageTargetSize: Equatable, Sendable {
  public let width: Double
  public let height: Double
  /// The display scale, so a 2x screen asks for 2x pixels.
  public let scale: Double

  public init(width: Double, height: Double, scale: Double = 2) {
    self.width = width
    self.height = height
    self.scale = scale
  }

  /// The pixel size to decode at.
  public var pixelSize: (width: Double, height: Double) {
    (width * scale, height * scale)
  }
}

/// A stable in-memory cache key for one image request.
///
/// The app's loader owns the real cache; this type exists so the *key* is
/// derived in one place and two views asking for the same asset agree.
public struct ImageCacheKey: Hashable, Sendable {
  public let url: URL
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(url: URL, targetSize: ImageTargetSize?) {
    self.url = url
    if let targetSize {
      let pixels = targetSize.pixelSize
      // Rounding keeps a 132.0pt request and a 131.9pt request on one key.
      self.pixelWidth = Int(pixels.width.rounded())
      self.pixelHeight = Int(pixels.height.rounded())
    } else {
      self.pixelWidth = 0
      self.pixelHeight = 0
    }
  }
}

/// The outcome of resolving an avatar URL, shared by the avatar and banner
/// views so both apply the same "is there anything to load" rule.
public enum AvatarSource: Equatable, Sendable {
  /// No avatar on the profile: render the initials/placeholder.
  case placeholder(String)
  case remote(URL)

  /// Resolves a profile's avatar plus display name into a source.
  public static func resolve(
    avatar: String?, handle: String, displayName: String?
  ) -> AvatarSource {
    if let avatar, !avatar.isEmpty, let url = URL(string: avatar) {
      return .remote(url)
    }
    let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let seed = (name?.isEmpty == false ? name! : handle)
    return .placeholder(seed)
  }
}

/// The initials an avatar placeholder shows, derived the way the RN fallbacks do
/// (first grapheme of the name, falling back to the first of the handle).
public func avatarInitials(_ seed: String) -> String {
  let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
  guard let first = trimmed.first else { return "?" }
  return String(first).uppercased()
}

/// The avatar size ladder from the RN app's avatar styles.
public enum AvatarSize: String, Sendable, CaseIterable {
  case xs
  case sm
  case md
  case lg
  case xl

  /// The rendered side in points.
  public var side: Double {
    switch self {
    case .xs: 20
    case .sm: 32
    case .md: 40
    case .lg: 56
    case .xl: 84
    }
  }
}

/// The banner aspect ratio the RN profile banner uses (about 3:1).
public enum BannerGeometry {
  public static let aspectRatio: Double = 3
  public static let defaultHeight: Double = 100
}

/// A loader that produces no bytes.
///
/// The library ships no image stack: the app owns its cache, request policy and
/// downsampling. This default lets a component render without wiring (and lets
/// the gallery and previews run without a session), and the app installs its
/// real loader with `.imageLoader(_:)`.
public struct PlaceholderImageLoader: ImageLoading {
  public init() {}

  /// Always reports "no image", so the placeholder path is exercised.
  public func loadImage(at url: URL, targetSize: ImageTargetSize?) async throws -> Data {
    throw ImageLoaderError.placeholderOnly
  }
}

/// Why an image could not be produced.
public enum ImageLoaderError: Error, Equatable {
  /// The placeholder loader was asked for real bytes.
  case placeholderOnly
  /// The response was not an image, or the bytes could not be decoded.
  case undecodable
}
