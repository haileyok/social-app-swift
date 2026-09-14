import Foundation

/// The change-handle flow's state, as data.
///
/// Port of the state spread across `ChangeHandleDialog.tsx`: which page is
/// showing, what has been typed, whether the field is valid, and the
/// verification/submission results. The flow type below owns the transitions.
public struct ChangeHandleState: Sendable, Equatable {
  /// Which page of the dialog is showing.
  public var page: ChangeHandlePage
  /// The subdomain typed on the provided-handle page.
  public var subdomain: String
  /// The domain typed on the own-handle page.
  public var domain: String
  /// Which ownership proof the user selected.
  public var verificationMethod: DomainVerificationMethod
  /// The custom-domain verification result, once a verification ran.
  public var verification: DomainVerificationOutcome?
  /// Whether the handle submission is in flight.
  public var isSubmitting: Bool
  /// The submission error message, if the last attempt failed.
  public var error: String?
  /// Whether the last submission succeeded.
  public var didSucceed: Bool
  /// The account's current handle, so the "will remain reserved" notice can be
  /// decided.
  public var currentHandle: String?
  /// Whether the account carries a verification badge, which a handle change
  /// would forfeit.
  public var isVerifiedAccount: Bool

  public init(
    page: ChangeHandlePage = .providedHandle,
    subdomain: String = "",
    domain: String = "",
    verificationMethod: DomainVerificationMethod = .dns,
    verification: DomainVerificationOutcome? = nil,
    isSubmitting: Bool = false,
    error: String? = nil,
    didSucceed: Bool = false,
    currentHandle: String? = nil,
    isVerifiedAccount: Bool = false
  ) {
    self.page = page
    self.subdomain = subdomain
    self.domain = domain
    self.verificationMethod = verificationMethod
    self.verification = verification
    self.isSubmitting = isSubmitting
    self.error = error
    self.didSucceed = didSucceed
    self.currentHandle = currentHandle
    self.isVerifiedAccount = isVerifiedAccount
  }

  /// Whether the provided-handle field is currently invalid.
  ///
  /// The validity test needs the provider's domain, so it is derived by
  /// ``ChangeHandleFlow/validation(host:)`` rather than stored.
  public var isVerified: Bool {
    verification == .verified
  }

  /// Whether the current handle is a `.bsky.social` one, which RN says will
  /// remain reserved after a change.
  public var currentHandleStaysReserved: Bool {
    currentHandle?.hasSuffix(".bsky.social") ?? false
  }
}

/// The change-handle flow.
///
/// Pure orchestration over ``HandleService`` and ``HandleAvailabilityChecking``:
/// it owns the dialog state and every transition, and has no UI dependency.
/// The class is `@unchecked Sendable` because the state is lock-guarded.
public final class ChangeHandleFlow: @unchecked Sendable {
  /// A state observer.
  public typealias Listener = @Sendable (ChangeHandleState) -> Void

  private let handles: HandleService
  private let availability: HandleAvailabilityChecking
  private let lock = NSLock()
  private var listeners: [Listener] = []
  private var current: ChangeHandleState

  public init(
    handles: HandleService,
    availability: HandleAvailabilityChecking,
    state: ChangeHandleState = ChangeHandleState()
  ) {
    self.handles = handles
    self.availability = availability
    self.current = state
  }

  /// The current state.
  public var state: ChangeHandleState {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  /// Registers a state observer.
  public func addListener(_ listener: @escaping Listener) {
    lock.lock()
    listeners.append(listener)
    lock.unlock()
  }

  private func update(_ mutate: (inout ChangeHandleState) -> Void) {
    lock.lock()
    let previous = current
    mutate(&current)
    let snapshot = current
    let changed = snapshot != previous
    let observers = listeners
    lock.unlock()
    guard changed else { return }
    for observer in observers { observer(snapshot) }
  }

  // MARK: - Page and field input

  /// Switches between the provided-handle and own-handle pages, clearing the
  /// verification result as RN's `setPage` effectively does by unmounting the
  /// other page's hook.
  public func setPage(_ page: ChangeHandlePage) {
    update { state in
      state.page = page
      state.verification = nil
    }
  }

  /// Records the subdomain being typed.
  public func setSubdomain(_ value: String) {
    update { state in
      state.subdomain = value
      state.error = nil
    }
  }

  /// Records the custom domain being typed, resetting verification (RN's
  /// `resetVerification` runs on every `onChangeText`).
  public func setDomain(_ value: String) {
    update { state in
      state.domain = value
      state.verification = nil
      state.error = nil
    }
  }

  /// Selects the ownership-proof method.
  public func setVerificationMethod(_ method: DomainVerificationMethod) {
    update { $0.verificationMethod = method }
  }

  /// Records the account context the screen needs for its notices.
  public func setAccountContext(currentHandle: String?, isVerified: Bool) {
    update { state in
      state.currentHandle = currentHandle
      state.isVerifiedAccount = isVerified
    }
  }

  // MARK: - Provided-handle page

  /// The validation for the subdomain, under the provider's first domain.
  public func validation(host: String) -> ServiceHandleValidation {
    HandleRules.validateServiceHandle(state.subdomain, userDomain: host)
  }

  /// The full handle the subdomain would become.
  public func proposedServiceHandle(host: String) -> String {
    HandleRules.createFullHandle(name: state.subdomain, domain: host)
  }

  /// Submits a subdomain under the provider's domain.
  ///
  /// Validation happens first and never touches the network. A name the PDS
  /// would reject never reaches it.
  public func submitServiceHandle(
    host: String, availabilityServiceDID: String
  ) async -> Result<Void, SettingsError> {
    let validation = self.validation(host: host)
    guard !validation.isInvalid else {
      let message = ChangeHandleStrings.invalidHandle
      update { $0.error = message }
      return .failure(.invalidHandle(message))
    }
    guard validation.frontLengthNotTooShort, validation.frontLengthNotTooLong else {
      let message = ChangeHandleStrings.invalidHandle
      update { $0.error = message }
      return .failure(.invalidHandle(message))
    }
    let handle = proposedServiceHandle(host: host)
    if let taken = await availabilityFailure(handle: handle, serviceDID: availabilityServiceDID) {
      return taken
    }
    return await submit(handle: handle)
  }

  // MARK: - Own-handle page

  /// Verifies a custom domain resolves to the signed-in account.
  ///
  /// Port of the `verify` mutation in `OwnHandlePage`: resolve the domain, then
  /// compare the DID against the account's. `resolveHandle` is also reused here
  /// for a domain the user typed, which is why the flow takes the expected DID
  /// rather than reading it from a session.
  public func verifyDomain(expectedDID: String) async -> DomainVerificationOutcome {
    let domain = state.domain.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !domain.isEmpty else {
      update { $0.verification = nil }
      return .unresolved
    }
    do {
      let resolved = try await handles.resolveHandle(domain)
      let outcome: DomainVerificationOutcome =
        resolved == expectedDID ? .verified : .didMismatch(received: resolved)
      update { $0.verification = outcome }
      return outcome
    } catch {
      update { $0.verification = .unresolved }
      return .unresolved
    }
  }

  /// Submits the verified custom domain as the new handle.
  ///
  /// RN only enables the button once the domain is verified; the guard is
  /// reproduced so a caller cannot submit an unverified domain through this
  /// path.
  public func submitVerifiedDomain(
    availabilityServiceDID: String
  ) async -> Result<Void, SettingsError> {
    guard state.verification == .verified else {
      let message = ChangeHandleStrings.failedToVerify
      update { $0.error = message }
      return .failure(.unverifiedDomain(message))
    }
    let domain = state.domain.trimmingCharacters(in: .whitespacesAndNewlines)
    if let taken = await availabilityFailure(handle: domain, serviceDID: availabilityServiceDID) {
      return taken
    }
    return await submit(handle: domain)
  }

  // MARK: - Shared submission

  /// Runs the availability check and maps a taken handle onto an error.
  private func availabilityFailure(
    handle: String, serviceDID: String
  ) async -> Result<Void, SettingsError>? {
    do {
      let result = try await availability.checkHandleAvailability(
        handle: handle, serviceDID: serviceDID)
      guard case .unavailable = result else { return nil }
      update { $0.error = ChangeHandleStrings.handleTaken }
      return .failure(.handleTaken(ChangeHandleStrings.handleTaken))
    } catch {
      // A failed availability check does not block the submission; the update
      // call has its own error path. RN's typeahead silently ignores failures.
      return nil
    }
  }

  /// Calls `updateHandle` and records the outcome.
  private func submit(handle: String) async -> Result<Void, SettingsError> {
    update { state in
      state.isSubmitting = true
      state.error = nil
      state.didSucceed = false
    }
    do {
      try await handles.updateHandle(handle)
      update { state in
        state.isSubmitting = false
        state.didSucceed = true
        state.currentHandle = handle
      }
      return .success(())
    } catch {
      let mapped = ChangeHandleErrors.map(error)
      update { state in
        state.isSubmitting = false
        state.error = mapped.message
      }
      return .failure(mapped)
    }
  }
}

/// The user-facing copy the change-handle screens show.
public enum ChangeHandleStrings {
  /// `Handle already taken. Please try a different one.`
  public static let handleTaken = "Handle already taken. Please try a different one."
  /// `This handle is reserved. Please try a different one.`
  public static let handleReserved = "This handle is reserved. Please try a different one."
  /// `Handle too long. Please try a shorter one.`
  public static let handleTooLong = "Handle too long. Please try a shorter one."
  /// `Invalid handle. Please try a different one.`
  public static let invalidHandle = "Invalid handle. Please try a different one."
  /// `Rate limit exceeded - you've tried to change your handle too many times in a short period. Please wait a minute before trying again.`
  public static let rateLimitExceeded =
    "Rate limit exceeded - you've tried to change your handle too many times in a short "
    + "period. Please wait a minute before trying again."
  /// `Failed to change handle. Please try again.`
  public static let failedToChange = "Failed to change handle. Please try again."
  /// `Failed to verify handle. Please try again.`
  public static let failedToVerify = "Failed to verify handle. Please try again."
  /// `Handle changed!`
  public static let handleChanged = "Handle changed!"
  /// `Domain verified!`
  public static let domainVerified = "Domain verified!"
}

/// Maps a failed handle change onto the message `ChangeHandleError` shows.
///
/// Port of the string-prefix matching in `ChangeHandleDialog.tsx`. The RN code
/// inspects `error.message` with `startsWith`/`===`; the same wire messages are
/// matched here.
public enum ChangeHandleErrors {
  /// The exact message RN recognizes for each condition.
  static let knownMessages: [(match: String, isPrefix: Bool, result: String)] = [
    ("Handle already taken", true, ChangeHandleStrings.handleTaken),
    ("Reserved handle", false, ChangeHandleStrings.handleReserved),
    ("Handle too long", false, ChangeHandleStrings.handleTooLong),
    ("Input/handle must be a valid handle", false, ChangeHandleStrings.invalidHandle),
    ("Rate Limit Exceeded", false, ChangeHandleStrings.rateLimitExceeded),
  ]

  /// Maps a thrown error onto its user-facing message.
  public static func map(_ error: any Error) -> SettingsError {
    let message = SettingsError.message(from: error)
    for known in knownMessages {
      let matches = known.isPrefix ? message.hasPrefix(known.match) : message == known.match
      if matches {
        return SettingsError.handleChange(message: known.result)
      }
    }
    return SettingsError.handleChange(message: ChangeHandleStrings.failedToChange)
  }
}
