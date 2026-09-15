import DesignSystem
import DesignTokens
import LoginLogic
import Observation
import SwiftUI
import UIComponents

/// The SwiftUI-facing adapter over ``PasswordResetFlow``.
///
/// The same shape as ``LoginViewModel``: one listener, main-actor republication,
/// and nothing but view-owned state (the new password) held locally. The two
/// step transitions the screens follow come from the flow's own `step`, so a
/// server failure keeps the user on the screen they were on.
@MainActor
@Observable
public final class PasswordResetViewModel {
  /// The flow's state, mirrored for SwiftUI.
  public private(set) var state: PasswordResetState

  /// The typed new password. Held here because the flow only needs it at submit.
  public var newPassword = ""

  /// The flow this adapter renders.
  public let flow: PasswordResetFlow

  public init(flow: PasswordResetFlow) {
    self.flow = flow
    self.state = flow.state
    flow.addListener { [weak self] newState in
      Task { @MainActor in
        self?.state = newState
      }
    }
  }

  /// True while a reset request is in flight.
  public var isProcessing: Bool { state.isProcessing }

  /// The failure copy the current step is showing.
  public var errorMessage: String? { state.error.map(LoginCopy.message(for:)) }

  /// True once the password has been changed.
  public var isComplete: Bool { state.step == .passwordUpdated }

  /// Whether the flow is collecting the code and the new password.
  public var isSettingNewPassword: Bool {
    state.step == .enteringNewPassword || state.step == .settingPassword
  }

  /// Records the email.
  public func setEmail(_ value: String) {
    flow.setEmail(value)
  }

  /// Records the reset code, letting the flow re-format it.
  public func setResetCode(_ value: String) {
    flow.setResetCode(value)
  }

  /// Requests the reset email; the flow moves to the new-password step on
  /// success.
  public func requestReset() async {
    await flow.requestReset()
  }

  /// Submits the code and the new password.
  public func submitNewPassword() async {
    await flow.setNewPassword(newPassword)
  }

  /// Returns to the email step.
  public func backToEmail() {
    flow.backToEmail()
  }
}

/// The request-reset screen: `ForgotPasswordForm` rendered natively.
public struct ForgotPasswordScreen: View {
  /// This screen's focus domain.
  enum Field: Hashable { case email }

  private let viewModel: PasswordResetViewModel
  private let onCancel: () -> Void

  @FocusState private var focusedField: Field?
  @Environment(\.alfTheme) private var theme

  public init(viewModel: PasswordResetViewModel, onCancel: @escaping () -> Void = {}) {
    self.viewModel = viewModel
    self.onCancel = onCancel
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          AlfText(
            LoginStrings.forgotPasswordTitle, scale: .xxl,
            weight: Scales.FontWeight.bold)
          AlfText(
            LoginStrings.forgotPasswordDescription, scale: .sm,
            color: theme.atomColors.textContrastMedium)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let error = viewModel.errorMessage {
          LoginErrorBanner(message: error)
        }

        LoginTextField(
          label: LoginCopy.emailPlaceholder,
          placeholder: "you@example.com",
          text: Binding(
            get: { viewModel.state.email },
            set: { viewModel.setEmail($0) }),
          field: Field.email,
          focusedField: $focusedField,
          keyboard: .emailAddress,
          identifier: LoginAccessibility.resetEmailField,
          onSubmit: requestReset)

        Button(action: requestReset) {
          if viewModel.isProcessing {
            ProgressView().tint(theme.colors.white)
          } else {
            AlfButtonText(LoginCopy.requestResetAction)
          }
        }
        .buttonStyle(.alf(color: .primary, size: .large, shape: .rectangular))
        .disabled(viewModel.isProcessing)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(LoginAccessibility.requestResetButton)

        LoginLinkButton(title: LoginCopy.cancelAction, action: onCancel)
      }
      .padding(.xl)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(LoginAccessibility.forgotPasswordScreen)
  }

  private func requestReset() {
    focusedField = nil
    Task { await viewModel.requestReset() }
  }
}

/// The set-new-password screen: `SetNewPasswordForm` rendered natively, with
/// the "you can now sign in" confirmation the RN flow shows around it.
public struct SetNewPasswordScreen: View {
  /// This screen's focus domain.
  enum Field: Hashable {
    case code
    case password
  }

  private let viewModel: PasswordResetViewModel
  private let onDone: () -> Void

  @FocusState private var focusedField: Field?
  @Environment(\.alfTheme) private var theme

  public init(viewModel: PasswordResetViewModel, onDone: @escaping () -> Void = {}) {
    self.viewModel = viewModel
    self.onDone = onDone
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        if viewModel.isComplete {
          passwordUpdated
        } else {
          form
        }
      }
      .padding(.xl)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(
      viewModel.isComplete
        ? LoginAccessibility.passwordUpdatedScreen
        : LoginAccessibility.setNewPasswordScreen)
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        AlfText(
          LoginStrings.forgotPasswordTitle, scale: .xxl, weight: Scales.FontWeight.bold)
        AlfText(
          LoginStrings.forgotPasswordDescription, scale: .sm,
          color: theme.atomColors.textContrastMedium)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let error = viewModel.errorMessage {
        LoginErrorBanner(message: error)
      }

      LoginTextField(
        label: LoginCopy.resetCodePlaceholder,
        placeholder: "XXXXX-XXXXX",
        text: Binding(
          get: { viewModel.state.resetCode },
          set: { viewModel.setResetCode($0) }),
        field: Field.code,
        focusedField: $focusedField,
        keyboard: .asciiCapable,
        identifier: LoginAccessibility.resetCodeField,
        onSubmit: { focusedField = .password })

      LoginTextField(
        label: LoginCopy.newPasswordPlaceholder,
        placeholder: LoginCopy.passwordPlaceholder,
        text: Binding(
          get: { viewModel.newPassword },
          set: { viewModel.newPassword = $0 }),
        field: Field.password,
        focusedField: $focusedField,
        isSecure: true,
        identifier: LoginAccessibility.newPasswordField,
        onSubmit: submit)

      Button(action: submit) {
        if viewModel.isProcessing {
          ProgressView().tint(theme.colors.white)
        } else {
          AlfButtonText(LoginCopy.updatePasswordAction)
        }
      }
      .buttonStyle(.alf(color: .primary, size: .large, shape: .rectangular))
      .disabled(viewModel.isProcessing)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier(LoginAccessibility.updatePasswordButton)

      LoginLinkButton(title: LoginCopy.cancelAction, action: viewModel.backToEmail)
    }
  }

  private var passwordUpdated: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        AlfText(
          LoginCopy.signedInTitle, scale: .xxl, weight: Scales.FontWeight.bold)
        AlfText(
          LoginStrings.passwordUpdatedDescription, scale: .sm,
          color: theme.atomColors.textContrastMedium)
          .fixedSize(horizontal: false, vertical: true)
      }

      AlfButton(
        LoginCopy.backToSignInAction, color: .primary, size: .large, shape: .rectangular,
        action: onDone)
    }
  }

  private func submit() {
    focusedField = nil
    Task { await viewModel.submitNewPassword() }
  }
}
