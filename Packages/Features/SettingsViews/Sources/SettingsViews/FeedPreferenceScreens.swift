import DesignSystem
import DesignSystemCore
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The following-feed preferences screen.
///
/// The four toggles come from ``FollowingFeedPreferences/fields`` and speak
/// *show* semantics; the store negates them before writing. The experimental
/// toggle is rendered in its own group, matching the RN screen.
///
/// Ported from `screens/Settings/FollowingFeedPreferences.tsx`.
public struct FollowingFeedPreferencesScreen: View {
  let viewModel: SettingsViewModel

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  private var preferences: FollowingFeedPreferences { viewModel.state.followingFeed }

  private var standardFields: [FollowingFeedPreferences.Field] {
    FollowingFeedPreferences.fields.filter { !$0.isExperimental }
  }

  private var experimentalFields: [FollowingFeedPreferences.Field] {
    FollowingFeedPreferences.fields.filter(\.isExperimental)
  }

  public var body: some View {
    Form {
      Section {
        ForEach(standardFields, id: \.rawValue) { field in
          toggle(field)
        }
      } footer: {
        Text("These preferences apply to your Following feed only.")
      }

      if !experimentalFields.isEmpty {
        Section {
          ForEach(experimentalFields, id: \.rawValue) { field in
            toggle(field)
          }
        } header: {
          Text("Experimental")
        }
      }
    }
    .navigationTitle(SettingsRoute.followingFeedPreferences.title)
    .accessibilityIdentifier(SettingsAccessibility.followingFeed)
    .overlay(alignment: .bottom) { banners }
  }

  private func toggle(_ field: FollowingFeedPreferences.Field) -> some View {
    Toggle(
      field.title,
      isOn: Binding(
        get: { preferences.value(of: field) },
        set: { value in
          Task { await viewModel.setFollowingFeed(field, value: value) }
        })
    )
    .accessibilityIdentifier(SettingsAccessibility.followingFeedToggle(field.rawValue))
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

/// The thread preferences screen: the reply sort and the tree view.
///
/// Ported from `screens/Settings/ThreadPreferences.tsx`; the sort option labels
/// come from ``ThreadSortOption/title``.
public struct ThreadPreferencesScreen: View {
  let viewModel: SettingsViewModel

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  private var preferences: ThreadPreferences { viewModel.state.threads }

  public var body: some View {
    Form {
      Section {
        Picker(
          "Sort replies",
          selection: Binding(
            get: { preferences.sort.rawValue },
            set: { raw in
              var updated = preferences
              updated.sort = ThreadPreferences.normalizeSort(raw)
              Task { await viewModel.setThreadPreferences(updated) }
            })
        ) {
          ForEach(ThreadSortOption.allCases, id: \.rawValue) { option in
            Text(option.title).tag(option.rawValue)
          }
        }
        .accessibilityIdentifier(SettingsAccessibility.threadSortPicker)
      } header: {
        Text("Replies")
      }

      Section {
        Toggle(
          "Tree view",
          isOn: Binding(
            get: { preferences.view == .tree },
            set: { enabled in
              var updated = preferences
              updated.view = ThreadPreferences.normalizeView(treeViewEnabled: enabled)
              Task { await viewModel.setThreadPreferences(updated) }
            })
        )
        .accessibilityIdentifier(SettingsAccessibility.threadTreeViewToggle)
      } header: {
        Text("Experimental")
      } footer: {
        Text("Show replies as a tree branching from the post.")
      }
    }
    .navigationTitle(SettingsRoute.threads.title)
    .accessibilityIdentifier(SettingsAccessibility.threads)
    .overlay(alignment: .bottom) { banners }
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
    FollowingFeedPreferencesScreen(viewModel: .fixture())
  }
  .theme(ThemePreference.light)
}
