#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponentsCore

/// A user avatar.
///
/// Renders a remote image through the injected ``ImageLoading``, falling back to
/// an initials tile. The image is requested at the avatar's display size so the
/// loader can downsample rather than decode a full-resolution upload.
///
/// ```swift
/// Avatar(source: .remote(url), size: .md)
/// ```
public struct Avatar: View {
  private let source: AvatarSource
  private let size: AvatarSize
  /// An accessibility label override. Defaults to the placeholder seed.
  private let label: String?

  @Environment(\.alfTheme) private var theme

  public init(source: AvatarSource, size: AvatarSize = .md, label: String? = nil) {
    self.source = source
    self.size = size
    self.label = label
  }

  /// Builds an avatar from a profile view's fields.
  public init(
    avatar: String?,
    handle: String,
    displayName: String? = nil,
    size: AvatarSize = .md
  ) {
    self.init(
      source: AvatarSource.resolve(avatar: avatar, handle: handle, displayName: displayName),
      size: size,
      label: displayName ?? handle)
  }

  public var body: some View {
    Group {
      switch source {
      case .placeholder(let seed):
        AvatarPlaceholder(seed: seed, size: size)
      case .remote(let url):
        RemoteImage(
          url: url,
          targetSize: ImageTargetSize(width: size.side, height: size.side),
          contentMode: .fill,
          placeholder: { AvatarPlaceholder(seed: "", size: size) }
        )
        .frame(width: size.side, height: size.side)
        .clipShape(.circle)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(label ?? "Avatar")
  }
}

/// The initials tile shown when an avatar is missing or still loading.
public struct AvatarPlaceholder: View {
  private let seed: String
  private let size: AvatarSize

  @Environment(\.alfTheme) private var theme

  public init(seed: String, size: AvatarSize = .md) {
    self.seed = seed
    self.size = size
  }

  public var body: some View {
    ZStack {
      Circle().fill(theme.atomColors.bgContrast100)
      if !seed.isEmpty {
        Text(avatarInitials(seed))
          .font(TypeScale.sm.font(weight: "600"))
          .foregroundStyle(theme.atomColors.textContrastMedium)
          .minimumScaleFactor(0.6)
          .padding(2)
      } else {
        Image(systemName: "person.fill")
          .font(.system(size: size.side * 0.5))
          .foregroundStyle(theme.atomColors.textContrastLow)
      }
    }
    .frame(width: size.side, height: size.side)
  }
}

/// A profile banner.
///
/// The banner keeps the RN app's wide aspect ratio and clips to the public
/// `banner` shape. When there is no banner image, or it is still loading, it
/// falls back to a tinted surface so the profile header keeps its geometry.
public struct Banner: View {
  private let url: URL?
  private let height: Double

  @Environment(\.alfTheme) private var theme

  public init(url: URL?, height: Double = BannerGeometry.defaultHeight) {
    self.url = url
    self.height = height
  }

  /// Builds a banner from a profile view's banner URL string.
  public init(banner: String?, height: Double = BannerGeometry.defaultHeight) {
    self.init(url: banner.flatMap { URL(string: $0) }, height: height)
  }

  public var body: some View {
    RemoteImage(
      url: url,
      targetSize: ImageTargetSize(width: 390, height: height),
      contentMode: .fill,
      placeholder: { placeholderBanner }
    )
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .background(theme.atomColors.bgContrast100)
    .accessibilityHidden(true)
  }

  private var placeholderBanner: some View {
    GradientFill(.sky) {
      Color.clear
    }
    .opacity(0.35)
  }
}
#endif
