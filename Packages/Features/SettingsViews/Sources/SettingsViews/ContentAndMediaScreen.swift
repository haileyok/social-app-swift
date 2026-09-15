import DesignSystem
import DesignSystemCore
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The content-and-media screen: the two preference links, the saved-feeds link,
/// the adult-content gate, and the label matrix.
///
/// Ported from `screens/Settings/ContentAndMediaSettings.tsx` plus the label list
/// in `screens/Moderation/index.tsx`. The rows themselves are derived by
/// ``LabelPreferenceMatrix``, so the screen shows exactly the permitted global
/// labels and their current visibility; when adult content is off the row set is
/// empty, which is what the matrix returns.
public struct ContentAndMediaScreen: View {
  let viewModel: SettingsViewModel

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  private var sections: [SettingsSection] { SettingsMenu.contentAndMedia }

  public var body: some View {
    Form {
      Section {
        ForEach(sections.flatMap(\.rows), id: \.self) { row in
          if let route = row.route {
            NavigationLink(value: route) {
              SettingsRowLabel(title: row.title)
            }
          }
        }
      }

      Section {
        Toggle(
          "Enable adult content",
          isOn: Binding(
            get: { viewModel.state.adultContentEnabled },
            set: { enabled in
              Task { await viewModel.setAdultContentEnabled(enabled) }
            })
        )
        .accessibilityIdentifier(SettingsAccessibility.adultContentToggle)
      } footer: {
        Text(
          "When enabled, you can choose how each content label is shown across Bluesky."
        )
      }

      if !viewModel.state.labelRows.isEmpty {
        Section {
          ForEach(viewModel.state.labelRows, id: \.identifier) { row in
            labelRow(row)
          }
        } header: {
          Text("Content labels")
        } footer: {
          Text("These settings apply everywhere you see labeled content.")
        }
      }
    }
    .navigationTitle(SettingsRoute.contentAndMedia.title)
    .accessibilityIdentifier(SettingsAccessibility.contentAndMedia)
    .overlay(alignment: .bottom) { banners }
  }

  private func labelRow(_ row: LabelPreferenceRow) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(row.name, scale: .md)
        AlfText(
          row.description, scale: .xs, color: theme.atomColors.textContrastMedium)
      }
      Picker(
        row.name,
        selection: Binding(
          get: { row.selected.rawValue },
          set: { raw in
            guard let visibility = LabelVisibility(rawValue: raw) else { return }
            Task { await viewModel.setLabelVisibility(visibility, for: row.identifier) }
          })
      ) {
        ForEach(LabelPreferenceMatrix.options, id: \.rawValue) { option in
          Text(option.title).tag(option.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(row.isDisabled)
    }
    .padding(.vertical, Spacing.xxs)
    .accessibilityIdentifier(SettingsAccessibility.labelRow(row.identifier))
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
    ContentAndMediaScreen(viewModel: .fixture())
  }
  .theme(ThemePreference.light)
}
