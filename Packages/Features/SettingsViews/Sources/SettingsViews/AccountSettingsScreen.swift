import DesignSystem
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The account screen: the profile rows, the account flows, and the destructive
/// lifecycle actions.
///
/// The rows are ``SettingsMenu/account``; the four that open a flow
/// (`changeHandle`, `exportData`, `deactivateAccount`, `deleteAccount`) present a
/// sheet, and the rest are out of the v1 UI surface so they surface a notice
/// rather than a dead control.
///
/// Ported from `screens/Settings/AccountSettings.tsx`.
public struct AccountSettingsScreen: View {
  let viewModel: SettingsViewModel

  @State private var presentedFlow: AccountFlow?

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  /// The account flows this screen can present.
  public enum AccountFlow: String, Identifiable {
    case changeHandle
    case exportData
    case deactivateAccount
    case deleteAccount
    case unavailable

    public var id: String { rawValue }
  }

  private var rows: [SettingsRow] { SettingsMenu.account.flatMap(\.rows) }

  public var body: some View {
    Form {
      Section {
        ForEach(rows, id: \.self) { row in
          rowButton(row)
        }
      }
    }
    .navigationTitle(SettingsRoute.account.title)
    .accessibilityIdentifier(SettingsAccessibility.account)
    .sheet(item: $presentedFlow) { flow in
      sheet(for: flow)
    }
    .overlay(alignment: .bottom) { banners }
  }

  @ViewBuilder
  private func rowButton(_ row: SettingsRow) -> some View {
    Button {
      guard case .flow(let name) = row.action else { return }
      switch name {
      case "changeHandle": presentedFlow = .changeHandle
      case "exportData": presentedFlow = .exportData
      case "deactivateAccount": presentedFlow = .deactivateAccount
      case "deleteAccount": presentedFlow = .deleteAccount
      default: presentedFlow = .unavailable
      }
    } label: {
      SettingsRowLabel(
        title: row.title, badge: row.badge, isDestructive: row.isDestructive,
        showsChevron: true)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("settings.account.row.\(row.title)")
  }

  @ViewBuilder
  private func sheet(for flow: AccountFlow) -> some View {
    switch flow {
    case .changeHandle:
      ChangeHandleSheet(viewModel: viewModel) { presentedFlow = nil }
    case .exportData:
      ExportDataSheet(viewModel: viewModel) { presentedFlow = nil }
    case .deactivateAccount:
      DeactivateAccountSheet(viewModel: viewModel) { presentedFlow = nil }
    case .deleteAccount:
      DeleteAccountSheet(viewModel: viewModel) { presentedFlow = nil }
    case .unavailable:
      UnavailableFlowSheet(title: "Not available yet") { presentedFlow = nil }
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

/// The privacy-and-security screen: the app-passwords entry point.
///
/// Ported from `screens/Settings/PrivacyAndSecuritySettings.tsx`.
public struct PrivacyAndSecurityScreen: View {
  let viewModel: SettingsViewModel

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  private var rows: [SettingsRow] { SettingsMenu.privacyAndSecurity.flatMap(\.rows) }

  public var body: some View {
    Form {
      Section {
        ForEach(rows, id: \.self) { row in
          if let route = row.route {
            NavigationLink(value: route) {
              SettingsRowLabel(title: row.title)
            }
          } else {
            SettingsRowLabel(title: row.title)
          }
        }
      }
    }
    .navigationTitle(SettingsRoute.privacyAndSecurity.title)
    .accessibilityIdentifier(SettingsAccessibility.privacyAndSecurity)
  }
}

/// A sheet for a flow the v1 surface does not implement.
struct UnavailableFlowSheet: View {
  let title: String
  let onClose: () -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: Spacing.md) {
        AlfText(title, scale: .lg, weight: Scales.FontWeight.bold)
        AlfText(
          "This step is not part of the current settings port.",
          scale: .sm)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onClose)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    AccountSettingsScreen(viewModel: .fixture())
  }
  .theme(.light)
}
