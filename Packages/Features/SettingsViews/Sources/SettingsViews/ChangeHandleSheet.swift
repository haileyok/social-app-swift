import DesignSystem
import DesignSystemCore
import DesignTokens
import SettingsLogic
import SwiftUI
import UIComponents

/// The change-handle sheet: the provided-subdomain page and the own-domain page.
///
/// Every transition, validation and submission belongs to ``ChangeHandleFlow``.
/// The sheet registers one listener, republishes the flow's state, and renders
/// it - it re-derives no rule, including the field validity, which comes from
/// ``ChangeHandleFlow/validation(host:)``.
///
/// Ported from `components/ChangeHandleDialog.tsx`.
public struct ChangeHandleSheet: View {
  let viewModel: SettingsViewModel
  let onClose: () -> Void

  @State private var state: ChangeHandleState
  @State private var flow: ChangeHandleFlow?
  @FocusState private var isFieldFocused: Bool

  @Environment(\.alfTheme) private var theme

  public init(viewModel: SettingsViewModel, onClose: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onClose = onClose
    _state = State(initialValue: ChangeHandleState())
  }

  private static let host = SettingsFixtures.providerHost

  public var body: some View {
    NavigationStack {
      Form {
        pagePicker
        switch state.page {
        case .providedHandle: providedHandlePage
        case .ownHandle: ownHandlePage
        }
        if let error = state.error {
          Section {
            AlfText(error, scale: .sm, color: theme.colors.negative600)
          }
        }
        if state.didSucceed {
          Section {
            AlfText(
              ChangeHandleStrings.handleChanged, scale: .sm,
              color: theme.colors.positive600)
          }
        }
        if let message = viewModel.errorMessage {
          Section {
            AlfText(message, scale: .sm, color: theme.colors.negative600)
          }
        }
      }
      .navigationTitle("Change handle")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onClose)
        }
      }
      .accessibilityIdentifier(SettingsAccessibility.changeHandleSheet)
      .task { installFlow() }
    }
  }

  // MARK: - Sections

  private var pagePicker: some View {
    Section {
      Picker(
        "Handle type",
        selection: Binding(
          get: { state.page.rawValue },
          set: { raw in
            guard let page = ChangeHandlePage(rawValue: raw) else { return }
            flow?.setPage(page)
          })
      ) {
        Text("Use a subdomain").tag(ChangeHandlePage.providedHandle.rawValue)
        Text("Use my own domain").tag(ChangeHandlePage.ownHandle.rawValue)
      }
      .pickerStyle(.segmented)
    }
  }

  private var providedHandlePage: some View {
    Group {
      Section {
      HStack(spacing: Spacing.xs) {
        TextField("Subdomain", text: Binding(
          get: { state.subdomain },
          set: { flow?.setSubdomain($0) }))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($isFieldFocused)
          .accessibilityIdentifier(SettingsAccessibility.changeHandleSubdomainField)
        AlfText(".\(Self.host)", scale: .md, color: theme.atomColors.textContrastMedium)
      }
      AlfText(
        "Your handle will be \(flow?.proposedServiceHandle(host: Self.host) ?? Self.host)",
        scale: .xs, color: theme.atomColors.textContrastMedium)
    } header: {
      Text("New handle")
    } footer: {
      if !validation.overall {
        Text("Handles must be at least 3 characters and use letters, numbers, and hyphens.")
      }
    }
    Section {
      Button {
        Task { await submitServiceHandle() }
      } label: {
        Text(state.isSubmitting ? "Saving…" : "Save")
      }
      .disabled(state.isSubmitting || !validation.overall)
    }
    }
  }

  private var ownHandlePage: some View {
    Group {
    Section {
      TextField(
        "yourdomain.com",
        text: Binding(
          get: { state.domain },
          set: { flow?.setDomain($0) }))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.URL)
        .accessibilityIdentifier(SettingsAccessibility.changeHandleDomainField)

      Picker(
        "Verification",
        selection: Binding(
          get: { state.verificationMethod.rawValue },
          set: { raw in
            guard let method = DomainVerificationMethod(rawValue: raw) else { return }
            flow?.setVerificationMethod(method)
          })
      ) {
        Text("DNS record").tag(DomainVerificationMethod.dns.rawValue)
        Text("Text file").tag(DomainVerificationMethod.file.rawValue)
      }
      .pickerStyle(.segmented)

      verificationStatus
    } header: {
      Text("Your domain")
    }

    Section {
      Button("Verify domain") {
        Task { await verifyDomain() }
      }
      .disabled(state.domain.isEmpty)

      Button {
        Task { await submitVerifiedDomain() }
      } label: {
        Text(state.isSubmitting ? "Saving…" : "Save")
      }
      .disabled(state.isSubmitting || state.verification != .verified)
    }
    }
  }

  @ViewBuilder
  private var verificationStatus: some View {
    switch state.verification {
    case .verified:
      AlfText(
        ChangeHandleStrings.domainVerified, scale: .sm,
        color: theme.colors.positive600)
    case .didMismatch(let received):
      AlfText(
        "That domain resolves to \(received), which is not your account.",
        scale: .sm, color: theme.colors.negative600)
    case .unresolved:
      AlfText(
        ChangeHandleStrings.failedToVerify, scale: .sm,
        color: theme.colors.negative600)
    case nil:
      AlfText(
        "Add the record below, then verify to claim this handle.",
        scale: .xs, color: theme.atomColors.textContrastMedium)
    }
  }

  // MARK: - Flow wiring

  private var validation: ServiceHandleValidation {
    flow?.validation(host: Self.host)
      ?? HandleRules.validateServiceHandle("", userDomain: Self.host)
  }

  private func installFlow() {
    guard flow == nil else { return }
    let flow = viewModel.makeChangeHandleFlow()
    self.flow = flow
    state = flow.state
    flow.setAccountContext(currentHandle: nil, isVerified: false)
    flow.addListener { newState in
      Task { @MainActor in
        self.state = newState
      }
    }
  }

  private func submitServiceHandle() async {
    guard let flow else { return }
    _ = await flow.submitServiceHandle(
      host: Self.host, availabilityServiceDID: SettingsConstants.blueskyServiceDID)
  }

  private func verifyDomain() async {
    guard let flow else { return }
    _ = await flow.verifyDomain(expectedDID: viewModel.accountDID)
  }

  private func submitVerifiedDomain() async {
    guard let flow else { return }
    _ = await flow.submitVerifiedDomain(
      availabilityServiceDID: SettingsConstants.blueskyServiceDID)
  }
}
