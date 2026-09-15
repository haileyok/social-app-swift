import DesignSystem
import DesignTokens
import LoginLogic
import Persistence
import SwiftUI
import UIComponents

/// A stored account plus the resume decision the chooser needs.
public struct StoredAccountRow: Identifiable, Sendable, Equatable {
  /// The account's DID, which is also its identity for `List`.
  public var id: String { account.did }
  /// The persisted account.
  public let account: PersistedAccount
  /// Whether it can be resumed as-is or needs a fresh sign-in.
  public let decision: ResumeDecision

  public init(account: PersistedAccount) {
    self.account = account
    self.decision = ResumeDecision.forAccount(account)
  }

  /// The handle as the row shows it.
  public var handle: String { "@\(account.handle)" }

  /// The row's supporting line: the server it lives on.
  public var serviceHost: String { account.service }
}

/// Renders one stored account.
///
/// Two actions per row, matching `ChooseAccountForm`: resume (which is disabled
/// when the account has no stored token, because the flow would only bounce back
/// to the credential form) and forget.
struct StoredAccountRowView: View {
  let row: StoredAccountRow
  let isResuming: Bool
  let onResume: () -> Void
  let onForget: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.md) {
      Avatar(
        avatar: nil,
        handle: row.account.handle,
        displayName: row.account.email,
        size: .lg)

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(row.handle, scale: .md, weight: Scales.FontWeight.semiBold)
          .lineLimit(1)
        AlfText(row.serviceHost, scale: .xs, color: theme.atomColors.textContrastLow)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if isResuming {
        ProgressView()
          .accessibilityLabel(LoginCopy.resumeAccountAction)
      } else {
        Button(LoginCopy.resumeAccountAction, action: onResume)
          .buttonStyle(.alf(color: .primary, size: .small))
          .disabled(row.decision != .resume)
          .accessibilityIdentifier(LoginAccessibility.resumeAccount(row.account.did))
      }

      Button(LoginCopy.forgetAccountAction, action: onForget)
        .buttonStyle(.alf(color: .negativeSubtle, size: .small))
        .accessibilityIdentifier(LoginAccessibility.forgetAccount(row.account.did))
    }
    .padding(.sm, .vertical)
    .contentShape(.rect)
  }
}

/// The stored-account chooser: `ChooseAccountForm` rendered natively.
///
/// Shown above the sign-in form when the device already has accounts, which is
/// the RN screen's arrangement (the chooser is a list you can switch away from,
/// not a separate route).
public struct ChooseAccountView: View {
  private let accounts: [StoredAccountRow]
  private let errorMessage: String?
  private let resumingDID: String?
  private let onResume: (StoredAccountRow) -> Void
  private let onForget: (StoredAccountRow) -> Void
  private let onSignInInstead: () -> Void

  @Environment(\.alfTheme) private var theme

  public init(
    accounts: [PersistedAccount],
    errorMessage: String? = nil,
    resumingDID: String? = nil,
    onResume: @escaping (StoredAccountRow) -> Void,
    onForget: @escaping (StoredAccountRow) -> Void,
    onSignInInstead: @escaping () -> Void
  ) {
    self.accounts = accounts.map(StoredAccountRow.init(account:))
    self.errorMessage = errorMessage
    self.resumingDID = resumingDID
    self.onResume = onResume
    self.onForget = onForget
    self.onSignInInstead = onSignInInstead
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      AlfText(
        LoginCopy.chooseAccountTitle, scale: .lg, weight: Scales.FontWeight.bold)

      if let errorMessage {
        LoginErrorBanner(message: errorMessage)
      }

      if accounts.isEmpty {
        AlfText(
          LoginCopy.noStoredAccounts, scale: .sm, color: theme.atomColors.textContrastMedium)
      } else {
        VStack(spacing: 0) {
          ForEach(accounts) { row in
            StoredAccountRowView(
              row: row,
              isResuming: resumingDID == row.id,
              onResume: { onResume(row) },
              onForget: { onForget(row) })
            if row.id != accounts.last?.id {
              Divider().overlay(theme.atomColors.borderContrastLow)
            }
          }
        }
      }

      LoginLinkButton(title: LoginCopy.signInAction, action: onSignInInstead)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(LoginAccessibility.chooseAccount)
  }
}
