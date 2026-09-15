import DesignSystem
import DesignTokens
import LoginLogic
import Persistence
import SwiftUI
import UIComponents

/// The sign-in screen: the app's first real user-facing surface.
///
/// Renders ``LoginFlow``'s state machine natively-first: a standard SwiftUI form
/// in a `ScrollView`, sheets for the service picker and the 2FA code, and an
/// inline banner for mapped failures. It owns no flow logic - every submit,
/// service change and account action is a call into the flow, and what the
/// screen shows is whatever the flow reports back.
///
/// Ported from `screens/Login/LoginForm.tsx` and the `Login` screen's layout in
/// `screens/Login/index.tsx`; see `LoginViews/README.md` for the deviations.
public struct LoginScreen: View {
  private let viewModel: LoginViewModel
  private let onSignedIn: (PersistedAccount) -> Void
  private let onForgotPassword: (String) -> Void
  private let showsStoredAccounts: Bool

  @State private var isServicePickerPresented = false
  @State private var isAuthFactorPresented = false
  @State private var isChooseAccountPresented = false
  @State private var resumingDID: String?

  @FocusState private var focusedField: Field?

  @Environment(\.alfTheme) private var theme

  /// The screen's own focus domain.
  enum Field: Hashable {
    case identifier
    case password
  }

  /// Creates the sign-in screen.
  ///
  /// - Parameters:
  ///   - viewModel: the adapter over the flow.
  ///   - showsStoredAccounts: whether the chooser may appear above the form.
  ///     The debug entry point turns this off so the smoke test always lands on
  ///     the credential form regardless of what is on the device.
  ///   - onSignedIn: called with the account once a sign-in succeeds.
  ///   - onForgotPassword: called with the current service address.
  public init(
    viewModel: LoginViewModel = LoginViewModel(),
    showsStoredAccounts: Bool = true,
    onSignedIn: @escaping (PersistedAccount) -> Void = { _ in },
    onForgotPassword: @escaping (String) -> Void = { _ in }
  ) {
    self.viewModel = viewModel
    self.showsStoredAccounts = showsStoredAccounts
    self.onSignedIn = onSignedIn
    self.onForgotPassword = onForgotPassword
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        header

        if showsStoredAccounts && !viewModel.storedAccounts.isEmpty && !isChooseAccountPresented {
          chooseAccountSummary
        }

        credentialForm
      }
      .padding(.xl)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    // The keyboard dismisses on drag, which matters most in landscape where the
    // form and the keyboard compete for height.
    .scrollDismissesKeyboard(.interactively)
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(LoginAccessibility.screen)
    .task { await viewModel.load() }
    // A success or a 2FA demand are flow transitions, so the screen reacts to
    // the state rather than to the button's callback: that keeps the sheet and
    // the credential form from disagreeing about which step is current.
    .onChange(of: viewModel.state.step) { _, step in
      handle(step)
    }
    .sheet(isPresented: $isServicePickerPresented) {
      servicePicker
    }
    .sheet(isPresented: $isAuthFactorPresented) {
      authFactor
    }
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(
        LoginCopy.screenTitle, scale: .xxl, weight: Scales.FontWeight.bold)
      AlfText(
        LoginCopy.screenDescription, scale: .sm,
        color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// The compact "you already have accounts here" entry, which opens the full
  /// chooser rather than rendering the list inline in the form.
  private var chooseAccountSummary: some View {
    Button {
      isChooseAccountPresented = true
    } label: {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "person.2.fill")
          .accessibilityHidden(true)
        AlfButtonText(
          LoginStrings.signedInAs(handle: viewModel.storedAccounts[0].handle))
      }
    }
    .buttonStyle(.alf(color: .secondary, size: .large, shape: .rectangular))
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier(LoginAccessibility.chooseAccount)
  }

  private var credentialForm: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      serviceRow

      if let validation = viewModel.validationMessage {
        LoginValidationLine(message: validation)
      }

      if let error = viewModel.error {
        errorBanner(for: error)
      }

      identifierField
      passwordField

      submitButton

      LoginLinkButton(
        title: LoginCopy.forgotPasswordAction,
        identifier: LoginAccessibility.forgotPasswordButton
      ) {
        onForgotPassword(viewModel.state.service)
      }

      if isChooseAccountPresented {
        chooseAccountSection
      }
    }
  }

  /// The chosen server plus the "change server" affordance.
  private var serviceRow: some View {
    HStack(spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(
          LoginCopy.serviceLabel, scale: .xs, color: theme.atomColors.textContrastLow)
        AlfText(viewModel.serviceDisplay, scale: .sm, weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      LoginLinkButton(
        title: LoginCopy.changeServerAction,
        identifier: LoginAccessibility.serviceButton
      ) {
        focusedField = nil
        isServicePickerPresented = true
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func errorBanner(for error: LoginError) -> some View {
    LoginErrorBanner(message: LoginCopy.message(for: error)) {
      if error.isRecoverable {
        LoginLinkButton(title: LoginCopy.retryAction, action: submit)
      }
    }
  }

  private var identifierField: some View {
    LoginTextField(
      label: LoginCopy.identifierLabel,
      placeholder: LoginCopy.identifierPlaceholder,
      text: Binding(
        get: { viewModel.state.identifier },
        set: { viewModel.setIdentifier($0) }),
      field: Field.identifier,
      focusedField: $focusedField,
      keyboard: .emailAddress,
      identifier: LoginAccessibility.identifierField,
      onSubmit: { focusedField = .password })
  }

  private var passwordField: some View {
    LoginTextField(
      label: LoginCopy.passwordLabel,
      placeholder: LoginCopy.passwordPlaceholder,
      text: Binding(
        get: { viewModel.password },
        set: { viewModel.password = $0 }),
      field: Field.password,
      focusedField: $focusedField,
      isSecure: true,
      identifier: LoginAccessibility.passwordField,
      onSubmit: submit)
  }

  private var submitButton: some View {
    Button(action: submit) {
      if viewModel.isProcessing {
        ProgressView().tint(theme.colors.white)
      } else {
        AlfButtonText(LoginCopy.signInAction)
      }
    }
    .buttonStyle(.alf(color: .primary, size: .large, shape: .rectangular))
    .disabled(!viewModel.canSubmit)
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier(LoginAccessibility.signInButton)
  }

  private var chooseAccountSection: some View {
    ChooseAccountView(
      accounts: viewModel.storedAccounts,
      errorMessage: viewModel.accountActionError,
      resumingDID: resumingDID,
      onResume: { row in
        Task { await resume(row) }
      },
      onForget: { row in
        Task { await viewModel.forget(row.account) }
      },
      onSignInInstead: { isChooseAccountPresented = false })
  }

  // MARK: - Sheets

  private var servicePicker: some View {
    ServicePickerSheet(
      currentService: viewModel.serviceDisplay,
      status: viewModel.serviceStatus,
      onSelectDefault: {
        Task {
          await viewModel.selectDefaultService()
          isServicePickerPresented = false
        }
      },
      onSelectCustom: { raw in
        Task {
          // Adopt the address first, then close: a failure still leaves the
          // normalized value chosen, which is what the flow does too.
          await viewModel.selectCustomService(raw)
          isServicePickerPresented = false
        }
      },
      onCancel: { isServicePickerPresented = false })
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
  }

  private var authFactor: some View {
    AuthFactorSheet(
      isProcessing: viewModel.isProcessing,
      errorMessage: viewModel.error?.message,
      onSubmit: { code in
        Task { await viewModel.submitAuthFactor(code) }
      },
      onCancel: {
        viewModel.cancelAuthFactor()
        isAuthFactorPresented = false
      })
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
  }

  // MARK: - Actions

  private func submit() {
    guard !viewModel.isProcessing else { return }
    focusedField = nil
    Task {
      await viewModel.signIn()
    }
  }

  private func resume(_ row: StoredAccountRow) async {
    resumingDID = row.id
    defer { resumingDID = nil }
    if case .resumed(let account) = await viewModel.resume(row.account) {
      onSignedIn(account)
    }
  }

  /// Reacts to a flow transition.
  private func handle(_ step: LoginStep) {
    switch step {
    case .needsAuthFactor:
      focusedField = nil
      isAuthFactorPresented = true
    case .success:
      isAuthFactorPresented = false
      if let account = viewModel.state.account {
        onSignedIn(account)
      }
    case .failed:
      // A failure deliberately leaves presentation alone: a failed 2FA retry
      // keeps the sheet up so the code can be corrected without retyping the
      // password, and a failed credential submit has no sheet to close.
      break
    case .enteringCredentials, .choosingAccount, .pickingService, .signingIn:
      isAuthFactorPresented = false
    }
  }
}

#Preview {
  LoginScreen()
}
