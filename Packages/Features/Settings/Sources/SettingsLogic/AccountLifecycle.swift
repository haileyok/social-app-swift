import ATProtoClient
import Foundation
import Lexicons
import SwiftAtproto

/// The account-lifecycle operations the account screens need.
///
/// Port of the calls in `DeactivateAccountDialog.tsx`,
/// `DeleteAccountDialog.tsx` and `ExportCarDialog.tsx`. All are PDS calls
/// against the account's own host except the repo export, which is also a PDS
/// read but returns CAR bytes rather than JSON.
public protocol AccountLifecycleService: Sendable {
  /// `com.atproto.server.deactivateAccount`
  func deactivateAccount() async throws
  /// `com.atproto.server.requestAccountDelete` - asks the PDS to email a
  /// confirmation code.
  func requestAccountDelete() async throws
  /// `com.atproto.server.deleteAccount` - consumes the emailed code.
  func deleteAccount(did: String, password: String, token: String) async throws
}

/// The live ``AccountLifecycleService``.
public struct LiveAccountLifecycleService: AccountLifecycleService {
  private let client: XrpcClient
  private let authorization: @Sendable () async throws -> String?

  public init(
    client: XrpcClient,
    authorization: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    self.client = client
    self.authorization = authorization
  }

  public func deactivateAccount() async throws {
    let input = Com.Atproto.ServerDeactivateAccount_Input()
    _ = try await client.procedure(
      "com.atproto.server.deactivateAccount", body: input,
      authorization: try await authorization()) as XrpcClient.EmptyResponse
  }

  public func requestAccountDelete() async throws {
    /*
     * The endpoint declares a wildcard content type and takes an empty body.
     * Passing `nil` sends no body bytes at all, which is what the RN call does.
     */
    _ = try await client.procedure(
      "com.atproto.server.requestAccountDelete",
      authorization: try await authorization()) as XrpcClient.EmptyResponse
  }

  public func deleteAccount(did: String, password: String, token: String) async throws {
    let input = Com.Atproto.ServerDeleteAccount_Input(
      did: FormatString<DID>(rawValue: did), password: password, token: token)
    _ = try await client.procedure(
      "com.atproto.server.deleteAccount", body: input,
      authorization: try await authorization()) as XrpcClient.EmptyResponse
  }
}

/// The delete-account dialog's steps.
///
/// Port of the `Step` enum in `DeleteAccountDialog.tsx`.
public enum DeleteAccountStep: String, Sendable, Equatable, CaseIterable {
  /// Ask the server to email a confirmation code.
  case sendCode
  /// Enter the emailed code.
  case verifyCode
  /// Confirm the deletion with the code and the account password.
  case confirmDeletion
}

/// Password validation for the delete-confirmation step.
public enum DeleteAccountRules {
  /// `PASSWORD_MIN_LENGTH` in `DeleteAccountDialog.tsx`.
  public static let passwordMinLength = 8
  /// Any whitespace, stripped from the confirmation code before it is sent.
  public static let whitespacePattern = "\\s"

  /// `isPasswordValid`: at least 8 characters.
  public static func isPasswordValid(_ password: String) -> Bool {
    password.count >= passwordMinLength
  }

  /// Strips every whitespace character from the confirmation code.
  ///
  /// RN does `confirmCode.replace(/\s/gu, '')`, so a code pasted with a space
  /// or newline still works.
  public static func sanitizeConfirmationCode(_ code: String) -> String {
    code.replacingOccurrences(
      of: whitespacePattern, with: "", options: .regularExpression)
  }
}

/// The delete-account flow's state.
public struct DeleteAccountState: Sendable, Equatable {
  /// Which step is showing.
  public var step: DeleteAccountStep
  /// How many times a code has been requested, so a resend can be offered.
  public var emailSentCount: Int
  /// Whether a code request is in flight.
  public var isSendingCode: Bool
  /// The code the user typed.
  public var confirmCode: String
  /// The account password.
  public var password: String
  /// The error message for the current step, if any.
  public var error: String?
  /// Whether the deletion succeeded.
  public var didDelete: Bool

  public init(
    step: DeleteAccountStep = .sendCode,
    emailSentCount: Int = 0,
    isSendingCode: Bool = false,
    confirmCode: String = "",
    password: String = "",
    error: String? = nil,
    didDelete: Bool = false
  ) {
    self.step = step
    self.emailSentCount = emailSentCount
    self.isSendingCode = isSendingCode
    self.confirmCode = confirmCode
    self.password = password
    self.error = error
    self.didDelete = didDelete
  }

  /// Whether the confirm step's inputs are complete enough to submit.
  public var canSubmitDeletion: Bool {
    !DeleteAccountRules.sanitizeConfirmationCode(confirmCode).isEmpty
      && DeleteAccountRules.isPasswordValid(password)
  }
}

/// The delete-account flow.
///
/// Port of `DeleteAccountDialog.tsx`'s three steps. The RN code also calls the
/// chat service's `deleteAccount` first; that call is a caller-supplied hook
/// here (`onBeforeDelete`) because `SettingsLogic` does not depend on the chat
/// client, and the ordering is preserved.
///
/// `@unchecked Sendable`: the state is lock-guarded.
public final class DeleteAccountFlow: @unchecked Sendable {
  /// A state observer.
  public typealias Listener = @Sendable (DeleteAccountState) -> Void

  private let service: AccountLifecycleService
  private let onBeforeDelete: @Sendable () async throws -> Void
  private let lock = NSLock()
  private var listeners: [Listener] = []
  private var current: DeleteAccountState

  public init(
    service: AccountLifecycleService,
    state: DeleteAccountState = DeleteAccountState(),
    onBeforeDelete: @escaping @Sendable () async throws -> Void = {}
  ) {
    self.service = service
    self.onBeforeDelete = onBeforeDelete
    self.current = state
  }

  /// The current state.
  public var state: DeleteAccountState {
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

  private func update(_ mutate: (inout DeleteAccountState) -> Void) {
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

  /// Records the code the user typed.
  public func setConfirmCode(_ code: String) {
    update { $0.confirmCode = code }
  }

  /// Records the password.
  public func setPassword(_ password: String) {
    update { $0.password = password }
  }

  /// Requests the emailed confirmation code and advances to the verify step.
  ///
  /// A request already in flight is ignored, matching RN's `emailState`
  /// pending guard.
  public func sendCode() async -> Result<Void, SettingsError> {
    guard !state.isSendingCode else { return .success(()) }
    update { state in
      state.isSendingCode = true
      state.error = nil
    }
    do {
      try await service.requestAccountDelete()
      update { state in
        state.isSendingCode = false
        state.emailSentCount += 1
        state.step = .verifyCode
      }
      return .success(())
    } catch {
      let mapped = SettingsError.accountAction(
        message: SettingsError.message(from: error),
        raw: SettingsError.rawMessage(from: error))
      update { state in
        state.isSendingCode = false
        state.error = mapped.message
      }
      return .failure(mapped)
    }
  }

  /// Moves to the confirm step.
  public func beginConfirmation() {
    update { state in
      state.error = nil
      state.step = .confirmDeletion
    }
  }

  /// Performs the deletion.
  ///
  /// The pre-delete hook (the chat-service call) runs first, then
  /// `deleteAccount`. A failure resets the code and password and returns to the
  /// verify step, which is what RN does so the user can re-enter a fresh code.
  public func confirmDeletion(did: String) async -> Result<Void, SettingsError> {
    let state = self.state
    update { $0.error = nil }
    guard !did.isEmpty else {
      let mapped = SettingsError.accountAction(message: SettingsStrings.invalidDid)
      update { $0.error = mapped.message }
      return .failure(mapped)
    }
    let token = DeleteAccountRules.sanitizeConfirmationCode(state.confirmCode)
    do {
      try await onBeforeDelete()
      try await service.deleteAccount(did: did, password: state.password, token: token)
      update { $0.didDelete = true }
      return .success(())
    } catch {
      let mapped = SettingsError.accountAction(
        message: SettingsError.message(from: error),
        raw: SettingsError.rawMessage(from: error))
      update { state in
        state.error = mapped.message
        state.confirmCode = ""
        state.password = ""
        state.step = .verifyCode
      }
      return .failure(mapped)
    }
  }
}

/// The deactivate-account flow.
///
/// Port of `DeactivateAccountDialog.tsx`. One call; the interesting part is the
/// error mapping, which has an app-password-specific message because the
/// app-password scope cannot deactivate.
public struct DeactivateAccountFlow: Sendable {
  private let service: AccountLifecycleService

  public init(service: AccountLifecycleService) {
    self.service = service
  }

  /// Runs the deactivation.
  ///
  /// A caller logs the account out on success; that side effect belongs to the
  /// session layer, not here.
  public func deactivate() async -> Result<Void, SettingsError> {
    do {
      try await service.deactivateAccount()
      return .success(())
    } catch {
      let message = SettingsError.message(from: error)
      if message == "Bad token scope" {
        return .failure(
          .accountAction(message: SettingsStrings.deactivateAppPassword, raw: message))
      }
      return .failure(
        .accountAction(message: SettingsStrings.deactivateFailed, raw: message))
    }
  }
}

/// The repo-export request the account screen's export dialog makes.
///
/// Port of `ExportCarDialog.tsx`'s `download`: `com.atproto.sync.getRepo` with
/// the account DID, returning CAR bytes. The URL builder is exposed separately
/// because a view layer that hands the URL to a downloader needs it, and
/// because it makes the wire shape assertable on Linux.
public struct ExportDataRequest: Sendable, Equatable {
  /// The endpoint, relative to the client's base URL.
  public let path: String
  /// Query parameters in the order the client emits them.
  public let parameters: [(name: String, value: String?)]
  /// The content type the bytes are saved as.
  public let contentType: String
  /// The suggested file name.
  public let fileName: String

  public static func == (lhs: ExportDataRequest, rhs: ExportDataRequest) -> Bool {
    lhs.path == rhs.path && lhs.contentType == rhs.contentType
      && lhs.fileName == rhs.fileName
      && lhs.parameters.map(\.name) == rhs.parameters.map(\.name)
      && lhs.parameters.map(\.value) == rhs.parameters.map(\.value)
  }
}

/// Builds the repo-export requests, ported from `ExportCarDialog.tsx`.
public enum ExportData {
  /// The full-repo export: `com.atproto.sync.getRepo?did=...`.
  public static func repoRequest(did: String) -> ExportDataRequest {
    ExportDataRequest(
      path: SettingsConstants.getRepoPath,
      parameters: [("did", did)],
      contentType: SettingsConstants.carContentType,
      fileName: "repo.car")
  }

  /// The incremental export: `com.atproto.sync.getCheckout?did=...`.
  ///
  /// RN's dialog only calls `getRepo`, but the task names `getCheckout` as part
  /// of the export surface, and it is the same shape with a different endpoint.
  public static func checkoutRequest(did: String) -> ExportDataRequest {
    ExportDataRequest(
      path: SettingsConstants.getCheckoutPath,
      parameters: [("did", did)],
      contentType: SettingsConstants.carContentType,
      fileName: "repo.car")
  }

  /// The absolute URL for a request against a client base URL.
  public static func url(for request: ExportDataRequest, baseURL: String) -> String {
    XrpcClient(baseURL: baseURL, transport: NullTransport())
      .url(method: request.path, params: request.parameters)
  }
}

/// The live export fetcher, for a caller that wants the bytes rather than a URL.
public struct LiveExportDataService: Sendable {
  private let client: XrpcClient
  private let authorization: @Sendable () async throws -> String?

  public init(
    client: XrpcClient,
    authorization: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    self.client = client
    self.authorization = authorization
  }

  /// Fetches the CAR bytes for a repo export.
  ///
  /// `com.atproto.sync.getRepo` declares `application/vnd.ipld.car`, so the
  /// response is bytes rather than a decoded body.
  public func fetchRepo(did: String) async throws -> Data {
    try await client.getBlob(
      SettingsConstants.getRepoPath, params: [("did", did)],
      authorization: try await authorization())
  }
}

/// A transport that never runs, for URL construction only.
///
/// ``ExportData/url(for:baseURL:)`` needs an `XrpcClient` purely to use its
/// query encoder; this keeps that from implying a network dependency.
struct NullTransport: HTTPTransport {
  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    throw SettingsError.unexpected(message: "NullTransport cannot send")
  }
}

/// Copy the account screens show.
public enum SettingsStrings {
  /// `Invalid did`
  public static let invalidDid = "Invalid did"
  /// The app-password-scope message from `DeactivateAccountDialog.tsx`.
  public static let deactivateAppPassword =
    "You're signed in with an App Password. Please sign in with your main password to "
    + "continue deactivating your account."
  /// `Something went wrong, please try again`
  public static let deactivateFailed = "Something went wrong, please try again"
  /// `Your account has been deleted, see ya! ✌️`
  public static let accountDeleted = "Your account has been deleted, see ya! ✌️"

  /// `Error occurred while saving file`, the export dialog's failure toast.
  public static let exportFailedToast = "Error occurred while saving file"
  /// `File saved successfully!`
  public static let exportSucceededToast = "File saved successfully!"

  /// The export cannot run because no export client was configured.
  public static let exportUnavailable = "Export is unavailable"

  /// The export failure message, mirroring the toast RN shows.
  public static func exportFailed(error: any Error) -> String {
    "\(exportFailedToast): \(SettingsError.rawMessage(from: error))"
  }
}
