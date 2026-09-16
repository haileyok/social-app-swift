import Foundation
import LoginLogic
import Observation
import Persistence

/// The SwiftUI-facing adapter over ``LoginFlow``.
///
/// `LoginFlow` exposes a `Sendable` value state plus an `addListener` callback
/// rather than being `Observable` itself (it is deliberately usable off the main
/// actor and from Linux CI). This type is the bridge: it registers one listener,
/// republishes every transition on the main actor, and holds the bits of state
/// that are genuinely the view's own - the password (never stored in the flow's
/// state), the field-level validation line, and the preflight status.
///
/// Every decision still belongs to the flow. This type calls
/// ``LoginFlow/signIn(identifier:password:)``, ``LoginFlow/retryWithAuthFactor(_:)``,
/// ``LoginFlow/selectDefaultService()``, ``LoginFlow/selectCustomService(_:)``,
/// ``LoginFlow/signInWithStoredAccount(_:)`` and ``LoginFlow/forgetAccount(_:)``
/// and renders whatever they report; it re-derives no rule.
@MainActor
@Observable
public final class LoginViewModel {
  /// The flow's state, mirrored so SwiftUI re-reads it on change.
  public private(set) var state: LoginState

  /// The typed password. Held here, not in the flow, because the flow only
  /// needs it for the duration of an attempt (and retains it privately so a 2FA
  /// retry can repeat the call).
  public var password = ""

  /// The field-level validation copy, set when a submission was rejected before
  /// any network call (``LoginOutcome/invalid(_:)``).
  public private(set) var validationMessage: String?

  /// Accounts already on this device, most recently used first.
  public private(set) var storedAccounts: [PersistedAccount] = []

  /// The preflight status of the currently chosen service.
  public private(set) var serviceStatus: ServicePreflightStatus = .idle

  /// A message shown for an operation that is not the sign-in attempt itself,
  /// e.g. a failed "forget account".
  public private(set) var accountActionError: String?

  /// The auto-discovered hosting provider awaiting explicit approval.
  public private(set) var hostingProviderConfirmation: String?

  /// The resolved attempt retained while the confirmation is visible.
  private var preparedLogin: PreparedLogin?

  /// The flow this adapter renders.
  public let flow: LoginFlow

  /// The emails/identifiers of accounts the user asked to forget in this
  /// session, so the chooser can confirm before doing it.
  private var hasLoaded = false

  /// Creates an adapter over a flow.
  ///
  /// - Parameter flow: the logic flow. Defaults to a live one with no session
  ///   store, which is enough to render and validate the form (and is what the
  ///   debug entry point uses).
  public init(flow: LoginFlow = LoginFlow()) {
    self.flow = flow
    self.state = flow.state
    flow.addListener { [weak self] newState in
      Task { @MainActor in
        self?.state = newState
      }
    }
  }

  // MARK: - Derived view state

  /// The mapped failure the banner should render, when any.
  public var error: LoginError? { state.error }

  /// True while a sign-in attempt is in flight.
  public var isProcessing: Bool { state.isProcessing }

  /// The server address currently targeted, as the form displays it.
  public var serviceDisplay: String { ServiceSelection(identifier: state.identifier,
    override: state.serviceOverride).niceHost }

  /// Whether the form has enough input to attempt a sign-in.
  ///
  /// Deliberately permissive: an empty field is reported as a validation message
  /// on submit (the RN behaviour), not as a permanently disabled button, so the
  /// user gets a specific reason rather than a dead control.
  public var canSubmit: Bool { !isProcessing }

  // MARK: - Lifecycle

  /// Loads the stored accounts and runs the initial service preflight.
  ///
  /// Called once from the screen's `task`, matching the RN form's mount effect.
  public func load() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    await refreshStoredAccounts()
    await refreshServiceStatus()
  }

  /// Reloads the on-device accounts.
  public func refreshStoredAccounts() async {
    storedAccounts = await flow.storedAccounts()
  }

  /// Describes the chosen service and records the resulting status.
  ///
  /// Uses ``LoginFlow/refreshServiceDescription()`` so the flow's own state
  /// (`availableUserDomains`, which the identifier completion depends on) stays
  /// in step with what the picker shows.
  public func refreshServiceStatus() async {
    serviceStatus = .checking
    let described = await flow.refreshServiceDescription()
    serviceStatus = described.map { .ok($0) } ?? .unreachable
  }

  // MARK: - Input

  /// Records the identifier in the flow, so the state machine stays the source
  /// of truth for what will be submitted.
  public func setIdentifier(_ value: String) {
    validationMessage = nil
    flow.setIdentifier(value)
  }

  // MARK: - Sign in

  /// Resolves and submits the form, pausing before authentication when the
  /// handle points at an unfamiliar non-Bluesky hosting provider.
  public func signIn() async {
    validationMessage = nil
    accountActionError = nil
    hostingProviderConfirmation = nil
    preparedLogin = nil

    switch await flow.prepareSignIn(identifier: state.identifier, password: password) {
    case .invalid(let message):
      validationMessage = message
    case .failure(let error):
      apply(.failure(error))
    case .ready(let prepared):
      let knownDIDs = storedAccounts.map(\.did)
      if prepared.requiresHostingProviderConfirmation(knownDIDs: knownDIDs) {
        preparedLogin = prepared
        hostingProviderConfirmation = URL(string: prepared.service)?.host ?? prepared.service
      } else {
        apply(await flow.authenticate(prepared))
      }
    }
  }

  /// Continues an explicitly approved prepared login.
  public func confirmHostingProvider() async {
    guard let preparedLogin else { return }
    self.preparedLogin = nil
    hostingProviderConfirmation = nil
    apply(await flow.authenticate(preparedLogin))
  }

  /// Cancels before credentials are sent to the resolved provider.
  public func cancelHostingProvider() {
    preparedLogin = nil
    hostingProviderConfirmation = nil
    flow.cancelPreparedSignIn()
  }

  /// Retries the retained attempt with an emailed confirmation code.
  public func submitAuthFactor(_ code: String) async {
    validationMessage = nil
    apply(await flow.retryWithAuthFactor(code))
  }

  /// Leaves the 2FA step and returns to the credential form.
  public func cancelAuthFactor() {
    flow.cancelAuthFactor()
  }

  /// Maps an attempt outcome onto this adapter's own state.
  private func apply(_ outcome: LoginOutcome) {
    switch outcome {
    case .invalid(let message):
      // The only outcome that never reached the network; it renders inline
      // beside the fields rather than in the banner.
      validationMessage = message
    case .success:
      validationMessage = nil
    case .needsAuthFactor, .failure:
      validationMessage = nil
    }
  }

  // MARK: - Service selection

  /// Adopts the default Bluesky server.
  public func selectDefaultService() async {
    flow.selectDefaultService()
    await refreshServiceStatus()
  }

  /// Adopts a manually entered server address.
  ///
  /// Returns the failure copy when the address could not be described, so the
  /// picker can show it inline; the flow has already stored the normalized
  /// address either way.
  @discardableResult
  public func selectCustomService(_ raw: String) async -> String? {
    switch await flow.selectCustomService(raw) {
    case .success(let resolved):
      serviceStatus = .ok(resolved.description)
      return nil
    case .failure(let error):
      serviceStatus = .invalid(error.message)
      return error.message
    }
  }

  // MARK: - Stored accounts

  /// Resumes a stored account.
  @discardableResult
  public func resume(_ account: PersistedAccount) async -> StoredAccountOutcome {
    let outcome = await flow.signInWithStoredAccount(account)
    if case .failure(let error) = outcome {
      accountActionError = error.message
    } else {
      accountActionError = nil
    }
    return outcome
  }

  /// Forgets a stored account and refreshes the list.
  public func forget(_ account: PersistedAccount) async {
    do {
      try await flow.forgetAccount(account.did)
      accountActionError = nil
      await refreshStoredAccounts()
    } catch {
      accountActionError = LoginCopy.message(for: LoginErrorMapper.map(error))
    }
  }

  /// Resets the flow and the view-owned fields.
  public func reset() {
    flow.reset()
    password = ""
    validationMessage = nil
    accountActionError = nil
    preparedLogin = nil
    hostingProviderConfirmation = nil
  }
}

/// The service-preflight status the picker and the form's server row show.
public enum ServicePreflightStatus: Sendable, Equatable {
  /// No check has run yet.
  case idle
  /// A describeServer check is in flight.
  case checking
  /// The address answered like a PDS; carries its description.
  case ok(ServiceDescription?)
  /// The address could not be used; carries the user-facing reason.
  case invalid(String)

  /// True while a check is in flight.
  public var isChecking: Bool { self == .checking }
}

/// The failure reason for an unreachable service, in one place.
extension ServicePreflightStatus {
  /// The default copy for a host that did not answer.
  static var unreachable: ServicePreflightStatus {
    .invalid(LoginStrings.unableToContactService)
  }
}
