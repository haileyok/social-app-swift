import DesignSystem
import DesignSystemCore
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The saved-feeds editor: reorder, pin, unpin, remove, and save.
///
/// RN holds an editing copy of the list and writes once on "Save changes"; the
/// edits here go through ``SettingsViewModel/editSavedFeeds(_:)``, which is the
/// same working-copy model, and the single write is
/// ``SettingsViewModel/saveSavedFeeds()``. The reorder controls are the pinned
/// block's move-up/move-down, which map onto
/// ``SavedFeedsEditor/movePinnedUp(at:)`` and
/// ``SavedFeedsEditor/movePinnedDown(at:)``.
///
/// Ported from `screens/SavedFeeds.tsx`.
public struct SavedFeedsScreen: View {
  let viewModel: SettingsViewModel

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  private var editor: SavedFeedsEditor { viewModel.state.savedFeeds }

  public var body: some View {
    List {
      pinnedSection
      unpinnedSection
    }
    .listStyle(.insetGrouped)
    .navigationTitle(SettingsRoute.savedFeeds.title)
    .accessibilityIdentifier(SettingsAccessibility.savedFeeds)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Save changes") {
          Task { await viewModel.saveSavedFeeds() }
        }
        .disabled(!editor.hasUnsavedChanges)
        .accessibilityIdentifier(SettingsAccessibility.savedFeedsSaveButton)
      }
    }
    .overlay(alignment: .bottom) { banners }
  }

  // MARK: - Sections

  private var pinnedSection: some View {
    Section {
      if editor.pinned.isEmpty {
        AlfText(
          "Pin a feed to show it as a tab.", scale: .sm,
          color: theme.atomColors.textContrastMedium)
      } else {
        ForEach(Array(editor.pinned.enumerated()), id: \.element.id) { index, item in
          pinnedRow(item, index: index)
        }
      }
    } header: {
      Text("Pinned")
    } footer: {
      Text("Pinned feeds appear as tabs on your home screen.")
    }
  }

  private var unpinnedSection: some View {
    Section {
      if editor.unpinned.isEmpty {
        AlfText(
          "No unpinned feeds.", scale: .sm, color: theme.atomColors.textContrastMedium)
      } else {
        ForEach(editor.unpinned, id: \.id) { item in
          unpinnedRow(item)
        }
      }
      if editor.isEmpty {
        Button("Add recommended feeds") {
          viewModel.addRecommendedSavedFeeds()
        }
      }
    } header: {
      Text("Saved but not pinned")
    }
  }

  // MARK: - Rows

  private func pinnedRow(_ item: SavedFeedItem, index: Int) -> some View {
    HStack(spacing: Spacing.sm) {
      feedLabel(item)
      Spacer(minLength: Spacing.sm)
      VStack(spacing: Spacing.xxs) {
        Button {
          viewModel.editSavedFeeds { $0.movePinnedUp(at: index) }
        } label: {
          Image(systemName: "chevron.up")
        }
        .buttonStyle(.plain)
        .disabled(index == 0)
        .accessibilityLabel("Move \(item.value) up")
        Button {
          viewModel.editSavedFeeds { $0.movePinnedDown(at: index) }
        } label: {
          Image(systemName: "chevron.down")
        }
        .buttonStyle(.plain)
        .disabled(index == editor.pinned.count - 1)
        .accessibilityLabel("Move \(item.value) down")
      }
      .font(.footnote)
      .foregroundStyle(theme.atomColors.textContrastMedium)

      Button {
        viewModel.editSavedFeeds { $0.togglePinned(id: item.id) }
      } label: {
        Image(systemName: item.isPinned ? "pin.fill" : "pin")
          .foregroundStyle(theme.colors.primary500)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(item.isPinned ? "Unpin \(item.value)" : "Pin \(item.value)")
      .accessibilityIdentifier(SettingsAccessibility.savedFeedPin(item.id))
    }
    .accessibilityIdentifier(SettingsAccessibility.savedFeedRow(item.id))
  }

  private func unpinnedRow(_ item: SavedFeedItem) -> some View {
    HStack(spacing: Spacing.sm) {
      feedLabel(item)
      Spacer(minLength: Spacing.sm)
      Button {
        viewModel.editSavedFeeds { $0.togglePinned(id: item.id) }
      } label: {
        Image(systemName: "pin")
          .foregroundStyle(theme.atomColors.textContrastMedium)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Pin \(item.value)")
      .accessibilityIdentifier(SettingsAccessibility.savedFeedPin(item.id))

      Button(role: .destructive) {
        viewModel.editSavedFeeds { _ = $0.remove(id: item.id) }
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(theme.colors.negative600)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Remove \(item.value)")
    }
    .accessibilityIdentifier(SettingsAccessibility.savedFeedRow(item.id))
  }

  private func feedLabel(_ item: SavedFeedItem) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      AlfText(item.value, scale: .sm)
        .lineLimit(1)
      AlfText(item.type, scale: .xs, color: theme.atomColors.textContrastMedium)
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
    SavedFeedsScreen(viewModel: .fixture())
  }
  .theme(ThemePreference.light)
}
