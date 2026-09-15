import DesignSystem
import DesignSystemCore
import DesignTokens
import Persistence
import SettingsLogic
import SwiftUI
import UIComponents

/// The appearance screen: theme, dark variant, font size, font family.
///
/// The theme picker drives ``ThemePreference`` (the three ALF names plus
/// `system`), which is exactly the value the app shell injects with
/// `.theme(_:)`. The screen shows its own preview card under the selected
/// preference so a change is visible here even before the shell re-themes.
///
/// Ported from `screens/Settings/AppearanceSettings.tsx`: the options and their
/// labels come from ``AppearanceOptions``, and the dark-variant group shows only
/// when the colour mode is not `light`.
public struct AppearanceSettingsScreen: View {
  let viewModel: SettingsViewModel

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  /// The colour mode a theme preference corresponds to, for the preview.
  ///
  /// `dim` and `dark` are both the `dark` colour mode; only the dark variant
  /// distinguishes them. This is the inverse of ``preference(for:)``.
  public static func preference(for appearance: AppearancePreferences) -> ThemePreference {
    switch appearance.colorMode {
    case .light: return .light
    case .dark: return appearance.darkTheme == .dark ? .dark : .dim
    case .system: return .system
    }
  }

  private var appearance: AppearancePreferences { viewModel.state.appearance }

  private var previewPreference: ThemePreference {
    AppearanceSettingsScreen.preference(for: appearance)
  }

  private var fontFamily: FontFamilyPreference {
    appearance.fontFamily == .system ? .system : .theme
  }

  public var body: some View {
    Form {
      themeSection
      previewSection
      fontSection
    }
    .navigationTitle(SettingsRoute.appearance.title)
    .accessibilityIdentifier(SettingsAccessibility.appearance)
    .overlay(alignment: .bottom) { banners }
  }

  // MARK: - Sections

  private var themeSection: some View {
    Section {
      Picker(
        "Theme",
        selection: Binding(
          get: { appearance.colorMode.rawValue },
          set: { raw in
            guard let mode = ColorMode(rawValue: raw) else { return }
            Task { await viewModel.setColorMode(mode) }
          })
      ) {
        ForEach(AppearanceOptions.colorModes, id: \.rawValue) { mode in
          Text(AppearanceOptions.label(for: mode)).tag(mode.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier(SettingsAccessibility.colorModePicker)

      if AppearanceOptions.showsDarkTheme(mode: appearance.colorMode) {
        Picker(
          "Dark theme",
          selection: Binding(
            get: { appearance.darkTheme?.rawValue ?? DarkThemeValue.dim.rawValue },
            set: { raw in
              Task { await viewModel.setDarkTheme(DarkThemeValue(rawValue: raw)) }
            })
        ) {
          ForEach(AppearanceOptions.darkThemes, id: \.rawValue) { variant in
            Text(AppearanceOptions.label(for: variant)).tag(variant.rawValue)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(SettingsAccessibility.darkThemePicker)
      }
    } header: {
      Text("Theme")
    } footer: {
      Text("System follows the device appearance.")
    }
  }

  private var previewSection: some View {
    Section("Preview") {
      ThemePreviewCard()
        .theme(previewPreference)
        .fontPreferences(
          family: fontFamily,
          scale: FontScale.multiplier(for: appearance.fontScale))
        .listRowInsets(
          EdgeInsets(
            top: Spacing.md.value, leading: Spacing.md.value,
            bottom: Spacing.md.value, trailing: Spacing.md.value))
    }
  }

  private var fontSection: some View {
    Section {
      Picker(
        "Font size",
        selection: Binding(
          get: { appearance.fontScale.rawValue },
          set: { raw in
            guard let step = FontScale.Step(rawValue: raw) else { return }
            Task { await viewModel.setFontScale(step) }
          })
      ) {
        ForEach(AppearanceOptions.fontScales, id: \.rawValue) { step in
          Text(AppearanceOptions.label(for: step)).tag(step.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier(SettingsAccessibility.fontScalePicker)

      Picker(
        "Font",
        selection: Binding(
          get: { appearance.fontFamily.rawValue },
          set: { raw in
            guard let family = FontFamilyValue(rawValue: raw) else { return }
            Task { await viewModel.setFontFamily(family) }
          })
      ) {
        ForEach(AppearanceOptions.fontFamilies, id: \.rawValue) { family in
          Text(AppearanceOptions.label(for: family)).tag(family.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier(SettingsAccessibility.fontFamilyPicker)
    } header: {
      Text("Font")
    } footer: {
      Text("Theme uses the app's Inter typeface; System uses the platform font.")
    }
  }

  @ViewBuilder
  private var banners: some View {
    VStack(spacing: Spacing.sm) {
      if let notice = viewModel.notice {
        SettingsNoticeBanner(message: notice) { viewModel.clearNotice() }
      }
      if let message = viewModel.errorMessage {
        SettingsErrorBanner(message: message) { viewModel.clearError() }
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, Spacing.lg)
  }
}

/// A sample card rendered under whichever theme preference is selected.
///
/// It reads the injected theme itself, so the `.theme(_:)` applied by the parent
/// is what colours it - the same mechanism the shell uses.
struct ThemePreviewCard: View {
  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      AlfText("Appearance preview", scale: .md, weight: Scales.FontWeight.bold)
      AlfText(
        "Sample text at the selected size.",
        scale: .sm, color: theme.atomColors.textContrastMedium)
    }
    .padding(.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.atomColors.bgContrast50)
    .cornerRadius(.md)
    .overlay(
      RoundedRectangle(cornerRadius: Radius.md)
        .stroke(theme.atomColors.borderContrastLow))
  }
}

#Preview {
  NavigationStack {
    AppearanceSettingsScreen(viewModel: .fixture())
  }
  .theme(.light)
}
