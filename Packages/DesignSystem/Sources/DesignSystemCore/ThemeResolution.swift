import DesignTokens

/**
 Resolves which of ALF's three themes is active from the system appearance and
 the user's theme preference.

 The RN app's preference is `ThemeName | 'system'` (`src/state/preferences/
 theme.tsx`): `system` follows the OS scheme (light -> `light`, dark -> `dark`),
 and an explicit name wins outright. This is pure, so it is tested on Linux; the
 SwiftUI layer supplies the scheme it reads from `@Environment(\.colorScheme)`.
 */
public enum ThemePreference: String, Equatable, Sendable, CaseIterable {
  case system
  case light
  case dark
  case dim
}

public enum ThemeResolver {
  /**
   The theme to render for a preference and an appearance scheme.

   `dim` is one of ALF's two dark themes; it is never selected by the system,
   only by an explicit preference.
   */
  public static func resolve(
    preference: ThemePreference, systemScheme: ThemeScheme
  ) -> Theme {
    switch preference {
    case .light: Theme.light
    case .dark: Theme.dark
    case .dim: Theme.dim
    case .system: systemScheme == .dark ? Theme.dark : Theme.light
    }
  }

  /** The theme for a resolved name, for consumers that already know it. */
  public static func theme(for name: ThemeName) -> Theme {
    Theme.all[name] ?? .light
  }
}

/**
 Which font family applies. Mirrors the RN app's `device.fontFamily`
 (`'theme'` | `'system'`), where `theme` is Inter and `system` is the platform
 UI font at the platform's native tracking.
 */
public enum FontFamilyPreference: String, Equatable, Sendable, CaseIterable {
  case theme
  case system
}
