import ATProtoClient
import Foundation
import Persistence

/// Where the sign-in form is, from the flow's point of view.
///
/// Port of the `Forms` enum in `screens/Login/index.tsx`, restricted to the
/// steps that carry logic. `SetNewPassword` and `PasswordUpdated` live in
/// ``PasswordResetFlow`` because they are reached from the forgot-password
/// branch rather than the sign-in branch.
public enum LoginStep: Sendable, Equatable {
  /// Collecting identifier and password.
  case enteringCredentials
  /// Choosing from accounts already on this device.
  case choosingAccount
  /// Collecting a service address for a manual override.
  case pickingService
  /// The server demanded an emailed confirmation code.
  case needsAuthFactor
  /// A sign-in attempt is in flight.
  case signingIn
  /// A sign-in attempt succeeded.
  case success
  /// A sign-in attempt failed.
  case failed(LoginError)
}

/// The full state of the sign-in flow.
///
/// A value type so any observer can hold it without sharing mutable state, and
/// an `Equatable` one so tests can assert transitions directly.
public struct LoginState: Sendable, Equatable {
  /// The current step.
  public private(set) var step: LoginStep
  /// The identifier as typed.
  public private(set) var identifier: String
  /// The service currently targeted, normalized.
  public private(set) var service: String
  /// A manual service override, when the user set one.
  public private(set) var serviceOverride: String?
  /// The described service, once a preflight check has succeeded.
  public private(set) var serviceDescription: ServiceDescription?
  /// The confirmation code the user typed, when one is needed.
  public private(set) var authFactorToken: String
  /// How many attempts have failed, for the sign-in analytics the RN form
  /// counts and for back-off decisions.
  public private(set) var failedAttemptCount: Int
  /// The account that was signed in, once the flow succeeds.
  public private(set) var account: PersistedAccount?

  init(
    step: LoginStep = .enteringCredentials,
    identifier: String = "",
    service: String = LoginConstants.defaultService,
    serviceOverride: String? = nil,
    serviceDescription: ServiceDescription? = nil,
    authFactorToken: String = "",
    failedAttemptCount: Int = 0,
    account: PersistedAccount? = nil
  ) {
    self.step = step
    self.identifier = identifier
    self.service = service
    self.serviceOverride = serviceOverride
    self.serviceDescription = serviceDescription
    self.authFactorToken = authFactorToken
    self.failedAttemptCount = failedAttemptCount
    self.account = account
  }

  /// True while an attempt is in flight.
  public var isProcessing: Bool { step == .signingIn }

  /// True when the flow is waiting for a confirmation code.
  public var needsAuthFactor: Bool { step == .needsAuthFactor }

  /// The described handle domains, for identifier completion.
  public var availableUserDomains: [String] {
    serviceDescription?.availableUserDomains ?? []
  }

  /// The failure the flow is showing, when any.
  public var error: LoginError? {
    if case .failed(let error) = step { return error }
    return nil
  }

  mutating func move(to step: LoginStep) {
    self.step = step
  }

  /// Leaves the failure step for the credential step, preserving the failure
  /// count. Used when a new submission supersedes a shown error.
  mutating func clearError() {
    if case .failed = step {
      step = .enteringCredentials
    }
  }

  mutating func setIdentifier(_ value: String) {
    identifier = value
  }

  mutating func setService(_ value: String, override: String?) {
    service = value
    serviceOverride = override
  }

  mutating func setServiceDescription(_ value: ServiceDescription?) {
    serviceDescription = value
  }

  mutating func setAuthFactorToken(_ value: String) {
    authFactorToken = value
  }

  mutating func countFailedAttempt() {
    failedAttemptCount += 1
  }

  mutating func resetFailedAttempts() {
    failedAttemptCount = 0
  }

  mutating func setAccount(_ value: PersistedAccount?) {
    account = value
  }
}
