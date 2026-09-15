import DesignSystem
import DesignTokens
import LoginLogic
import SwiftUI
import UIComponents

/// The 2FA confirmation sheet.
///
/// Presented when the flow reports ``LoginStep/needsAuthFactor`` (the server
/// demanded an emailed code). The retry path is
/// ``LoginFlow/retryWithAuthFactor(_:)``, which repeats the original
/// `createSession` call with the code attached rather than restarting the
/// attempt - so the user never retypes their password.
public struct AuthFactorSheet: View {
  /// The sheet's own focus domain.
  enum Field: Hashable { case code }

  private let isProcessing: Bool
  private let errorMessage: String?
  private let onSubmit: (String) -> Void
  private let onCancel: () -> Void

  @State private var code = ""
  @FocusState private var focusedField: Field?

  @Environment(\.alfTheme) private var theme

  public init(
    isProcessing: Bool,
    errorMessage: String? = nil,
    onSubmit: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.isProcessing = isProcessing
    self.errorMessage = errorMessage
    self.onSubmit = onSubmit
    self.onCancel = onCancel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        AlfText(
          LoginStrings.twoFactorLabel, scale: .xl, weight: Scales.FontWeight.bold)
        AlfText(
          LoginStrings.twoFactorPrompt, scale: .sm,
          color: theme.atomColors.textContrastMedium)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let errorMessage {
        LoginErrorBanner(message: errorMessage)
      }

      LoginTextField(
        label: LoginCopy.authFactorPlaceholder,
        placeholder: "XXXXX",
        text: $code,
        field: Field.code,
        focusedField: $focusedField,
        keyboard: .asciiCapable,
        identifier: LoginAccessibility.authFactorField,
        onSubmit: submit)

      Button(action: submit) {
        if isProcessing {
          ProgressView().tint(theme.colors.white)
        } else {
          AlfButtonText(LoginCopy.confirmAction)
        }
      }
      .buttonStyle(.alf(color: .primary, size: .large, shape: .rectangular))
      .disabled(isProcessing || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier(LoginAccessibility.authFactorSubmit)

      LoginLinkButton(title: LoginCopy.cancelAction, action: onCancel)
    }
    .padding(.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(LoginAccessibility.authFactorSheet)
    // The code field is the only thing to do on this sheet, so it takes focus
    // as soon as the sheet settles.
    .task { focusedField = .code }
  }

  private func submit() {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isProcessing else { return }
    onSubmit(trimmed)
  }
}
