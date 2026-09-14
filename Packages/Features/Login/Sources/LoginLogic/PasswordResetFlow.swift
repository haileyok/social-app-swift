import ATProtoClient
import Domain
import Foundation
import Lexicons

/// Port of `checkAndFormatResetCode` from `src/lib/strings/password.ts`.
public enum ResetCode {
  /// Base32 alphabet, as the RN regex uses.
  private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

  /// Uppercases and inserts the separator dash, then validates.
  ///
  /// A 10-character input is read as two five-character halves and gains the
  /// dash; anything else must already be `XXXXX-XXXXX`. Returns `nil` when the
  /// code is not in that form.
  public static func format(_ code: String) -> String? {
    var fixed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if fixed.count == 10 {
      let index = fixed.index(fixed.startIndex, offsetBy: 5)
      fixed = "\(fixed[fixed.startIndex..<index])-\(fixed[index...])"
    }
    guard fixed.count == 11 else { return nil }
    let parts = fixed.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].count == 5, parts[1].count == 5 else { return nil }
    for character in fixed where character != "-" {
      guard alphabet.contains(character) else { return nil }
    }
    return fixed
  }
}

/// The pre-auth calls the password reset needs.
///
/// Extracted so tests can drive the flow without a network, and so the flow
/// package owns the exact request shapes.
public protocol PasswordResetService: Sendable {
  /// `com.atproto.server.requestPasswordReset`.
  func requestPasswordReset(service: String, email: String) async throws
  /// `com.atproto.server.resetPassword`.
  func resetPassword(service: String, token: String, password: String) async throws
}

/// The live implementation, over the shared XRPC client.
public struct LivePasswordResetService: PasswordResetService {
  private let transport: HTTPTransport

  public init(transport: HTTPTransport = URLSessionTransport()) {
    self.transport = transport
  }

  public func requestPasswordReset(service: String, email: String) async throws {
    let client = XrpcClient(
      baseURL: ServiceURL.requestBase(service), labelers: nil, transport: transport)
    let _: XrpcClient.EmptyResponse = try await client.procedure(
      "com.atproto.server.requestPasswordReset",
      body: Com.Atproto.ServerRequestPasswordReset_Input(email: email))
  }

  public func resetPassword(service: String, token: String, password: String) async throws {
    let client = XrpcClient(
      baseURL: ServiceURL.requestBase(service), labelers: nil, transport: transport)
    let _: XrpcClient.EmptyResponse = try await client.procedure(
      "com.atproto.server.resetPassword",
      body: Com.Atproto.ServerResetPassword_Input(password: password, token: token))
  }
}

/// Where the forgotten-password journey is.
public enum PasswordResetStep: Sendable, Equatable {
  /// Collecting the account email.
  case enteringEmail
  /// `requestPasswordReset` is in flight.
  case requestingReset
  /// The email was sent; collecting the reset code and the new password.
  case enteringNewPassword
  /// `resetPassword` is in flight.
  case settingPassword
  /// The password was changed.
  case passwordUpdated
  /// The step failed.
  case failed(PasswordResetError)
}

/// Why a password-reset step failed.
public enum PasswordResetError: Error, Sendable, Equatable {
  /// The typed email is not usable.
  case invalidEmail
  /// The typed reset code is not in `XXXXX-XXXXX` form.
  case invalidCode
  /// The new password is empty.
  case emptyPassword
  /// The service could not be reached.
  case networkOffline(underlying: XRPCErrorShape?)
  /// The server rejected the request.
  case failed(message: String, underlying: XRPCErrorShape?)

  /// The user-facing copy.
  public var message: String {
    switch self {
    case .invalidEmail: LoginStrings.invalidEmail
    case .invalidCode: LoginStrings.invalidResetCode
    case .emptyPassword: LoginStrings.pleaseEnterNewPassword
    case .networkOffline: LoginStrings.unableToContactService
    case .failed(let message, _): message
    }
  }

  /// The underlying lex error, when the server produced one.
  public var underlying: XRPCErrorShape? {
    switch self {
    case .invalidEmail, .invalidCode, .emptyPassword: nil
    case .networkOffline(let underlying), .failed(_, let underlying): underlying
    }
  }

}

/// The reset state, read by the reset screens.
public struct PasswordResetState: Sendable, Equatable {
  public private(set) var step: PasswordResetStep
  public private(set) var service: String
  public private(set) var email: String
  public private(set) var resetCode: String

  init(
    step: PasswordResetStep = .enteringEmail,
    service: String = LoginConstants.defaultService,
    email: String = "",
    resetCode: String = ""
  ) {
    self.step = step
    self.service = service
    self.email = email
    self.resetCode = resetCode
  }

  /// True while a request is in flight.
  public var isProcessing: Bool {
    step == .requestingReset || step == .settingPassword
  }

  /// The failure being shown, when any.
  public var error: PasswordResetError? {
    if case .failed(let error) = step { return error }
    return nil
  }

  mutating func move(to step: PasswordResetStep) { self.step = step }
  mutating func setService(_ value: String) { service = value }
  mutating func setEmail(_ value: String) { email = value }
  mutating func setResetCode(_ value: String) { resetCode = value }
}

/// The forgotten-password flow.
///
/// Port of `ForgotPasswordForm` plus `SetNewPasswordForm`, sharing the service
/// address with the sign-in screen exactly as the RN `Login` screen shares its
/// `serviceUrl` state.
public final class PasswordResetFlow: @unchecked Sendable {
  /// A state observer.
  public typealias Listener = @Sendable (PasswordResetState) -> Void

  private let service: PasswordResetService
  private let emailValidator: @Sendable (String) -> Bool
  private let lock = NSLock()
  private var listeners: [Listener] = []
  private var current: PasswordResetState

  /// Creates a flow.
  ///
  /// - Parameters:
  ///   - service: the pre-auth calls. Injected for testing.
  ///   - serviceURL: the initial service address.
  ///   - emailValidator: the email check. The RN form delegates to its
  ///     `EmailValidator` (which consults a public-suffix list), so it is a
  ///     parameter here rather than a rule baked into this package.
  public init(
    service: PasswordResetService,
    serviceURL: String = LoginConstants.defaultService,
    emailValidator: @escaping @Sendable (String) -> Bool = PasswordResetFlow.defaultEmailValidator
  ) {
    self.service = service
    self.emailValidator = emailValidator
    self.current = PasswordResetState(service: serviceURL)
  }

  /// A pragmatic email check: exactly one `@`, a non-empty local part, and a
  /// dotted domain. Deliberately conservative; the caller can supply the
  /// public-suffix-aware validator the RN app uses.
  public static let defaultEmailValidator: @Sendable (String) -> Bool = { email in
    let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return false }
    return parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
  }

  /// The current state.
  public var state: PasswordResetState {
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

  private func update(_ mutate: (inout PasswordResetState) -> Void) {
    lock.lock()
    mutate(&current)
    let snapshot = current
    let observers = listeners
    lock.unlock()
    for observer in observers { observer(snapshot) }
  }

  /// Records the service address shared with the sign-in screen.
  public func setServiceURL(_ raw: String) {
    let normalized = ServiceURL.normalize(raw) ?? raw
    update { $0.setService(normalized) }
  }

  /// Records the typed email.
  public func setEmail(_ email: String) {
    update { $0.setEmail(email) }
  }

  /// Records the typed reset code, re-validating on blur like the RN form.
  public func setResetCode(_ code: String) {
    update { state in
      state.setResetCode(code)
      if let formatted = ResetCode.format(code) {
        state.setResetCode(formatted)
      }
    }
  }

  /// Requests the reset email.
  ///
  /// Returns `true` when the server accepted the request, which is the signal
  /// to move to the new-password step.
  @discardableResult
  public func requestReset() async -> Bool {
    let email = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard emailValidator(email) else {
      update { $0.move(to: .failed(.invalidEmail)) }
      return false
    }
    update { state in
      state.setEmail(email)
      state.move(to: .requestingReset)
    }
    do {
      try await service.requestPasswordReset(service: state.service, email: email)
      update { $0.move(to: .enteringNewPassword) }
      return true
    } catch {
      update { $0.move(to: .failed(Self.map(error))) }
      return false
    }
  }

  /// Submits the reset code and the new password.
  @discardableResult
  public func setNewPassword(_ password: String) async -> Bool {
    guard let formatted = ResetCode.format(state.resetCode) else {
      update { $0.move(to: .failed(.invalidCode)) }
      return false
    }
    guard !password.isEmpty else {
      update { $0.move(to: .failed(.emptyPassword)) }
      return false
    }
    update { state in
      state.setResetCode(formatted)
      state.move(to: .settingPassword)
    }
    do {
      try await service.resetPassword(
        service: state.service, token: formatted, password: password)
      update { $0.move(to: .passwordUpdated) }
      return true
    } catch {
      update { $0.move(to: .failed(Self.map(error))) }
      return false
    }
  }

  /// Returns to the email step.
  public func backToEmail() {
    update { $0.move(to: .enteringEmail) }
  }

  /// Resets the flow.
  public func reset() {
    update { state in
      state.setEmail("")
      state.setResetCode("")
      state.move(to: .enteringEmail)
    }
  }

  /// Maps a thrown error onto a reset failure.
  private static func map(_ error: any Error) -> PasswordResetError {
    let shape = XRPCErrorShapes.shape(from: error)
    let subject = XRPCErrorShapes.subject(for: error)
    if ErrorStrings.isNetworkError(subject) {
      return .networkOffline(underlying: shape)
    }
    return .failed(message: ErrorStrings.cleanError(subject), underlying: shape)
  }
}
