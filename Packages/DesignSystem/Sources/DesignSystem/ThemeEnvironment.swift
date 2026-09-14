#if canImport(SwiftUI)
import DesignSystemCore
import DesignTokens
import SwiftUI

/**
 Theme injection and read-back, the SwiftUI stand-in for ALF's
 `ThemeProvider` / `useTheme()` pair.

 A consumer writes:

 ```swift
 MyView()
   .theme(.dim)            // or .theme(.system) to follow the OS
 ```

 and reads the active theme with `@Environment(\.alfTheme)`:

 ```swift
 @Environment(\.alfTheme) private var t
 ...
 .background(t.atomColors.bg)
 ```
 */
private struct AlfThemeKey: EnvironmentKey {
  static let defaultValue: Theme = .light
}

private struct AlfFontFamilyKey: EnvironmentKey {
  static let defaultValue: FontFamilyPreference = .theme
}

private struct AlfFontScaleKey: EnvironmentKey {
  static let defaultValue: Double = 1
}

extension EnvironmentValues {
  /** The active ALF theme. Defaults to `Theme.light` outside a `.theme(...)`. */
  public var alfTheme: Theme {
    get { self[AlfThemeKey.self] }
    set { self[AlfThemeKey.self] = newValue }
  }

  /** The active font family preference (`theme` = Inter, `system`). */
  public var alfFontFamily: FontFamilyPreference {
    get { self[AlfFontFamilyKey.self] }
    set { self[AlfFontFamilyKey.self] = newValue }
  }

  /** The user font-scale multiplier (`FontScale.multiplier(for:)`). */
  public var alfFontScale: Double {
    get { self[AlfFontScaleKey.self] }
    set { self[AlfFontScaleKey.self] = newValue }
  }
}

extension View {
  /** Injects a theme by name, e.g. `.theme(.dim)`. */
  public func theme(_ name: ThemeName) -> some View {
    environment(\.alfTheme, ThemeResolver.theme(for: name))
  }

  /** Injects an already-resolved theme. */
  public func theme(_ theme: Theme) -> some View {
    environment(\.alfTheme, theme)
  }

  /**
   Injects a theme by preference. `.system` follows `\.colorScheme`, so the view
   re-resolves whenever the OS appearance changes - this is the runtime-switch
   path (light <-> dark) and it needs no state of its own.
   */
  public func theme(_ preference: ThemePreference) -> some View {
    modifier(ThemePreferenceModifier(preference: preference))
  }

  /** Applies the user's font family and font-scale preferences. */
  public func fontPreferences(
    family: FontFamilyPreference, scale: Double
  ) -> some View {
    environment(\.alfFontFamily, family)
      .environment(\.alfFontScale, scale)
  }

  /** Applies a `FontScale.Step` as the font-scale multiplier. */
  public func fontScale(_ step: FontScale.Step) -> some View {
    environment(\.alfFontScale, FontScale.multiplier(for: step))
  }
}

/**
 Resolves a `ThemePreference` against the current appearance. Kept as a
 `ViewModifier` so the modifier body itself reads `\.colorScheme`, which makes
 SwiftUI re-evaluate on appearance change.
 */
struct ThemePreferenceModifier: ViewModifier {
  let preference: ThemePreference

  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content.environment(
      \.alfTheme,
      ThemeResolver.resolve(preference: preference, systemScheme: scheme))
  }

  private var scheme: ThemeScheme {
    colorScheme == .dark ? .dark : .light
  }
}
#endif
