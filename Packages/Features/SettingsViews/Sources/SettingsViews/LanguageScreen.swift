import DesignSystem
import DesignSystemCore
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The language screen: the UI language, the translate target, and the content
/// languages.
///
/// The pickers read the tables in ``Languages``: ``Languages/appLanguages`` for
/// the UI language and the ``LanguagePreferences/possibleContentLanguages()``
/// ordering for the content languages. The sanitizer
/// (``LanguageRules/sanitizeAppLanguageSetting(_:)``) runs on every UI-language
/// write, so a legacy comma-separated value is repaired rather than rejected.
///
/// Ported from `screens/Settings/LanguageSettings.tsx`.
public struct LanguageScreen: View {
  let viewModel: SettingsViewModel

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  private var languages: LanguagePreferences { viewModel.state.languages }

  public var body: some View {
    Form {
      uiLanguageSection
      primaryLanguageSection
      contentLanguagesSection
    }
    .navigationTitle(SettingsRoute.language.title)
    .accessibilityIdentifier(SettingsAccessibility.language)
    .overlay(alignment: .bottom) { banners }
  }

  // MARK: - Sections

  private var uiLanguageSection: some View {
    Section {
      Picker(
        "App language",
        selection: Binding(
          get: { LanguageRules.sanitizeAppLanguageSetting(languages.appLanguage) },
          set: { viewModel.setAppLanguage($0) })
      ) {
        ForEach(Languages.appLanguages, id: \.code2) { language in
          Text(language.name).tag(language.code2)
        }
      }
      .accessibilityIdentifier(SettingsAccessibility.appLanguagePicker)
    } header: {
      Text("App language")
    } footer: {
      Text("The language Bluesky's interface is shown in.")
    }
  }

  private var primaryLanguageSection: some View {
    Section {
      Picker(
        "Translation language",
        selection: Binding(
          get: { languages.primaryLanguage },
          set: { viewModel.setPrimaryLanguage($0) })
      ) {
        ForEach(Languages.languages, id: \.code2) { language in
          Text(language.name).tag(language.code2)
        }
      }
      .accessibilityIdentifier(SettingsAccessibility.primaryLanguagePicker)
    } header: {
      Text("Translation")
    } footer: {
      Text("Posts in other languages are translated into this one.")
    }
  }

  private var contentLanguagesSection: some View {
    Section {
      ForEach(languages.possibleContentLanguages(), id: \.code2) { language in
        Button {
          viewModel.toggleContentLanguage(language.code2)
        } label: {
          HStack(spacing: Spacing.sm) {
            AlfText(language.name, scale: .md)
            Spacer(minLength: Spacing.sm)
            if languages.contentLanguages.contains(language.code2) {
              Image(systemName: "checkmark")
                .foregroundStyle(theme.colors.primary500)
                .accessibilityHidden(true)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    } header: {
      Text("Content languages")
    } footer: {
      Text("Feeds use these languages to decide what to show you.")
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

#Preview {
  NavigationStack {
    LanguageScreen(viewModel: .fixture())
  }
  .theme(ThemePreference.light)
}
