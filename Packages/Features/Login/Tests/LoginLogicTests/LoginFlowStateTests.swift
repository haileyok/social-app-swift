import ATProtoClient
import Foundation
import Persistence
import Testing

@testable import LoginLogic

/// The state machine: steps, transitions, error recovery, and observation.
@Suite struct LoginFlowStateTests {

  private func makeFlow(
    _ responses: (HTTPResponse)?...
  ) -> (flow: LoginFlow, transport: ScriptedTransport) {
    let transport = ScriptedTransport(script: responses)
    let flow = LoginFlow(transport: transport)
    return (flow, transport)
  }

  @Test func startsInTheCredentialStepAgainstTheDefaultService() {
    let (flow, _) = makeFlow()
    #expect(flow.state.step == .enteringCredentials)
    #expect(flow.state.service == LoginConstants.defaultService)
    #expect(flow.state.serviceOverride == nil)
    #expect(flow.state.failedAttemptCount == 0)
    #expect(flow.state.error == nil)
    #expect(flow.state.isProcessing == false)
  }

  @Test func listenersSeeEveryTransition() async {
    let (flow, _) = makeFlow(ScriptedTransport.createSession())
    let recorder = StateRecorder()
    flow.addListener { recorder.record($0) }

    flow.beginServicePicking()
    flow.endServicePicking()
    flow.setIdentifier("alice.example.com")
    _ = await flow.signIn(identifier: "alice.example.com", password: "hunter2")

    // One notification per real transition: pick, return, identifier, sign-in
    // start, sign-in result. Repeat values collapse so the observer is not
    // woken for a no-op.
    #expect(recorder.steps == [
      .pickingService,
      .enteringCredentials,
      .enteringCredentials,
      .signingIn,
      .success,
    ])
  }

  @Test func pickingAServiceAndReturningKeepsTheDefault() {
    let (flow, _) = makeFlow()
    flow.beginServicePicking()
    #expect(flow.state.step == .pickingService)
    flow.selectDefaultService()
    #expect(flow.state.service == LoginConstants.defaultService)
    #expect(flow.state.serviceOverride == nil)
    flow.endServicePicking()
    #expect(flow.state.step == .enteringCredentials)
  }

  @Test func emptyIdentifierFailsValidationWithoutTouchingTheNetwork() async {
    let (flow, transport) = makeFlow()
    let outcome = await flow.signIn(identifier: "   ", password: "hunter2")
    #expect(outcome == .invalid(LoginStrings.pleaseEnterUsername))
    #expect(transport.received.isEmpty)
    // A validation failure is not a failed attempt: the step does not change.
    #expect(flow.state.step == .enteringCredentials)
    #expect(flow.state.failedAttemptCount == 0)
  }

  @Test func emptyPasswordFailsValidationWithoutTouchingTheNetwork() async {
    let (flow, transport) = makeFlow()
    let outcome = await flow.signIn(identifier: "alice.example.com", password: "")
    #expect(outcome == .invalid(LoginStrings.pleaseEnterPassword))
    #expect(transport.received.isEmpty)
  }

  @Test func successfulSignInRecordsTheAccountAndCountsNoFailure() async {
    let (flow, transport) = makeFlow(ScriptedTransport.createSession())
    let outcome = await flow.signIn(identifier: "Alice.Example.com", password: "hunter2")

    guard case .success(let account) = outcome else {
      Issue.record("expected success, got \(outcome)")
      return
    }
    #expect(account.did == "did:plc:testaccount")
    #expect(account.handle == "alice.example.com")
    #expect(flow.state.step == .success)
    #expect(flow.state.failedAttemptCount == 0)
    #expect(flow.state.account == account)

    // The identifier is lowercased on the wire, and no auth factor is sent.
    let body = try? #require(transport.lastRequest?.json)
    #expect(body?["identifier"] as? String == "alice.example.com")
    #expect(body?["password"] as? String == "hunter2")
    #expect(body?["authFactorToken"] == nil)
    #expect(transport.lastRequest?.url.hasSuffix("/xrpc/com.atproto.server.createSession") == true)
  }

  @Test func failedSignInCountsTheAttemptAndExposesTheMappedError() async {
    let (flow, _) = makeFlow(
      ScriptedTransport.xrpcError(
        "AuthenticationRequired", message: "Authentication Required", status: 401))
    let outcome = await flow.signIn(identifier: "alice.example.com", password: "wrong")

    #expect(outcome == .failure(.incorrectCredentials(
      underlying: XRPCErrorShapes.shape(fromXrpc: XrpcError(
        rawCode: "AuthenticationRequired", message: "Authentication Required", status: 401)))))
    #expect(flow.state.step == .failed(.incorrectCredentials(
      underlying: flow.state.error?.underlying)))
    #expect(flow.state.failedAttemptCount == 1)
    #expect(flow.state.error?.messageID == .incorrectCredentials)
  }

  @Test func aFailureIsStickyUntilTheNextSubmission() async {
    let (flow, _) = makeFlow(
      ScriptedTransport.xrpcError(
        "AuthenticationRequired", message: "Authentication Required", status: 401))
    _ = await flow.signIn(identifier: "alice.example.com", password: "wrong")
    #expect(flow.state.error != nil)

    // Re-stating the same identifier must not clear the shown error, or the
    // form would flash back to the credential step mid-retry.
    flow.setIdentifier("alice.example.com")
    #expect(flow.state.error != nil)
    #expect(flow.state.step == .failed(.incorrectCredentials(
      underlying: flow.state.error?.underlying)))
    #expect(flow.state.identifier == "alice.example.com")
  }

  @Test func aNewSubmissionClearsTheShownErrorWhileKeepingTheCount() async {
    let (flow, _) = makeFlow(
      ScriptedTransport.xrpcError("AuthenticationRequired", message: "nope", status: 401),
      ScriptedTransport.xrpcError(
        "AuthenticationRequired", message: "still nope", status: 401))
    _ = await flow.signIn(identifier: "alice.example.com", password: "wrong")
    #expect(flow.state.failedAttemptCount == 1)

    // The retry re-submits the same identifier; the error clears up front but
    // the attempt counter carries across attempts, as the RN form's ref does.
    _ = await flow.signIn(identifier: "alice.example.com", password: "also-wrong")
    #expect(flow.state.failedAttemptCount == 2)
    #expect(flow.state.error?.message == "still nope")
  }

  @Test func retryingAfterAFailureSucceeds() async {
    let (flow, _) = makeFlow(
      ScriptedTransport.xrpcError("AuthenticationRequired", message: "nope", status: 401),
      ScriptedTransport.createSession())
    _ = await flow.signIn(identifier: "alice.example.com", password: "wrong")
    #expect(flow.state.error != nil)

    // Recovery through the flow's own entry point, not by editing a field.
    flow.setIdentifier("alice.example.com")
    let outcome = await flow.signIn(identifier: "alice.example.com", password: "right")
    guard case .success = outcome else {
      Issue.record("expected success on retry, got \(outcome)")
      return
    }
    #expect(flow.state.step == .success)
    // The counter accumulates across attempts and survives the success: it
    // feeds the RN sign-in analytics (`failedAttemptsCount`) for the session.
    #expect(flow.state.failedAttemptCount == 1)
  }

  @Test func needsAuthFactorMovesTheFlowRatherThanFailingIt() async {
    let (flow, _) = makeFlow(
      ScriptedTransport.xrpcError("AuthFactorTokenRequired", message: "code", status: 401))
    let outcome = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    #expect(outcome == .needsAuthFactor)
    #expect(flow.state.step == .needsAuthFactor)
    #expect(flow.state.needsAuthFactor)
    #expect(flow.state.failedAttemptCount == 1)
  }

  @Test func retryWithAuthFactorResendsTheStoredCredentialsAndClearsOnSuccess() async {
    let (flow, transport) = makeFlow(
      ScriptedTransport.xrpcError("AuthFactorTokenRequired", message: "code", status: 401),
      ScriptedTransport.createSession())
    _ = await flow.signIn(identifier: "alice.example.com", password: "hunter2")

    let outcome = await flow.retryWithAuthFactor("  abc-123  ")
    guard case .success = outcome else {
      Issue.record("expected success, got \(outcome)")
      return
    }
    #expect(flow.state.step == .success)
    // The code is trimmed, and the original credentials are repeated exactly.
    let second = transport.received[1].json
    #expect(second["authFactorToken"] as? String == "abc-123")
    #expect(second["password"] as? String == "hunter2")
    #expect(second["identifier"] as? String == "alice.example.com")
    // On success the retained code is cleared.
    #expect(flow.state.authFactorToken.isEmpty)
  }

  @Test func retryWithWrongCodeReportsAnInvalidCodeAndStaysRecoverable() async {
    let (flow, _) = makeFlow(
      ScriptedTransport.xrpcError("AuthFactorTokenRequired", message: "code", status: 401),
      ScriptedTransport.xrpcError("InvalidToken", message: "Token is invalid", status: 400))
    _ = await flow.signIn(identifier: "alice.example.com", password: "hunter2")

    let outcome = await flow.retryWithAuthFactor("000000")
    #expect(outcome == .failure(.invalidAuthFactorToken(
      underlying: XRPCErrorShapes.shape(fromXrpc: XrpcError(
        rawCode: "InvalidToken", message: "Token is invalid", status: 400)))))
    #expect(flow.state.error?.messageID == .invalidAuthFactorToken)
    #expect(flow.state.failedAttemptCount == 2)
  }

  @Test func retryWithAnEmptyCodeIsRejectedLocally() async {
    let (flow, transport) = makeFlow(
      ScriptedTransport.xrpcError("AuthFactorTokenRequired", message: "code", status: 401))
    _ = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    let callsBefore = transport.received.count

    let outcome = await flow.retryWithAuthFactor("   ")
    #expect(outcome == .invalid(LoginStrings.invalidAuthFactorToken))
    #expect(transport.received.count == callsBefore)
  }

  @Test func retryWithoutAPendingAttemptIsRejected() async {
    let (flow, transport) = makeFlow()
    let outcome = await flow.retryWithAuthFactor("abc-123")
    #expect(outcome == .invalid(LoginStrings.pleaseEnterPassword))
    #expect(transport.received.isEmpty)
  }

  @Test func cancellingAuthFactorReturnsToCredentials() async {
    let (flow, _) = makeFlow(
      ScriptedTransport.xrpcError("AuthFactorTokenRequired", message: "code", status: 401))
    _ = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    flow.cancelAuthFactor()
    #expect(flow.state.step == .enteringCredentials)
    #expect(flow.state.authFactorToken.isEmpty)
    // The retained attempt is gone too, so a late retry cannot resend it.
    #expect(await flow.retryWithAuthFactor("abc-123") == .invalid(LoginStrings.pleaseEnterPassword))
  }

  @Test func resetRestoresEveryField() async {
    let (flow, _) = makeFlow(ScriptedTransport.createSession())
    flow.selectDefaultService()
    _ = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    #expect(flow.state.step == .success)

    flow.reset()
    #expect(flow.state.step == .enteringCredentials)
    #expect(flow.state.identifier.isEmpty)
    #expect(flow.state.account == nil)
    #expect(flow.state.service == LoginConstants.defaultService)
    #expect(flow.state.serviceOverride == nil)
    #expect(flow.state.serviceDescription == nil)
    #expect(flow.state.failedAttemptCount == 0)
  }

  @Test func networkFailureDuringSignInIsReportedAsOffline() async {
    let transport = ScriptedTransport.failing(with: makeNetworkError())
    let flow = LoginFlow(transport: transport)
    let outcome = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    #expect(outcome == .failure(.networkOffline(
      underlying: XRPCErrorShapes.shape(fromXrpc: makeNetworkError()))))
    #expect(flow.state.error?.message == LoginStrings.unableToContactService)
  }
}

/// Collects the steps a flow passes through.
final class StateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _states: [LoginState] = []

  var states: [LoginState] {
    withLock { _states }
  }

  var steps: [LoginStep] { states.map(\.step) }

  func record(_ state: LoginState) {
    withLock { _states.append(state) }
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
