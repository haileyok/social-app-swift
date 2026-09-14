#if canImport(SwiftUI)
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponentsCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Resolves a core ``ColorToken`` against the active theme.
///
/// The core names tokens as strings so the button matrix can be tested without
/// SwiftUI; this is the one place that turns a name into a `Color`.
extension ColorToken {
  func resolve(_ theme: DesignTokens.Theme) -> Color {
    switch self {
    case .palette(let name):
      theme.colors[name]
    case .atom(let name):
      AtomColorLookup.color(named: name, in: theme)
    }
  }
}

/// Name lookup for the handful of ALF atoms the components use.
///
/// `AtomColors` has typed fields, not a subscript, so the mapping is explicit
/// and total over the names the matrix emits. An unknown name renders clear,
/// matching ``PaletteColors/subscript(name:)``.
enum AtomColorLookup {
  static func color(named name: String, in theme: DesignTokens.Theme) -> Color {
    let atoms = theme.atomColors
    if let text = textColor(named: name, atoms: atoms) { return text }
    if let background = backgroundColor(named: name, atoms: atoms) { return background }
    return borderColor(named: name, atoms: atoms) ?? .clear
  }

  private static func textColor(named name: String, atoms: AtomColors) -> Color? {
    switch name {
    case "text": atoms.text
    case "textLink": atoms.textLink
    case "textContrastLow": atoms.textContrastLow
    case "textContrastMedium": atoms.textContrastMedium
    case "textContrastHigh": atoms.textContrastHigh
    case "textInverted": atoms.textInverted
    default: nil
    }
  }

  private static func backgroundColor(named name: String, atoms: AtomColors) -> Color? {
    switch name {
    case "bg": atoms.bg
    case "bgContrast25": atoms.bgContrast25
    case "bgContrast50": atoms.bgContrast50
    case "bgContrast100": atoms.bgContrast100
    case "bgContrast200": atoms.bgContrast200
    case "bgContrast300": atoms.bgContrast300
    case "bgContrast400": atoms.bgContrast400
    case "bgContrast500": atoms.bgContrast500
    case "bgContrast600": atoms.bgContrast600
    case "bgContrast700": atoms.bgContrast700
    case "bgContrast800": atoms.bgContrast800
    case "bgContrast900": atoms.bgContrast900
    case "bgContrast950": atoms.bgContrast950
    case "bgContrast975": atoms.bgContrast975
    default: nil
    }
  }

  private static func borderColor(named name: String, atoms: AtomColors) -> Color? {
    switch name {
    case "borderContrastLow": atoms.borderContrastLow
    case "borderContrastMedium": atoms.borderContrastMedium
    case "borderContrastHigh": atoms.borderContrastHigh
    default: nil
    }
  }
}

extension TextScaleName {
  /// The DesignSystem type step for this name.
  var typeScale: TypeScale {
    switch self {
    case .xxs: .xxs
    case .xs: .xs
    case .sm: .sm
    case .md: .md
    case .lg: .lg
    case .xl: .xl
    case .xxl: .xxl
    case .xxxl: .xxxl
    case .xxxxl: .xxxxl
    case .xxxxxl: .xxxxxl
    }
  }
}

/// Supplies the app's image loader to the component tree.
///
/// The library ships ``PlaceholderImageLoader`` so a gallery or avatar renders
/// something sensible with no wiring; the app installs its real loader once, at
/// the root:
///
/// ```swift
/// MyView().imageLoader(AppImageLoader())
/// ```
struct ImageLoaderKey: EnvironmentKey {
  static let defaultValue: any ImageLoading = PlaceholderImageLoader()
}

extension EnvironmentValues {
  /// The image loader used by avatars, banners and embed media.
  public var imageLoader: any ImageLoading {
    get { self[ImageLoaderKey.self] }
    set { self[ImageLoaderKey.self] = newValue }
  }
}

extension View {
  /// Installs the image loader used by every component below this view.
  public func imageLoader(_ loader: any ImageLoading) -> some View {
    environment(\.imageLoader, loader)
  }
}

/// A loader that renders a flat placeholder for every request.
///
/// It exists so the package has no required dependency on any networking or
/// caching stack, and so the gallery renders without a session. It never
/// produces bytes, which keeps the placeholder path exercised in previews.
///
/// Types are in ``ImageLoading.swift`` (the pure core); this is the SwiftUI
/// layer's re-export so a caller only imports `UIComponents`.
public typealias PlaceholderImageLoader = UIComponentsCore.PlaceholderImageLoader

/// Why an image could not be produced.
public typealias ImageLoaderError = UIComponentsCore.ImageLoaderError

/// Loads and renders a remote image at a downsampling-friendly target size.
///
/// The view owns only the load lifecycle: it asks the injected
/// ``ImageLoading`` for bytes and decodes them. Caching, retries and
/// prioritisation belong to the loader, so there is exactly one place to change
/// them.
public struct RemoteImage<Placeholder: View, Failure: View>: View {
  private let url: URL?
  private let targetSize: ImageTargetSize?
  private let contentMode: ContentMode
  private let placeholder: () -> Placeholder
  private let failure: () -> Failure

  @Environment(\.imageLoader) private var loader
  @State private var phase: ImageLoadPhase = .idle
  @State private var image: PlatformImage?

  /**
   - Parameters:
     - url: the image location. `nil` renders the placeholder immediately.
     - targetSize: the display size, so the loader can downsample.
     - contentMode: `.fill` for avatars and media, `.fit` for banners.
   */
  public init(
    url: URL?,
    targetSize: ImageTargetSize? = nil,
    contentMode: ContentMode = .fill,
    @ViewBuilder placeholder: @escaping () -> Placeholder,
    @ViewBuilder failure: @escaping () -> Failure
  ) {
    self.url = url
    self.targetSize = targetSize
    self.contentMode = contentMode
    self.placeholder = placeholder
    self.failure = failure
  }

  public var body: some View {
    ZStack {
      switch phase {
      case .idle, .loading:
        placeholder()
      case .loaded:
        if let image {
          PlatformImageView(image: image, contentMode: contentMode)
        } else {
          failure()
        }
      case .failed:
        failure()
      }
    }
    .task(id: cacheKey) {
      await load()
    }
  }

  /// A task identity that only changes when the request changes, so scrolling a
  /// list does not restart an in-flight load.
  private var cacheKey: ImageCacheKey? {
    guard let url else { return nil }
    return ImageCacheKey(url: url, targetSize: targetSize)
  }

  private func load() async {
    guard let url else {
      phase = .failed
      return
    }
    phase = .loading
    do {
      let data = try await loader.loadImage(at: url, targetSize: targetSize)
      guard let decoded = PlatformImage(data: data) else {
        phase = .failed
        return
      }
      image = decoded
      phase = .loaded
    } catch {
      phase = .failed
    }
  }
}

extension RemoteImage where Failure == EmptyView {
  /// Convenience for callers whose failure state is the placeholder.
  public init(
    url: URL?,
    targetSize: ImageTargetSize? = nil,
    contentMode: ContentMode = .fill,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.init(
      url: url,
      targetSize: targetSize,
      contentMode: contentMode,
      placeholder: placeholder,
      failure: { EmptyView() })
  }
}

/// The platform image type, so the views stay one implementation.
#if canImport(UIKit)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
public typealias PlatformImage = NSImage
#endif

/// Renders a decoded platform image with a content mode.
struct PlatformImageView: View {
  let image: PlatformImage
  let contentMode: ContentMode

  var body: some View {
    #if canImport(UIKit)
    Image(uiImage: image)
      .resizable()
      .aspectRatio(contentMode: contentMode)
    #elseif canImport(AppKit)
    Image(nsImage: image)
      .resizable()
      .aspectRatio(contentMode: contentMode)
    #endif
  }
}
#endif
