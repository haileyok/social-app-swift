/**
 The platform shadow geometry ALF's native atoms carry, which DesignTokens
 deliberately skipped (it records the colour and the web `boxShadow` string).

 Transcribed 1:1 from `@bsky.app/alf@0.1.15` `src/atoms/index.native.ts`. ALF
 applies the same `shadowOpacity: 0.1` to every step; the theme's shadow colour
 carries the real opacity (`0.1` for light, `0.4` for dark and dim), so the two
 multiply when a shadow is drawn. The values are kept here, free of any UI
 framework, so they are verifiable on Linux and can be exercised by the SwiftUI
 modifier without a Mac.
 */
public struct ShadowGeometry: Equatable, Sendable {
  /** `shadowRadius`, in points. */
  public let radius: Double
  /** Android `elevation`, in dp; exposed for completeness, unused on iOS. */
  public let elevation: Double
  /** `shadowOffset.width`, in points. */
  public let offsetX: Double
  /** `shadowOffset.height`, in points. */
  public let offsetY: Double
  /** ALF's uniform `shadowOpacity` for this step. */
  public let opacity: Double

  public init(radius: Double, elevation: Double, offsetX: Double, offsetY: Double, opacity: Double) {
    self.radius = radius
    self.elevation = elevation
    self.offsetX = offsetX
    self.offsetY = offsetY
    self.opacity = opacity
  }
}

extension ShadowGeometry {
  /** The five ALF shadow atoms, `shadow_xs`..`shadow_xl`. */
  public static let xs = ShadowGeometry(
    radius: 8, elevation: 4, offsetX: 0, offsetY: 2, opacity: 0.1)
  public static let sm = ShadowGeometry(
    radius: 4, elevation: 8, offsetX: 0, offsetY: 4, opacity: 0.1)
  public static let md = ShadowGeometry(
    radius: 8, elevation: 16, offsetX: 0, offsetY: 8, opacity: 0.1)
  public static let lg = ShadowGeometry(
    radius: 16, elevation: 32, offsetX: 0, offsetY: 16, opacity: 0.1)
  public static let xl = ShadowGeometry(
    radius: 40, elevation: 48, offsetX: 0, offsetY: 10, opacity: 0.1)

  /** The size steps of the atom, matching ALF's `shadow_*` names. */
  public enum Size: String, Equatable, Sendable, CaseIterable {
    case xs
    case sm
    case md
    case lg
    case xl
  }

  /** Resolves a geometry step by name. */
  public static func `for`(_ size: Size) -> ShadowGeometry {
    switch size {
    case .xs: xs
    case .sm: sm
    case .md: md
    case .lg: lg
    case .xl: xl
    }
  }
}

/**
 A fully resolved shadow: geometry plus the effective colour alpha.

 ALF's `Shadow.color` is always plain `#000000`; the theme carries the opacity
 (`Theme.shadowOpacity`), and the atom adds its own `0.1`. The two multiply.
 */
public struct ResolvedShadow: Equatable, Sendable {
  public let radius: Double
  public let offsetX: Double
  public let offsetY: Double
  /** `themeShadowOpacity * geometryOpacity`. */
  public let alpha: Double

  public init(radius: Double, offsetX: Double, offsetY: Double, alpha: Double) {
    self.radius = radius
    self.offsetX = offsetX
    self.offsetY = offsetY
    self.alpha = alpha
  }

  /**
   Combines an ALF shadow atom with the active theme's shadow opacity, matching
   what the RN app draws: black at `themeOpacity * atomOpacity`.
   */
  public static func resolve(
    _ size: ShadowGeometry.Size, themeShadowOpacity: Double
  ) -> ResolvedShadow {
    let geometry = ShadowGeometry.for(size)
    return ResolvedShadow(
      radius: geometry.radius,
      offsetX: geometry.offsetX,
      offsetY: geometry.offsetY,
      alpha: themeShadowOpacity * geometry.opacity)
  }
}
