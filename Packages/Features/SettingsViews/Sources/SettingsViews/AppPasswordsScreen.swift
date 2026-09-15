import DesignSystem
import DesignSystemCore
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The app-passwords screen: the list, the create sheet, and the revoke confirm.
///
/// Ported from `screens/Settings/AppPasswords.tsx` and
/// `components/AddAppPasswordDialog.tsx`. Every rule (the name character rule,
/// the minimum length, uniqueness, the one-time plaintext) belongs to
/// ``AppPasswordValidation`` and ``SettingsStore``; the screen renders what they
/// report.
public struct AppPasswordsScreen: View {
  let viewModel: SettingsViewModel

  @State private var isCreatePresented = false
  @State private var created: SettingsAppPassword?
  @State private var revokeTarget: SettingsAppPassword?
  @State private var revokeError: String?

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  private var status: SettingsState.LoadStatus { viewModel.state.appPasswordsStatus }
  private var passwords: [SettingsAppPassword] { viewModel.state.appPasswords }

  public var body: some View {
    Group {
      if status == .failed {
        ErrorStateView(
          title: "Could not load app passwords",
          message: viewModel.state.appPasswordsError?.message
            ?? AppPasswordErrors.fetchFailed,
          retry: { Task { await viewModel.load() } })
      } else {
        list
      }
    }
    .navigationTitle(SettingsRoute.appPasswords.title)
    .accessibilityIdentifier(SettingsAccessibility.appPasswords)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isCreatePresented = true
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add app password")
        .accessibilityIdentifier(SettingsAccessibility.addAppPasswordButton)
      }
    }
    .sheet(isPresented: $isCreatePresented) {
      CreateAppPasswordSheet(
        viewModel: viewModel,
        onCreated: { password in
          isCreatePresented = false
          created = password
        },
        onCancel: { isCreatePresented = false })
    }
    .sheet(
      isPresented: Binding(
        get: { created != nil },
        set: { if !$0 { created = nil } })
    ) {
      if let created {
        AppPasswordCreatedSheet(password: created) { self.created = nil }
      }
    }
    .confirmationDialog(
      "Revoke app password?",
      isPresented: Binding(
        get: { revokeTarget != nil },
        set: { if !$0 { revokeTarget = nil } }),
      presenting: revokeTarget
    ) { password in
      Button("Revoke \(password.name)", role: .destructive) {
        revokeTarget = nil
        Task { await revoke(password.name) }
      }
      Button("Cancel", role: .cancel) { revokeTarget = nil }
    } message: { password in
      Text("\(password.name) will stop working immediately.")
    }
    .overlay(alignment: .bottom) { banners }
  }

  private var list: some View {
    List {
      if passwords.isEmpty {
        Section {
          AlfText(
            "You have not created any app passwords yet.",
            scale: .sm, color: theme.atomColors.textContrastMedium)
        }
      } else {
        Section {
          ForEach(passwords, id: \.name) { password in
            row(password)
          }
          .onDelete { offsets in
            guard let index = offsets.first, passwords.indices.contains(index) else { return }
            revokeTarget = passwords[index]
          }
        } footer: {
          Text("App passwords can be revoked at any time.")
        }
      }
    }
    .listStyle(.insetGrouped)
    .overlay {
      if status == .loading && passwords.isEmpty {
        ProgressView()
      }
    }
  }

  private func row(_ password: SettingsAppPassword) -> some View {
    HStack(spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(password.name, scale: .md)
        if password.privileged {
          AlfText(
            "Privileged", scale: .xs, color: theme.atomColors.textContrastMedium)
        }
      }
      Spacer(minLength: Spacing.sm)
      Button(role: .destructive) {
        revokeTarget = password
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(theme.colors.negative600)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Revoke \(password.name)")
      .accessibilityIdentifier(SettingsAccessibility.appPasswordRevoke(password.name))
    }
    .accessibilityIdentifier(SettingsAccessibility.appPasswordRow(password.name))
  }

  @ViewBuilder
  private var banners: some View {
    VStack(spacing: Spacing.sm) {
      if let notice = viewModel.notice {
        SettingsNoticeBanner(message: notice) { viewModel.clearNotice() }
      }
      if let message = revokeError {
        SettingsErrorBanner(message: message) { revokeError = nil }
      }
      if let message = viewModel.errorMessage {
        SettingsErrorBanner(message: message) { viewModel.clearError() }
      }
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.bottom, Spacing.lg)
  }

  private func revoke(_ name: String) async {
    let result = await viewModel.revokeAppPassword(name: name)
    if case .failure(let error) = result {
      revokeError = error.message
    }
  }
}

/// The create-app-password sheet.
///
/// The name field starts pre-filled with a random suggestion from
/// ``AppPasswordNameSuggestions`` (the RN `useRandomName` behaviour), the
/// character rule shows inline while typing, and the length/uniqueness rules are
/// checked on submit by ``SettingsViewModel/createAppPassword(typedName:privileged:generatedName:)``.
public struct CreateAppPasswordSheet: View {
  let viewModel: SettingsViewModel
  let onCreated: (SettingsAppPassword) -> Void
  let onCancel: () -> Void

  @State private var name = ""
  @State private var privileged = false
  @State private var generatedName = AppPasswordNameSuggestions.suggestion(at: 0)
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @FocusState private var isNameFocused: Bool

  @Environment(\.alfTheme) private var theme

  public init(
    viewModel: SettingsViewModel,
    onCreated: @escaping (SettingsAppPassword) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.viewModel = viewModel
    self.onCreated = onCreated
    self.onCancel = onCancel
  }

  private var displayError: String? {
    errorMessage ?? AppPasswordValidation.displayError(typed: name)
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isNameFocused)
            .accessibilityIdentifier(SettingsAccessibility.appPasswordNameField)
          Toggle("Allow access to direct messages", isOn: $privileged)
        } header: {
          Text("Name")
        } footer: {
          Text(
            "Leave the field empty to use \(generatedName). App password names must be at least 4 characters long."
          )
        }

        if let displayError {
          Section {
            AlfText(displayError, scale: .sm, color: theme.colors.negative600)
              .accessibilityIdentifier(SettingsAccessibility.appPasswordError)
          }
        }
      }
      .navigationTitle("Add app password")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { Task { await submit() } }
            .disabled(isSubmitting)
            .accessibilityIdentifier(SettingsAccessibility.appPasswordSubmitButton)
        }
      }
      .accessibilityIdentifier(SettingsAccessibility.createAppPasswordSheet)
      .task {
        generatedName = AppPasswordNameSuggestions.suggestion(
          at: Int.random(in: 0..<AppPasswordNameSuggestions.shadesOfBlue.count))
      }
    }
  }

  private func submit() async {
    isSubmitting = true
    errorMessage = nil
    let result = await viewModel.createAppPassword(
      typedName: name, privileged: privileged, generatedName: generatedName)
    isSubmitting = false
    switch result {
    case .success(let password):
      onCreated(password)
    case .failure(let error):
      errorMessage = error.message
    }
  }
}

/// The one-time plaintext password, shown once and never returned again.
public struct AppPasswordCreatedSheet: View {
  let password: SettingsAppPassword
  let onDone: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(password: SettingsAppPassword, onDone: @escaping () -> Void) {
    self.password = password
    self.onDone = onDone
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(password.password ?? "")
            .font(.system(.body, design: .monospaced))
            .accessibilityIdentifier(SettingsAccessibility.appPasswordCreatedSheet)
        } header: {
          Text(password.name)
        } footer: {
          Text(
            "Copy this password now. It cannot be shown again."
          )
        }
      }
      .navigationTitle("App password created")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    AppPasswordsScreen(viewModel: .fixture())
  }
  .theme(ThemePreference.light)
}
