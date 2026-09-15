import DesignSystem
import DesignSystemCore
import DesignTokens
import Persistence
import SettingsLogic
import SwiftUI
import UIComponents

/// The settings root: the section list ``SettingsMenu/root`` describes.
///
/// Native-first: a `List` of `Section`s inside one `NavigationStack`, with the
/// route tree pushed by value. The rows come from SettingsLogic as data, so the
/// screen renders the menu rather than restating it.
///
/// Ported from `screens/Settings/Settings.tsx` (the `SettingsList` container and
/// its rows); see `SettingsViews/README.md` for the deviations.
public struct SettingsRootScreen: View {
  let viewModel: SettingsViewModel
  private let onSignOut: () -> Void

  @State private var path: [SettingsRoute] = []
  @State private var isSignOutPresented = false

  @Environment(\.alfTheme) private var theme
  @Environment(\.openURL) private var openURL

  public init(viewModel: SettingsViewModel, onSignOut: @escaping () -> Void = {}) {
    self.viewModel = viewModel
    self.onSignOut = onSignOut
  }

  public var body: some View {
    NavigationStack(path: $path) {
      List {
        ForEach(SettingsMenu.root, id: \.route) { section in
          Section {
            ForEach(section.rows, id: \.self) { row in
              rowView(row)
            }
          } header: {
            if let title = section.title {
              Text(title)
            }
          } footer: {
            if let note = section.note {
              Text(note)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle(SettingsRoute.settings.title)
      .navigationDestination(for: SettingsRoute.self) { route in
        destination(for: route)
      }
      .accessibilityIdentifier(SettingsAccessibility.root)
      .overlay(alignment: .bottom) { banners }
    }
    .confirmationDialog(
      "Sign out of Bluesky?",
      isPresented: $isSignOutPresented,
      titleVisibility: .visible
    ) {
      Button("Sign out", role: .destructive) { onSignOut() }
      Button("Cancel", role: .cancel) {}
    }
    .task { await viewModel.load() }
  }

  // MARK: - Rows

  @ViewBuilder
  private func rowView(_ row: SettingsRow) -> some View {
    switch row.action {
    case .navigate(let route):
      Button {
        path.append(route)
      } label: {
        SettingsRowLabel(
          title: row.title, badge: row.badge, isDestructive: row.isDestructive,
          showsChevron: true)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(rowAccessibilityIdentifier(for: route))
    case .openURL(let urlString):
      Button {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
      } label: {
        SettingsRowLabel(
          title: row.title, badge: row.badge, isDestructive: row.isDestructive,
          showsChevron: false)
      }
      .buttonStyle(.plain)
    case .flow(let name):
      Button {
        if name == "signOut" { isSignOutPresented = true }
      } label: {
        SettingsRowLabel(
          title: row.title, badge: row.badge, isDestructive: row.isDestructive,
          showsChevron: false)
      }
      .buttonStyle(.plain)
    }
  }

  /// A stable identifier for a navigable row, keyed by the route it opens.
  private func rowAccessibilityIdentifier(for route: SettingsRoute) -> String {
    "settings.root.row.\(route.rawValue)"
  }

  // MARK: - Destinations

  @ViewBuilder
  private func destination(for route: SettingsRoute) -> some View {
    switch route {
    case .account:
      AccountSettingsScreen(viewModel: viewModel)
    case .privacyAndSecurity:
      PrivacyAndSecurityScreen(viewModel: viewModel)
    case .appPasswords:
      AppPasswordsScreen(viewModel: viewModel)
    case .contentAndMedia:
      ContentAndMediaScreen(viewModel: viewModel)
    case .followingFeedPreferences:
      FollowingFeedPreferencesScreen(viewModel: viewModel)
    case .threads:
      ThreadPreferencesScreen(viewModel: viewModel)
    case .savedFeeds:
      SavedFeedsScreen(viewModel: viewModel)
    case .appearance:
      AppearanceSettingsScreen(viewModel: viewModel)
    case .language:
      LanguageScreen(viewModel: viewModel)
    default:
      SettingsPlaceholderScreen(title: route.title)
    }
  }

  // MARK: - Banners

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

/// One menu row's label: title, optional badge, optional disclosure chevron.
struct SettingsRowLabel: View {
  let title: String
  var badge: String? = nil
  var isDestructive: Bool = false
  var showsChevron: Bool = false

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.sm) {
      AlfText(
        title, scale: .md,
        color: isDestructive ? theme.colors.negative600 : nil)
      Spacer(minLength: Spacing.sm)
      if let badge {
        AlfText(badge, scale: .sm, color: theme.atomColors.textContrastMedium)
      }
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.footnote)
          .foregroundStyle(theme.atomColors.textContrastLow)
          .accessibilityHidden(true)
      }
    }
    .contentShape(Rectangle())
  }
}

/// A plain informational row: a label and a trailing value.
struct SettingsValueRow: View {
  let title: String
  let value: String

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.sm) {
      AlfText(title, scale: .md)
      Spacer(minLength: Spacing.sm)
      AlfText(value, scale: .sm, color: theme.atomColors.textContrastMedium)
    }
  }
}

/// The transient confirmation banner.
struct SettingsNoticeBanner: View {
  let message: String
  let onDismiss: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(theme.colors.positive600)
        .accessibilityHidden(true)
      AlfText(message, scale: .sm)
      Spacer(minLength: Spacing.sm)
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundStyle(theme.atomColors.textContrastMedium)
      }
      .accessibilityLabel("Dismiss")
    }
    .padding(.md)
    .background(theme.atomColors.bgContrast50)
    .cornerRadius(.md)
  }
}

/// The failure banner, carrying an already-mapped message.
struct SettingsErrorBanner: View {
  let message: String
  let onDismiss: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(theme.colors.negative600)
        .accessibilityHidden(true)
      AlfText(message, scale: .sm)
      Spacer(minLength: Spacing.sm)
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundStyle(theme.atomColors.textContrastMedium)
      }
      .accessibilityLabel("Dismiss")
    }
    .padding(.md)
    .background(theme.atomColors.bgContrast50)
    .cornerRadius(.md)
  }
}

/// A route whose v1 logic is out of scope, kept reachable so the tree is total.
struct SettingsPlaceholderScreen: View {
  let title: String

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(spacing: Spacing.md) {
      AlfText(title, scale: .xl, weight: Scales.FontWeight.bold)
      AlfText(
        "This screen is not part of the current settings port.",
        scale: .sm, color: theme.atomColors.textContrastMedium)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.atomColors.bg)
    .navigationTitle(title)
  }
}

#Preview {
  SettingsRootScreen(viewModel: .fixture())
    .theme(ThemePreference.light)
}
