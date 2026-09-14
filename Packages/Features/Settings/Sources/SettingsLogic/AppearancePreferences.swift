import DesignTokens
import Foundation
import Persistence

/// The device-scoped appearance preferences: theme and font.
///
/// Port of `state/shell/color-mode.tsx` and `alf/fonts.ts`. Everything here is
/// **device scope**: RN writes these to the `device` storage slot, not to the
/// account, so switching accounts does not change the theme and signing out
/// does not reset it.
///
/// The two storage layers RN uses are both reproduced:
///
/// - `colorMode` / `darkTheme` live in the persisted root document
///   (`src/state/persisted/schema.ts`), which the Swift port models as
///   ``Persistence/PersistedSchema``.
/// - `fontScale` / `fontFamily` live in the `device` key/value store
///   (`src/storage/schema.ts`), which the Swift port models as
///   ``Persistence/DeviceSchema``.
///
/// This type reads and writes both and exposes one validated snapshot, so a
/// caller cannot observe a half-applied appearance.
///
/// Both backing stores are actors, so every method here is `async`.
public struct AppearancePreferencesStore: Sendable {
  private let persisted: PersistedStore?
  private let device: Storage<DeviceSchemaMarker>?

  /// Creates a store over either backing layer, or both.
  ///
  /// A nil layer is simply not read or written; tests use whichever layer the
  /// assertion needs, and a caller that only has one storage root still works.
  public init(
    persisted: PersistedStore? = nil,
    device: Storage<DeviceSchemaMarker>? = nil
  ) {
    self.persisted = persisted
    self.device = device
  }

  /// Builds both layers under one directory, the shape the app boots with.
  public static func scoped(at directory: URL) -> AppearancePreferencesStore {
    let stores = ScopedStores(directory: directory)
    return AppearancePreferencesStore(
      persisted: PersistedStore(directory: directory), device: stores.device)
  }

  // MARK: - Read

  /// The current appearance, with every field defaulted and validated.
  public func snapshot() async -> AppearancePreferences {
    var appearance = AppearancePreferences()
    if let persisted {
      /*
       * `PersistedStore` starts at defaults and only reads the file when
       * `hydrate()` is called; the app does that at boot. Doing it here too
       * makes the store correct on its own, and it is idempotent.
       */
      let document = await persisted.hydrate()
      appearance.colorMode =
        ColorMode(rawValue: document.colorMode.rawValue) ?? AppearanceDefaults.colorMode
      if let darkTheme = document.darkTheme {
        appearance.darkTheme = DarkThemeValue(rawValue: darkTheme.rawValue)
      }
    }
    if let device {
      appearance.fontScale = await Self.readFontScale(device)
      appearance.fontFamily = await Self.readFontFamily(device)
    }
    return appearance
  }

  /// The resolved theme name for the current preference and an OS scheme.
  ///
  /// `colorMode: .system` follows the OS; `darkTheme` only matters when the
  /// resolved scheme is dark, which is exactly the RN rule (`App.tsx` picks
  /// `darkTheme` under `colorScheme === 'dark'`).
  public func resolvedTheme(systemScheme: ThemeScheme) async -> ThemeName {
    let appearance = await snapshot()
    switch appearance.colorMode {
    case .light:
      return .light
    case .dark:
      // An explicit dark mode uses the user's dark variant, defaulting to dim.
      return appearance.darkTheme == .dark ? .dark : .dim
    case .system:
      guard systemScheme == .dark else { return .light }
      return appearance.darkTheme == .dark ? .dark : .dim
    }
  }

  /// The font-scale multiplier the renderer applies.
  public func fontScaleMultiplier() async -> Double {
    FontScale.multiplier(for: await snapshot().fontScale)
  }

  // MARK: - Write

  /// Sets the color mode. Writes through to the persisted document.
  public func setColorMode(_ mode: ColorMode) async throws {
    try await persisted?.write { $0.colorMode = mode }
  }

  /// Sets the dark-mode variant.
  ///
  /// `nil` clears the field, which RN treats as "unset" and reads back as the
  /// default (`dim`).
  public func setDarkTheme(_ theme: DarkThemeValue?) async throws {
    let stored = theme.flatMap { DarkTheme(rawValue: $0.rawValue) }
    try await persisted?.write { document in
      document.darkTheme = stored
    }
  }

  /// Sets the font scale step.
  public func setFontScale(_ step: FontScale.Step) async throws {
    try await device?.set(DeviceSchema.fontScale, value: step.rawValue)
  }

  /// Sets the font family preference.
  public func setFontFamily(_ family: FontFamilyValue) async throws {
    try await device?.set(DeviceSchema.fontFamily, value: family.rawValue)
  }

  /// Applies a whole appearance in one call, for a caller restoring a saved
  /// profile. Invalid font values degrade to the defaults rather than writing
  /// something the reader would reject.
  public func apply(_ appearance: AppearancePreferences) async throws {
    let validated = AppearancePreferences(
      colorMode: appearance.colorMode,
      darkTheme: appearance.darkTheme,
      fontScale: AppearancePreferences.isValidFontScale(appearance.fontScale)
        ? appearance.fontScale : AppearanceDefaults.fontScale,
      fontFamily: AppearancePreferences.isValidFontFamily(appearance.fontFamily)
        ? appearance.fontFamily : AppearanceDefaults.fontFamily)
    try await persisted?.write { document in
      document.colorMode =
        ColorMode(rawValue: validated.colorMode.rawValue) ?? AppearanceDefaults.colorMode
      document.darkTheme = validated.darkTheme.flatMap { DarkTheme(rawValue: $0.rawValue) }
    }
    if let device {
      try await device.set(DeviceSchema.fontScale, value: validated.fontScale.rawValue)
      try await device.set(DeviceSchema.fontFamily, value: validated.fontFamily.rawValue)
    }
  }

  // MARK: - Validation

  /// Reads the persisted font scale, falling back to the default on an
  /// unrecognized value.
  ///
  /// RN reads `device.get(['fontScale']) ?? '0'` and hands the raw string to a
  /// `Record<fontScale, number>` index; an unknown value would be `undefined`.
  /// The Swift port degrades to the default instead, which keeps a bad write
  /// from blanking the app's typography.
  private static func readFontScale(
    _ device: Storage<DeviceSchemaMarker>
  ) async -> FontScale.Step {
    guard let raw = await device.get(DeviceSchema.fontScale, as: String.self),
      let step = FontScale.Step(rawValue: raw)
    else { return AppearanceDefaults.fontScale }
    return step
  }

  /// Reads the persisted font family, falling back to the default.
  ///
  /// RN's `getFontFamily()` is `device.get(['fontFamily']) || 'theme'`, so an
  /// absent value means `theme`.
  private static func readFontFamily(
    _ device: Storage<DeviceSchemaMarker>
  ) async -> FontFamilyValue {
    guard let raw = await device.get(DeviceSchema.fontFamily, as: String.self),
      let family = FontFamilyValue(rawValue: raw)
    else { return AppearanceDefaults.fontFamily }
    return family
  }
}

/// The device-scope appearance preference values, as one value type.
public struct AppearancePreferences: Sendable, Equatable {
  /// `colorMode` in the persisted document.
  public var colorMode: ColorMode
  /// `darkTheme` in the persisted document; nil means unset.
  public var darkTheme: DarkThemeValue?
  /// The `device.fontScale` step.
  public var fontScale: FontScale.Step
  /// The `device.fontFamily` choice.
  public var fontFamily: FontFamilyValue

  public init(
    colorMode: ColorMode = AppearanceDefaults.colorMode,
    darkTheme: DarkThemeValue? = AppearanceDefaults.darkTheme,
    fontScale: FontScale.Step = AppearanceDefaults.fontScale,
    fontFamily: FontFamilyValue = AppearanceDefaults.fontFamily
  ) {
    self.colorMode = colorMode
    self.darkTheme = darkTheme
    self.fontScale = fontScale
    self.fontFamily = fontFamily
  }

  /// `Device['fontScale']` is a closed set; this checks membership.
  public static func isValidFontScale(_ step: FontScale.Step) -> Bool {
    FontScale.Step.allCases.contains(step)
  }

  /// `Device['fontFamily']` is `'system' | 'theme'`.
  public static func isValidFontFamily(_ family: FontFamilyValue) -> Bool {
    FontFamilyValue.allCases.contains(family)
  }
}

/// The dark-theme variant, matching `PersistedSchema.darkTheme`.
///
/// `Persistence` already declares `DarkTheme`; this mirror exists so the
/// settings surface can name the concept without importing the storage schema
/// into every call site, and so an "unset" value is representable.
public enum DarkThemeValue: String, Sendable, CaseIterable {
  case dim
  case dark
}

/// The font-family preference, matching `Device['fontFamily']`.
///
/// Mirrors `DesignSystemCore.FontFamilyPreference`; declared here so
/// `SettingsLogic` does not depend on the SwiftUI-side package.
public enum FontFamilyValue: String, Sendable, CaseIterable {
  case system
  case theme
}

/// The defaults the appearance screens start from.
public enum AppearanceDefaults {
  /// `defaults.colorMode` in `state/persisted/schema.ts`.
  public static let colorMode: ColorMode = .system
  /// `defaults.darkTheme` in `state/persisted/schema.ts`.
  public static let darkTheme: DarkThemeValue? = .dim
  /// `getFontScale()` falls back to `'0'`.
  public static let fontScale: FontScale.Step = .zero
  /// `getFontFamily()` falls back to `'theme'`.
  public static let fontFamily: FontFamilyValue = .theme
}

/// The option rows the appearance screen renders, as data.
///
/// Port of the three `AppearanceToggleButtonGroup` calls in
/// `screens/Settings/AppearanceSettings.tsx`. The dark-theme group is
/// conditional on the color mode not being `light`, which is
/// ``AppearanceOptions/showsDarkTheme(mode:)``.
public enum AppearanceOptions {
  public static let colorModes: [ColorMode] = [.system, .light, .dark]
  public static let darkThemes: [DarkThemeValue] = [.dim, .dark]
  public static let fontFamilies: [FontFamilyValue] = [.system, .theme]
  /// The three steps the screen offers, excluding the unused `-2` and `2`.
  public static let fontScales: [FontScale.Step] = [.minus1, .zero, .plus1]

  /// The label RN renders for a color mode.
  public static func label(for mode: ColorMode) -> String {
    switch mode {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  /// The label RN renders for a dark-theme variant.
  public static func label(for theme: DarkThemeValue) -> String {
    switch theme {
    case .dim: return "Dim"
    case .dark: return "Dark"
    }
  }

  /// The label RN renders for a font family.
  public static func label(for family: FontFamilyValue) -> String {
    switch family {
    case .system: return "System"
    case .theme: return "Theme"
    }
  }

  /// The label RN renders for a font-scale step.
  public static func label(for step: FontScale.Step) -> String {
    switch step {
    case .minus2, .minus1: return "Smaller"
    case .zero: return "Default"
    case .plus1, .plus2: return "Larger"
    }
  }

  /// Whether the dark-theme group is shown for a color mode.
  public static func showsDarkTheme(mode: ColorMode) -> Bool {
    mode != .light
  }
}
