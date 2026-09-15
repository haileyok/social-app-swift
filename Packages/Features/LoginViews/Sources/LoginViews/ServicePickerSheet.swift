import DesignSystem
import DesignTokens
import LoginLogic
import SwiftUI
import UIComponents

/// The server picker: the default Bluesky server vs a typed custom address.
///
/// Ports `ServerInput.tsx` plus the `useServiceQuery` preflight. The preflight
/// result is shown rather than blocking: an address that describes successfully
/// gets a confirmation line, one that does not gets the reason, and the form
/// behind the sheet keeps whatever normalized address was last adopted (the flow
/// stores it either way - see ``LoginFlow/selectCustomService(_:)``).
public struct ServicePickerSheet: View {
  /// The picker's own focus domain.
  enum Field: Hashable { case address }

  private let currentService: String
  private let status: ServicePreflightStatus
  private let onSelectDefault: () -> Void
  private let onSelectCustom: (String) -> Void
  private let onCancel: () -> Void

  @State private var address = ""
  @State private var validationMessage: String?
  @FocusState private var focusedField: Field?

  @Environment(\.alfTheme) private var theme

  public init(
    currentService: String,
    status: ServicePreflightStatus,
    onSelectDefault: @escaping () -> Void,
    onSelectCustom: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.currentService = currentService
    self.status = status
    self.onSelectDefault = onSelectDefault
    self.onSelectCustom = onSelectCustom
    self.onCancel = onCancel
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          AlfText(LoginCopy.serviceLabel, scale: .xl, weight: Scales.FontWeight.bold)
          AlfText(currentService, scale: .sm, color: theme.atomColors.textContrastMedium)
            .lineLimit(1)
        }

        statusLine

        divider

        Button(action: onSelectDefault) {
          HStack(spacing: Spacing.sm) {
            Image(systemName: "cloud.fill")
              .accessibilityHidden(true)
            AlfButtonText(LoginCopy.defaultServerAction)
            Spacer(minLength: 0)
          }
        }
        .buttonStyle(.alf(color: .secondary, size: .large, shape: .rectangular))
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(LoginAccessibility.defaultServiceOption)

        divider

        VStack(alignment: .leading, spacing: Spacing.md) {
          LoginTextField(
            label: LoginCopy.serverPlaceholder,
            placeholder: "example.com",
            text: $address,
            field: Field.address,
            focusedField: $focusedField,
            keyboard: .url,
            identifier: LoginAccessibility.serviceField,
            error: validationMessage,
            onSubmit: connect)

          Button(action: connect) {
            if status.isChecking {
              ProgressView().tint(theme.colors.white)
            } else {
              AlfButtonText(LoginCopy.connectToServerAction)
            }
          }
          .buttonStyle(.alf(color: .primary, size: .large, shape: .rectangular))
          .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier(LoginAccessibility.connectServiceButton)
        }

        LoginLinkButton(title: LoginCopy.cancelAction, action: onCancel)
      }
      .padding(.xl)
    }
    // The keyboard dismisses on drag, which matters most in landscape where the
    // sheet and the keyboard compete for height.
    .scrollDismissesKeyboard(.interactively)
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(LoginAccessibility.servicePicker)
  }

  /// The preflight status, rendered in one line under the header.
  @ViewBuilder
  private var statusLine: some View {
    switch status {
    case .idle:
      EmptyView()
    case .checking:
      statusRow(LoginCopy.checkingServer, color: theme.atomColors.textContrastMedium)
    case .ok(let description):
      statusRow(
        LoginCopy.connectedToServer(description?.did ?? currentService),
        color: theme.colors.positive600)
    case .invalid(let message):
      statusRow(message, color: theme.colors.negative600)
    }
  }

  private func statusRow(_ message: String, color: Color) -> some View {
    AlfText(message, scale: .sm, color: color)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier(LoginAccessibility.serviceStatus)
  }

  private var divider: some View {
    Divider().overlay(theme.atomColors.borderContrastLow)
  }

  /// Validates locally before asking the flow to describe the address, so an
  /// empty or malformed value never produces a network round trip.
  private func connect() {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    switch ServiceURL.validate(trimmed) {
    case .empty, .invalid:
      validationMessage = LoginStrings.invalidServiceUrl
    case .valid:
      validationMessage = nil
      onSelectCustom(trimmed)
    }
  }
}
