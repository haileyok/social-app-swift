#if canImport(SwiftUI)
import DesignSystemCore
import DesignTokens
import SwiftUI

/**
 ALF's shadow atoms as a SwiftUI modifier.

 The geometry (`radius`/`elevation`/`offset`, uniform `0.1`) comes from the
 native atoms that DesignTokens deliberately skipped; the colour comes from the
 active theme (`Theme.shadowOpacity` over the palette black). The two opacities
 multiply, matching the RN app.

 ```swift
 card.alfShadow(.md)
 ```
 */
extension View {
  /** Applies an ALF shadow step using the theme in the environment. */
  public func alfShadow(_ size: ShadowGeometry.Size) -> some View {
    modifier(AlfShadowModifier(size: size))
  }
}

struct AlfShadowModifier: ViewModifier {
  let size: ShadowGeometry.Size

  @Environment(\.alfTheme) private var theme

  func body(content: Content) -> some View {
    let resolved = ResolvedShadow.resolve(size, themeShadowOpacity: theme.shadowOpacity)
    return content.shadow(
      color: Color(.sRGB, red: 0, green: 0, blue: 0, opacity: resolved.alpha),
      radius: resolved.radius,
      x: resolved.offsetX,
      y: resolved.offsetY)
  }
}

extension Theme {
  /**
   The resolved shadow for a step, for callers that need the numbers (the
   gallery prints them; a future elevation-aware component may too).
   */
  public func shadow(_ size: ShadowGeometry.Size) -> ResolvedShadow {
    ResolvedShadow.resolve(size, themeShadowOpacity: shadowOpacity)
  }
}
#endif
