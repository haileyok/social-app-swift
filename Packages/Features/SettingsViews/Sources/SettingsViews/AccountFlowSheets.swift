import DesignSystem
import DesignSystemCore
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The delete-account sheet: the three steps ``DeleteAccountStep`` names.
///
/// `sendCode` → `verifyCode` → `confirmDeletion`, all driven by
/// ``DeleteAccountFlow``. The sheet renders the flow's step, and the copy comes
/// from ``SettingsStrings``, so the flow's tests and the screen agree.
///
/// Ported from `components/DeleteAccountDialog.tsx`.
public struct DeleteAccountSheet: View {
  let viewModel: SettingsViewModel
  let onClose: () -> Void

  @State private var state: DeleteAccountState
  @State private var flow: DeleteAccountFlow?
  @FocusState private var focused: Field?

  @Environment(\.alfTheme) private var theme

  /// The sheet's own focus domain.
  enum Field: Hashable {
    case code
    case password
  }

  public init(viewModel: SettingsViewModel, onClose: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onClose = onClose
    _state = State(initialValue: DeleteAccountState())
  }

  public var body: some View {
    NavigationStack {
      Form {
        switch state.step {
        case .sendCode: sendCodeStep
        case .verifyCode: verifyCodeStep
        case .confirmDeletion: confirmStep
        }
        if let error = state.error {
          Section {
            AlfText(error, scale: .sm, color: theme.colors.negative600)
          }
        }
        if state.didDelete {
          Section {
            AlfText(
              SettingsStrings.accountDeleted, scale: .sm,
              color: theme.colors.positive600)
          }
        }
      }
      .navigationTitle("Delete account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onClose)
        }
      }
      .accessibilityIdentifier(SettingsAccessibility.deleteAccountSheet)
      .task { installFlow() }
    }
  }

  // MARK: - Steps

  private var sendCodeStep: some View {
    Section {
      AlfText(
        "Deleting your account is permanent. We will email a confirmation code to continue.",
        scale: .sm)
      Button {
        Task { _ = await flow?.sendCode() }
      } label: {
        Text(state.isSendingCode ? "Sending…" : "Send confirmation code")
      }
      .disabled(state.isSendingCode)
    } header: {
      Text("Step 1 of 3")
    }
  }

  private var verifyCodeStep: some View {
    Section {
      TextField("Confirmation code", text: Binding(
        get: { state.confirmCode },
        set: { flow?.setConfirmCode($0) }))
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .focused($focused, equals: .code)

      Button {
        flow?.beginConfirmation()
      } label: {
        Text("Continue")
      }
      .disabled(DeleteAccountRules.sanitizeConfirmationCode(state.confirmCode).isEmpty)

      Button("Resend code") {
        Task { _ = await flow?.sendCode() }
      }
      .disabled(state.isSendingCode)
    } header: {
      Text("Step 2 of 3")
    } footer: {
      Text("Enter the code we emailed you. Sent \(state.emailSentCount) time(s).")
    }
  }

  private var confirmStep: some View {
    Section {
      SecureField("Password", text: Binding(
        get: { state.password },
        set: { flow?.setPassword($0) }))
        .focused($focused, equals: .password)

      Button(role: .destructive) {
        Task { _ = await flow?.confirmDeletion(did: viewModel.accountDID) }
      } label: {
        Text("Delete my account")
      }
      .disabled(!state.canSubmitDeletion)
    } header: {
      Text("Step 3 of 3")
    } footer: {
      Text("Enter your account password to confirm. This cannot be undone.")
    }
  }

  // MARK: - Flow wiring

  private func installFlow() {
    guard flow == nil else { return }
    let flow = viewModel.makeDeleteAccountFlow()
    self.flow = flow
    state = flow.state
    flow.addListener { newState in
      Task { @MainActor in
        self.state = newState
      }
    }
  }
}

/// The deactivate-account sheet: one call, plus the app-password-scope message.
///
/// Ported from `components/DeactivateAccountDialog.tsx`.
public struct DeactivateAccountSheet: View {
  let viewModel: SettingsViewModel
  let onClose: () -> Void

  @State private var isSubmitting = false
  @State private var message: String?

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel, onClose: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onClose = onClose
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          AlfText(
            "Your account will be hidden until you reactivate it by signing in again.",
            scale: .sm)
          Button(role: .destructive) {
            Task { await deactivate() }
          } label: {
            Text(isSubmitting ? "Deactivating…" : "Deactivate account")
          }
          .disabled(isSubmitting)
        }
        if let message {
          Section {
            AlfText(message, scale: .sm, color: theme.colors.negative600)
          }
        }
      }
      .navigationTitle("Deactivate account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onClose)
        }
      }
      .accessibilityIdentifier(SettingsAccessibility.deactivateAccountSheet)
    }
  }

  private func deactivate() async {
    isSubmitting = true
    message = nil
    let result = await viewModel.makeDeactivateAccountFlow().deactivate()
    isSubmitting = false
    if case .failure(let error) = result {
      message = error.message
    }
  }
}

/// The repo-export sheet: build the request, fetch the bytes, report the size.
///
/// Ported from `components/ExportCarDialog.tsx`. The request shape comes from
/// ``ExportData``; this sheet only reports what the fetch produced.
public struct ExportDataSheet: View {
  let viewModel: SettingsViewModel
  let onClose: () -> Void

  @State private var request: ExportDataRequest?
  @State private var byteCount: Int?
  @State private var isLoading = false
  @State private var message: String?

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel, onClose: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onClose = onClose
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          if let request {
            SettingsValueRow(title: "File", value: request.fileName)
            SettingsValueRow(title: "Endpoint", value: request.path)
          } else {
            AlfText(
              "Preparing your export…", scale: .sm,
              color: theme.atomColors.textContrastMedium)
          }
          Button {
            Task { await download() }
          } label: {
            Text(isLoading ? "Downloading…" : "Download my data")
          }
          .disabled(isLoading)
        } header: {
          Text("Export my data")
        } footer: {
          Text("Your repository is exported as a CAR file.")
        }
        if let byteCount {
          Section {
            SettingsValueRow(title: "Downloaded", value: "\(byteCount) bytes")
          }
        }
        if let message {
          Section {
            AlfText(message, scale: .sm, color: theme.colors.negative600)
          }
        }
      }
      .navigationTitle("Export my data")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onClose)
        }
      }
      .accessibilityIdentifier(SettingsAccessibility.exportSheet)
      .task { request = await viewModel.repoExportRequest() }
    }
  }

  private func download() async {
    isLoading = true
    message = nil
    let result = await viewModel.fetchRepoExport()
    isLoading = false
    switch result {
    case .success(let data):
      byteCount = data.count
    case .failure(let error):
      message = error.message
    }
  }
}
