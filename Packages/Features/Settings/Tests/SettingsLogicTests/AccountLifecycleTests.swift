import Foundation
import Testing

import ATProtoClient
import Lexicons

@testable import SettingsLogic

/// The delete-account flow, ported from `DeleteAccountDialog.tsx`.
@Suite struct DeleteAccountFlowTests {

  /// The dialog starts on the send-code step.
  @Test func initialState() {
    let state = DeleteAccountState()
    #expect(state.step == .sendCode)
    #expect(state.emailSentCount == 0)
    #expect(!state.isSendingCode)
    #expect(state.confirmCode.isEmpty)
    #expect(state.password.isEmpty)
    #expect(!state.didDelete)
  }

  /// Requesting a code advances to the verify step and counts the request.
  @Test func sendCodeAdvances() async {
    let service = FakeAccountLifecycleService()
    let flow = DeleteAccountFlow(service: service)

    let result = await flow.sendCode()

    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(service.deleteRequestCount == 1)
    #expect(flow.state.step == .verifyCode)
    #expect(flow.state.emailSentCount == 1)
    #expect(!flow.state.isSendingCode)
  }

  /// A second request increments the counter, so a resend can be offered.
  @Test func sendCodeTwice() async {
    let service = FakeAccountLifecycleService()
    let flow = DeleteAccountFlow(service: service)

    _ = await flow.sendCode()
    _ = await flow.sendCode()

    #expect(service.deleteRequestCount == 2)
    #expect(flow.state.emailSentCount == 2)
  }

  /// A failed code request records the error and stays on the send step.
  @Test func sendCodeFailure() async {
    let service = FakeAccountLifecycleService()
    service.setRequestError(
      XrpcError(rawCode: "InvalidRequest", message: "no email on file", status: 400))
    let flow = DeleteAccountFlow(service: service)

    let result = await flow.sendCode()

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == "no email on file")
    #expect(error.raw == "no email on file")
    #expect(flow.state.step == .sendCode)
    #expect(flow.state.emailSentCount == 0)
    #expect(!flow.state.isSendingCode)
  }

  /// `beginConfirmation` moves to the confirm step and clears the error.
  @Test func beginConfirmation() async {
    let flow = DeleteAccountFlow(service: FakeAccountLifecycleService())
    _ = await flow.sendCode()
    flow.beginConfirmation()
    #expect(flow.state.step == .confirmDeletion)
  }

  /// The whitespace-stripped code and the password reach `deleteAccount`.
  @Test func confirmDeletionSendsSanitizedCode() async {
    let service = FakeAccountLifecycleService()
    let flow = DeleteAccountFlow(service: service)
    _ = await flow.sendCode()
    flow.beginConfirmation()
    flow.setConfirmCode(" 1234 5678\n")
    flow.setPassword("correct horse")

    let result = await flow.confirmDeletion(did: "did:plc:testaccount")

    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(service.deleteCalls.count == 1)
    #expect(service.deleteCalls[0].did == "did:plc:testaccount")
    #expect(service.deleteCalls[0].token == "12345678")
    #expect(service.deleteCalls[0].password == "correct horse")
    #expect(flow.state.didDelete)
  }

  /// The pre-delete hook (RN's chat-service call) runs before the deletion.
  @Test func preDeleteHookRunsFirst() async {
    let service = FakeAccountLifecycleService()
    let order = OrderRecorder()
    let flow = DeleteAccountFlow(service: service) {
      order.record("chat")
    }
    order.setDeletionObserver { service.deleteCalls.count }
    flow.setConfirmCode("12345678")
    flow.setPassword("correct horse")

    _ = await flow.confirmDeletion(did: "did:plc:testaccount")

    #expect(order.events == ["chat"])
    #expect(service.deleteCalls.count == 1)
  }

  /// A failing pre-delete hook aborts before `deleteAccount`.
  @Test func preDeleteHookFailureAborts() async {
    let service = FakeAccountLifecycleService()
    let flow = DeleteAccountFlow(service: service) {
      throw XrpcError(rawCode: "InvalidRequest", message: "chat down", status: 500)
    }
    flow.setConfirmCode("12345678")
    flow.setPassword("correct horse")

    let result = await flow.confirmDeletion(did: "did:plc:testaccount")

    guard case .failure = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(service.deleteCalls.isEmpty)
  }

  /// A deletion failure resets the code and password and returns to the verify
  /// step, which is RN's recovery path.
  @Test func confirmDeletionFailureResets() async {
    let service = FakeAccountLifecycleService()
    service.setDeleteError(
      XrpcError(rawCode: "InvalidToken", message: "expired", status: 400))
    let flow = DeleteAccountFlow(service: service)
    flow.beginConfirmation()
    flow.setConfirmCode("12345678")
    flow.setPassword("correct horse")

    let result = await flow.confirmDeletion(did: "did:plc:testaccount")

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == "expired")
    #expect(flow.state.step == .verifyCode)
    #expect(flow.state.confirmCode.isEmpty)
    #expect(flow.state.password.isEmpty)
    #expect(!flow.state.didDelete)
  }

  /// A missing DID fails before any network call.
  @Test func confirmDeletionRequiresDID() async {
    let service = FakeAccountLifecycleService()
    let flow = DeleteAccountFlow(service: service)
    flow.setConfirmCode("12345678")
    flow.setPassword("correct horse")

    let result = await flow.confirmDeletion(did: "")

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == SettingsStrings.invalidDid)
    #expect(service.deleteCalls.isEmpty)
  }

  /// The submit-readiness check requires both a code and a long-enough password.
  @Test func submitReadiness() {
    var state = DeleteAccountState()
    #expect(!state.canSubmitDeletion)

    state.confirmCode = "12345678"
    #expect(!state.canSubmitDeletion)

    state.password = "short"
    #expect(!state.canSubmitDeletion)

    state.password = "longenough"
    #expect(state.canSubmitDeletion)

    // Whitespace-only codes do not count.
    state.confirmCode = "   "
    #expect(!state.canSubmitDeletion)
  }

  /// The password rule is `>= 8` characters.
  @Test func passwordRule() {
    #expect(DeleteAccountRules.passwordMinLength == 8)
    #expect(!DeleteAccountRules.isPasswordValid("1234567"))
    #expect(DeleteAccountRules.isPasswordValid("12345678"))
  }

  /// The code sanitizer strips every whitespace character.
  @Test func confirmationCodeSanitizer() {
    #expect(DeleteAccountRules.sanitizeConfirmationCode("1234 5678") == "12345678")
    #expect(DeleteAccountRules.sanitizeConfirmationCode("1234\n5678") == "12345678")
    #expect(DeleteAccountRules.sanitizeConfirmationCode("\t1234 5678 ") == "12345678")
    #expect(DeleteAccountRules.sanitizeConfirmationCode("12345678") == "12345678")
  }
}

/// The deactivate-account flow, ported from `DeactivateAccountDialog.tsx`.
@Suite struct DeactivateAccountFlowTests {

  /// A successful deactivation calls the endpoint once.
  @Test func deactivate() async {
    let service = FakeAccountLifecycleService()
    let flow = DeactivateAccountFlow(service: service)

    let result = await flow.deactivate()

    guard case .success = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(service.deactivateCount == 1)
  }

  /// The app-password scope produces its specific message.
  @Test func deactivateAppPasswordScope() async {
    let service = FakeAccountLifecycleService()
    service.setDeactivateError(
      XrpcError(rawCode: "InvalidRequest", message: "Bad token scope", status: 400))
    let flow = DeactivateAccountFlow(service: service)

    let result = await flow.deactivate()

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == SettingsStrings.deactivateAppPassword)
    #expect(error.raw == "Bad token scope")
  }

  /// Every other failure gets the generic message.
  @Test func deactivateGenericFailure() async {
    let service = FakeAccountLifecycleService()
    service.setDeactivateError(
      XrpcError(rawCode: nil, message: "offline", status: -1))
    let flow = DeactivateAccountFlow(service: service)

    let result = await flow.deactivate()

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == SettingsStrings.deactivateFailed)
    #expect(error.raw == "offline")
  }
}

/// The export-data request builders, ported from `ExportCarDialog.tsx`.
@Suite struct ExportDataTests {

  /// The repo export is a GET of `com.atproto.sync.getRepo` with the DID.
  @Test func repoRequest() {
    let request = ExportData.repoRequest(did: "did:plc:testaccount")
    #expect(request.path == "com.atproto.sync.getRepo")
    #expect(request.parameters.count == 1)
    #expect(request.parameters[0].name == "did")
    #expect(request.parameters[0].value == "did:plc:testaccount")
    #expect(request.contentType == "application/vnd.ipld.car")
    #expect(request.fileName == "repo.car")
  }

  /// The full URL the client would request.
  @Test func repoURL() {
    let url = ExportData.url(
      for: ExportData.repoRequest(did: "did:plc:testaccount"),
      baseURL: "https://pds.test")
    #expect(
      url == "https://pds.test/xrpc/com.atproto.sync.getRepo?did=did%3Aplc%3Atestaccount")
  }

  /// The checkout export is the same shape against `getCheckout`.
  @Test func checkoutRequest() {
    let request = ExportData.checkoutRequest(did: "did:plc:testaccount")
    #expect(request.path == "com.atproto.sync.getCheckout")
    #expect(request.parameters[0].value == "did:plc:testaccount")
    #expect(request.contentType == "application/vnd.ipld.car")

    let url = ExportData.url(for: request, baseURL: "https://pds.test")
    #expect(
      url
        == "https://pds.test/xrpc/com.atproto.sync.getCheckout?did=did%3Aplc%3Atestaccount")
  }

  /// A getRepo request is fetched as bytes, not decoded JSON.
  @Test func fetchRepoBytes() async throws {
    let car = Data([0x01, 0x02, 0x03, 0x04])
    let transport = ScriptedTransport(
      HTTPResponse(
        status: 200, headers: ["Content-Type": "application/vnd.ipld.car"], body: car))
    let service = LiveExportDataService(
      client: XrpcClient(baseURL: "https://pds.test", transport: transport))

    let data = try await service.fetchRepo(did: "did:plc:testaccount")

    #expect(data == car)
    let request = try #require(transport.lastRequest)
    #expect(request.method == "GET")
    #expect(request.url == "https://pds.test/xrpc/com.atproto.sync.getRepo?did=did%3Aplc%3Atestaccount")
  }

  /// The store's export request is nil without a session.
  @Test func storeExportRequestWithoutSession() async {
    let harness = await StoreHarness(did: nil)
    defer { harness.cleanUp() }
    #expect(await harness.store.repoExportRequest() == nil)
  }

  /// With a session, the store builds the request for the current DID.
  @Test func storeExportRequest() async {
    let harness = await StoreHarness(did: "did:plc:testaccount")
    defer { harness.cleanUp() }
    let request = await harness.store.repoExportRequest()
    #expect(request?.parameters[0].value == "did:plc:testaccount")
    #expect(request?.path == "com.atproto.sync.getRepo")
  }

  /// Without an export client, the fetch fails with the explicit message rather
  /// than a silent nil.
  @Test func storeExportWithoutClient() async {
    let harness = await StoreHarness(did: "did:plc:testaccount")
    defer { harness.cleanUp() }

    let result = await harness.store.fetchRepoExport()

    guard case .failure(let error) = result else {
      Issue.record("expected failure, got \(result)")
      return
    }
    #expect(error.message == SettingsStrings.exportUnavailable)
  }
}

/// Records the order of side effects for the pre-delete-hook test.
final class OrderRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []
  private var observation: (@Sendable () -> Int)?

  var events: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func record(_ event: String) {
    lock.lock()
    recorded.append(event)
    lock.unlock()
  }

  func setDeletionObserver(_ observe: @escaping @Sendable () -> Int) {
    lock.lock()
    observation = observe
    lock.unlock()
  }
}
