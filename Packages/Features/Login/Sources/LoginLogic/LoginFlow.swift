import ATProtoClient
import Foundation
import Persistence

/// The result of a sign-in attempt.
public enum LoginOutcome: Sendable, Equatable {
  /// The session was created (or resumed) and the account recorded.
  case success(PersistedAccount)
  /// The server wants an emailed confirmation code.
  case needsAuthFactor
  /// The attempt failed with a mapped, user-presentable error.
  case failure(LoginError)
  /// The input was unusable and no network call was made; carries the
  /// field-level copy the form shows inline.
  case invalid(String)
}

/// Whether a stored account can be resumed as-is.
///
/// Port of the branch in `ChooseAccountForm.tsx`: an account with no access
/// token cannot resume and must go back through the sign-in form.
public enum ResumeDecision: Sendable, Equatable {
  /// The account has tokens; resume it.
  case resume
  /// No access token is stored; the user has to sign in again.
  case freshLogin

  /// The decision for an account.
  public static func forAccount(_ account: PersistedAccount) -> ResumeDecision {
    guard let access = account.accessJwt, !access.isEmpty else { return .freshLogin }
    return .resume
  }
}

/// The result of selecting a stored account.
public enum StoredAccountOutcome: Sendable, Equatable {
  /// The session was resumed and the account is current.
  case resumed(PersistedAccount)
  /// The account has no tokens, so the flow moved to the sign-in form with the
  /// handle prefilled.
  case needsFreshLogin(identifier: String)
  /// The resume failed.
  case failure(LoginError)
}

/// The sign-in flow.
///
/// Pure orchestration: it owns the step, the identifier, the target service,
/// and the mapped error for every failure. It has no UI dependency and no
/// MainActor requirement, so it can be driven and observed from any context
/// (and from Linux CI).
///
/// ## Observation
///
/// ``state`` is a value type that can be read at any time, and ``addListener``
/// registers a callback invoked with the new value after every change. The
/// class is `@unchecked Sendable` because the state and listener list are
/// guarded by a lock; the stored dependencies are all `Sendable`.
///
/// ## Concurrency
///
/// Sign-in is asynchronous, so ``state`` is not a lock on the network call: a
/// caller can read it while an attempt is in flight. `isProcessing` in the
/// state distinguishes "in flight" from the step that follows.
public final class LoginFlow: @unchecked Sendable {

  /// A state observer.
  public typealias Listener = @Sendable (LoginState) -> Void

  /// Builds the session hooks for an account, so callers can bridge session
  /// rotation into their own state stores.
  public typealias SessionHooksFactory = @Sendable (String) -> SessionHooks

  /// The transport every request in this flow uses.
  public let transport: HTTPTransport

  /// The account store, when the caller has one. Without it the flow still
  /// performs sign-in, but it cannot record the account.
  public let sessionStore: SessionStore?

  private let sessionHooksFactory: SessionHooksFactory
  private let lookupHandle: (@Sendable (String) async throws -> ResolvedPDSEndpoint)?

  private let lock = NSLock()
  private var listeners: [Listener] = []
  private var current: LoginState
  private var pending: PendingAttempt?

  /// The credentials of the in-flight attempt, retained so a 2FA retry can
  /// repeat the same `createSession` call with a token attached.
  private struct PendingAttempt {
    let service: String
    let fullIdentifier: String
    let password: String
  }

  /// Creates a flow.
  ///
  /// - Parameters:
  ///   - transport: network transport; injected so tests can script responses.
  ///   - sessionStore: the account store used to record a successful login.
  ///   - sessionHooksFactory: session hooks per account.
  ///   - lookupHandle: resolves a handle to its DID and PDS endpoint. Should
  ///     throw only for genuine network errors.
  public init(
    transport: HTTPTransport = URLSessionTransport(),
    sessionStore: SessionStore? = nil,
    sessionHooksFactory: @escaping SessionHooksFactory = { _ in SessionHooks() },
    lookupHandle: (@Sendable (String) async throws -> ResolvedPDSEndpoint)? = nil
  ) {
    self.transport = transport
    self.sessionStore = sessionStore
    self.sessionHooksFactory = sessionHooksFactory
    self.lookupHandle = lookupHandle
    self.current = LoginState()
  }

  // MARK: - Observation

  /// The current state.
  public var state: LoginState {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  /// Registers a state observer. The listener is retained for the flow's
  /// lifetime; it is called synchronously from whichever context mutated the
  /// state, so it must not block.
  public func addListener(_ listener: @escaping Listener) {
    lock.lock()
    listeners.append(listener)
    lock.unlock()
  }

  /// Mutates the state and notifies every observer.
  ///
  /// Observers are only woken when the value actually changed, so a caller that
  /// re-states an existing value does not emit a transition the view would have
  /// to discard.
  private func update(_ mutate: (inout LoginState) -> Void) {
    lock.lock()
    let previous = current
    mutate(&current)
    let snapshot = current
    let changed = snapshot != previous
    let observers = listeners
    lock.unlock()
    guard changed else { return }
    for observer in observers {
      observer(snapshot)
    }
  }

  // MARK: - Input

  /// Records the identifier.
  ///
  /// Notifies only when the value actually changes, so a `signIn` call that
  /// re-states the identifier the form already reported does not emit a
  /// duplicate transition. The step is left alone: failure is sticky (see
  /// ``LoginState/clearError()``), so a re-submission with the same identifier
  /// does not flip the form back to the credential step mid-retry.
  public func setIdentifier(_ identifier: String) {
    update { state in
      if state.identifier != identifier {
        state.setIdentifier(identifier)
      }
    }
  }

  /// Records the confirmation code the user typed.
  public func setAuthFactorToken(_ token: String) {
    update { $0.setAuthFactorToken(token) }
  }

  // MARK: - Service selection

  /// Moves to the manual service-address step.
  public func beginServicePicking() {
    update { $0.move(to: .pickingService) }
  }

  /// Leaves the service-address step, keeping whatever service was set.
  public func endServicePicking() {
    update { $0.move(to: .enteringCredentials) }
  }

  /// Chooses the default public PDS.
  public func selectDefaultService() {
    update { state in
      state.setService(LoginConstants.defaultService, override: nil)
      state.setServiceDescription(nil)
    }
  }

  /// Applies a manually typed service address.
  ///
  /// The address is normalized, then described before it is adopted: a server
  /// that cannot be described is not offered as a login target. The normalized
  /// URL is stored either way so the form can show what the user will hit.
  @discardableResult
  public func selectCustomService(
    _ raw: String
  ) async -> Result<ResolvedService, ServiceResolutionError> {
    switch ServiceURL.validate(raw) {
    case .empty, .invalid:
      return .failure(.invalidURL)
    case .valid(let normalized):
      do {
        let resolved = try await ServiceResolver.resolve(
          service: normalized, transport: transport)
        update { state in
          state.setService(resolved.service, override: resolved.service)
          state.setServiceDescription(resolved.description)
        }
        return .success(resolved)
      } catch let error as ServiceResolutionError {
        update { state in
          state.setService(normalized, override: normalized)
          state.setServiceDescription(nil)
        }
        return .failure(error)
      } catch {
        update { state in
          state.setService(normalized, override: normalized)
          state.setServiceDescription(nil)
        }
        return .failure(.failed(underlying: XRPCErrorShapes.shape(from: error)))
      }
    }
  }

  /// Describes the current service, for the preflight check the RN sign-in
  /// screen runs on mount and on every service change.
  @discardableResult
  public func refreshServiceDescription() async -> ServiceDescription? {
    let service = state.service
    guard let description = try? await ServiceResolver.describe(
      service: service, transport: transport)
    else {
      update { $0.setServiceDescription(nil) }
      return nil
    }
    update { $0.setServiceDescription(description) }
    return description
  }

  // MARK: - Sign in

  /// Signs in with a fresh identifier and password.
  ///
  /// Field validation happens first and never touches the network; failures
  /// after that are mapped through ``LoginErrorMapper``.
  public func signIn(identifier: String, password: String) async -> LoginOutcome {
    setIdentifier(identifier)
    // A fresh submission supersedes whatever the last attempt left behind, so
    // the failure step is cleared up front and the count is preserved.
    update { $0.clearError() }

    let normalized = LoginIdentifier.normalize(identifier)
    guard !normalized.isEmpty else {
      return .invalid(LoginStrings.pleaseEnterUsername)
    }
    guard !password.isEmpty else {
      return .invalid(LoginStrings.pleaseEnterPassword)
    }

    let selection = ServiceSelection(
      identifier: normalized,
      defaultService: LoginConstants.defaultService,
      override: state.serviceOverride,
      isDebounceSettled: true)
    let domains = state.availableUserDomains
    let fullIdentifier = LoginIdentifier.fullIdentifier(
      identifier: normalized, serviceProviderDomains: domains)

    update { $0.move(to: .signingIn) }

    let resolution: ServiceResolution
    do {
      resolution = try await selection.resolveService(
        identifier: normalized, lookupHandle: lookup)
    } catch {
      return fail(with: error)
    }

    return await attempt(
      service: resolution.service,
      fullIdentifier: fullIdentifier,
      password: password,
      authFactorToken: nil)
  }

  /// Retries the in-flight attempt with an emailed confirmation code.
  ///
  /// The password from the original attempt is reused: `createSession` is
  /// called again with `authFactorToken` attached, which is exactly the retry
  /// the RN form performs.
  public func retryWithAuthFactor(_ code: String) async -> LoginOutcome {
    setAuthFactorToken(code)

    guard let pending else {
      return .invalid(LoginStrings.pleaseEnterPassword)
    }
    guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .invalid(LoginStrings.invalidAuthFactorToken)
    }

    update { $0.move(to: .signingIn) }
    return await attempt(
      service: pending.service,
      fullIdentifier: pending.fullIdentifier,
      password: pending.password,
      authFactorToken: code.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// Returns to the credential step, discarding any retained attempt.
  public func cancelAuthFactor() {
    pending = nil
    update { state in
      state.setAuthFactorToken("")
      state.move(to: .enteringCredentials)
    }
  }

  /// Resets the flow to its initial state.
  public func reset() {
    pending = nil
    update { state in
      state.setIdentifier("")
      state.setAuthFactorToken("")
      state.setAccount(nil)
      state.resetFailedAttempts()
      state.setService(LoginConstants.defaultService, override: nil)
      state.setServiceDescription(nil)
      state.move(to: .enteringCredentials)
    }
  }

  /// Performs one `createSession` call and records the result.
  private func attempt(
    service: String,
    fullIdentifier: String,
    password: String,
    authFactorToken: String?
  ) async -> LoginOutcome {
    let normalizedService = ServiceURL.normalize(service) ?? service
    let requestBase = ServiceURL.requestBase(normalizedService)
    pending = PendingAttempt(
      service: requestBase, fullIdentifier: fullIdentifier, password: password)

    do {
      let session = try await PasswordSession.login(
        service: requestBase,
        identifier: fullIdentifier,
        password: password,
        authFactorToken: authFactorToken,
        hooks: sessionHooksFactory(fullIdentifier),
        transport: transport)
      let account = try await record(session: session)
      pending = nil
      update { state in
        state.setAccount(account)
        state.setAuthFactorToken("")
        state.move(to: .success)
      }
      return .success(account)
    } catch {
      return fail(with: error)
    }
  }

  /// Maps a thrown error onto the state and the caller-facing outcome.
  private func fail(with error: any Error) -> LoginOutcome {
    let loginError = LoginErrorMapper.map(error)
    if case .authFactorRequired = loginError {
      update { state in
        state.countFailedAttempt()
        state.setAuthFactorToken("")
        state.move(to: .needsAuthFactor)
      }
      return .needsAuthFactor
    }
    update { state in
      state.countFailedAttempt()
      state.move(to: .failed(loginError))
    }
    return .failure(loginError)
  }

  /// Whether an identifier is one whose PDS the flow would look up.
  ///
  /// Surfaced so a view can decide whether to show a "don't send my password
  /// to a non-Bluesky server" confirmation without re-deriving the rule.
  public static func requiresHostingProviderConfirmation(
    service: String, override: String?, did: String?, knownDIDs: [String]
  ) -> Bool {
    guard override == nil else { return false }
    guard !ServiceURL.isBlueskyHosted(service) else { return false }
    if let did, knownDIDs.contains(did) { return false }
    return true
  }

  /// Records a successful session.
  private func record(session: PasswordSession) async throws -> PersistedAccount {
    if let sessionStore {
      return try await sessionStore.addAccount(fromSession: session)
    }
    let data = try await session.sessionData()
    guard let account = SessionAccountMapping.account(from: data, service: data.service)
    else {
      throw SessionStore.StoreError.sessionUnavailable("login result had no session data")
    }
    return account
  }

  // MARK: - Stored accounts

  /// The accounts already on this device, most recently used first.
  public func storedAccounts() async -> [PersistedAccount] {
    await sessionStore?.snapshot().accounts ?? []
  }

  /// The DID of the account currently signed in, if any.
  public func currentAccountDID() async -> String? {
    await sessionStore?.snapshot().currentDID
  }

  /// Switches to a stored account, resuming its session.
  ///
  /// Mirrors `ChooseAccountForm.onSelect`: an account with no tokens cannot
  /// resume, so the flow moves back to the credential step with the handle
  /// prefilled rather than attempting a doomed refresh.
  public func signInWithStoredAccount(_ account: PersistedAccount) async -> StoredAccountOutcome {
    guard ResumeDecision.forAccount(account) == .resume else {
      update { state in
        state.setIdentifier(account.handle)
        state.move(to: .enteringCredentials)
      }
      return .needsFreshLogin(identifier: account.handle)
    }
    guard let sessionStore else {
      return .failure(
        .unexpected(message: LoginStrings.unableToContactService, underlying: nil))
    }

    update { $0.move(to: .signingIn) }
    do {
      try await sessionStore.switchToAccount(account.did)
      let resumed = try await sessionStore.resume(account: account)
      update { state in
        state.setAccount(resumed)
        state.setIdentifier(resumed.handle)
        state.move(to: .success)
      }
      return .resumed(resumed)
    } catch {
      let loginError = LoginErrorMapper.map(error)
      update { state in
        state.countFailedAttempt()
        state.move(to: .failed(loginError))
      }
      return .failure(loginError)
    }
  }

  /// Forgets a stored account entirely: tokens, entry, and caches.
  public func forgetAccount(_ did: String) async throws {
    guard let sessionStore else {
      throw SessionStore.StoreError.sessionUnavailable(did)
    }
    try await sessionStore.removeAccount(did)
  }

  // MARK: - Internals

  private func lookup(_ handle: String) async throws -> ResolvedPDSEndpoint? {
    guard let lookupHandle else { return nil }
    return try await lookupHandle(handle)
  }
}
