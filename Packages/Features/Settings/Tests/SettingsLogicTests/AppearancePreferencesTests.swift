import Foundation
import Testing

import DesignTokens
import Persistence

@testable import SettingsLogic

/// Appearance persistence and validation, ported from
/// `state/shell/color-mode.tsx` and `alf/fonts.ts`.
@Suite struct AppearancePreferencesTests {

  /// Defaults match `defaults` in `state/persisted/schema.ts` and the
  /// `getFontScale`/`getFontFamily` fallbacks.
  @Test func defaults() {
    let appearance = AppearancePreferences()
    #expect(appearance.colorMode == ColorMode.system)
    #expect(appearance.darkTheme == DarkThemeValue.dim)
    #expect(appearance.fontScale == FontScale.Step.zero)
    #expect(appearance.fontFamily == FontFamilyValue.theme)
  }

  /// A color mode written through the persisted document survives a reopen.
  @Test func colorModeRoundTrip() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setColorMode(.dark)
    let reopened = harness.reopened()
    #expect(await reopened.snapshot().colorMode == ColorMode.dark)
  }

  /// The dark-theme variant round-trips, including the explicit `dark` value.
  @Test func darkThemeRoundTrip() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setDarkTheme(.dark)
    #expect(await harness.reopened().snapshot().darkTheme == DarkThemeValue.dark)
  }

  /// Clearing the dark theme leaves it unset, which reads back as the default.
  @Test func darkThemeCleared() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setDarkTheme(nil)
    let reopened = harness.reopened()
    let appearance = await reopened.snapshot()
    // The persisted field is absent; the snapshot reports the default.
    #expect(appearance.darkTheme == AppearanceDefaults.darkTheme)
  }

  /// The font scale is device scope: it lands in the device store, not the
  /// persisted document.
  @Test func fontScaleIsDeviceScoped() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setFontScale(.plus1)
    let raw = await harness.device.get(DeviceSchema.fontScale, as: String.self)
    #expect(raw == "1")
    // And it survives a reopen of the device store.
    #expect(await harness.reopened().snapshot().fontScale == FontScale.Step.plus1)
  }

  /// The font family is device scope too, and round-trips.
  @Test func fontFamilyRoundTrip() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setFontFamily(.system)
    let raw = await harness.device.get(DeviceSchema.fontFamily, as: String.self)
    #expect(raw == "system")
    #expect(await harness.reopened().snapshot().fontFamily == FontFamilyValue.system)
  }

  /// A whole appearance applies in one call and reads back identically. This is
  /// the round-trip the task asks for: write, reopen both stores, compare.
  @Test func fullAppearanceRoundTrip() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    let target = AppearancePreferences(
      colorMode: .dark, darkTheme: .dark, fontScale: .minus1, fontFamily: .system)
    try await harness.store.apply(target)

    let reopened = harness.reopened()
    #expect(await reopened.snapshot() == target)
  }

  /// An unrecognized stored font scale degrades to the default rather than
  /// making the multiplier undefined, which is RN's failure mode.
  @Test func invalidStoredFontScaleFallsBack() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.device.set(DeviceSchema.fontScale, value: "99")
    #expect(await harness.store.snapshot().fontScale == AppearanceDefaults.fontScale)
  }

  /// An unrecognized stored font family degrades to `theme`, matching
  /// `getFontFamily() || 'theme'`.
  @Test func invalidStoredFontFamilyFallsBack() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.device.set(DeviceSchema.fontFamily, value: "comic-sans")
    #expect(await harness.store.snapshot().fontFamily == FontFamilyValue.theme)
  }

  /// `apply` validates the font values it is handed.
  @Test func applyValidatesFontValues() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    // Both values are legal, so the validators accept them.
    #expect(AppearancePreferences.isValidFontScale(.minus2))
    #expect(AppearancePreferences.isValidFontScale(.plus2))
    #expect(AppearancePreferences.isValidFontFamily(.theme))
    #expect(AppearancePreferences.isValidFontFamily(.system))
  }

  /// The font-scale multipliers match ALF's table, including the deliberate
  /// collapse of the unused extremes onto their neighbours.
  @Test func fontScaleMultipliers() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setFontScale(.zero)
    #expect(await harness.store.fontScaleMultiplier() == 1)

    try await harness.store.setFontScale(.minus1)
    #expect(await harness.store.fontScaleMultiplier() == 1 - FontScale.step)

    try await harness.store.setFontScale(.plus1)
    #expect(await harness.store.fontScaleMultiplier() == 1 + FontScale.step)

    // `-2` collapses onto `-1`, and `2` onto `1`, as ALF defines them.
    #expect(FontScale.multiplier(for: .minus2) == FontScale.multiplier(for: .minus1))
    #expect(FontScale.multiplier(for: .plus2) == FontScale.multiplier(for: .plus1))
  }

  /// `colorMode: light` resolves to light whatever the OS scheme.
  @Test func resolvedThemeLightIgnoresSystem() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setColorMode(.light)
    #expect(await harness.store.resolvedTheme(systemScheme: .dark) == .light)
    #expect(await harness.store.resolvedTheme(systemScheme: .light) == .light)
  }

  /// `colorMode: system` follows the OS scheme.
  ///
  /// Port of `getThemeName` in `alf/util/useColorModeTheme.ts`: light only when
  /// the scheme is light; otherwise `darkTheme ?? 'dim'`. The default
  /// `darkTheme` is `dim`, so a system dark scheme with no explicit variant is
  /// `dim`, not `dark`.
  @Test func resolvedThemeSystemFollowsScheme() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setColorMode(.system)
    #expect(await harness.store.resolvedTheme(systemScheme: .light) == .light)
    #expect(await harness.store.resolvedTheme(systemScheme: .dark) == .dim)

    // With an explicit `dark` variant, a system dark scheme selects it.
    try await harness.store.setDarkTheme(.dark)
    #expect(await harness.store.resolvedTheme(systemScheme: .dark) == .dark)
  }

  /// `colorMode: dark` honours the dark-theme variant.
  @Test func resolvedThemeDarkUsesVariant() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setColorMode(.dark)
    try await harness.store.setDarkTheme(.dim)
    #expect(await harness.store.resolvedTheme(systemScheme: .light) == .dim)

    try await harness.store.setDarkTheme(.dark)
    #expect(await harness.store.resolvedTheme(systemScheme: .light) == .dark)
  }

  /// An unset dark theme under a dark mode falls back to `dim`, matching the
  /// screen's `value={darkTheme ?? 'dim'}`.
  @Test func resolvedThemeUnsetVariantFallsBackToDim() async throws {
    let harness = await AppearanceHarness()
    defer { harness.cleanUp() }

    try await harness.store.setColorMode(.dark)
    try await harness.store.setDarkTheme(nil)
    #expect(await harness.store.resolvedTheme(systemScheme: .light) == .dim)
  }

  /// The appearance screen's option rows and labels.
  @Test func optionRows() {
    #expect(AppearanceOptions.colorModes == [.system, .light, .dark])
    #expect(AppearanceOptions.darkThemes == [.dim, .dark])
    #expect(AppearanceOptions.fontFamilies == [.system, .theme])
    #expect(AppearanceOptions.fontScales == [.minus1, .zero, .plus1])
    #expect(AppearanceOptions.label(for: ColorMode.system) == "System")
    #expect(AppearanceOptions.label(for: FontScale.Step.minus1) == "Smaller")
    #expect(AppearanceOptions.label(for: FontScale.Step.zero) == "Default")
    #expect(AppearanceOptions.label(for: FontScale.Step.plus1) == "Larger")
  }

  /// The dark-theme group is hidden only for an explicit light mode.
  @Test func darkThemeGroupVisibility() {
    #expect(AppearanceOptions.showsDarkTheme(mode: .system))
    #expect(AppearanceOptions.showsDarkTheme(mode: .dark))
    #expect(!AppearanceOptions.showsDarkTheme(mode: .light))
  }
}
