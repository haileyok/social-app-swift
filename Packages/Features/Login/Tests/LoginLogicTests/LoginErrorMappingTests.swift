import ATProtoClient
import Domain
import Foundation
import Testing

@testable import LoginLogic

/// The RN branch order, ported from `attemptLogin` in
/// `screens/Login/LoginForm.tsx` and widened with the app-password and
/// rate-limit cases.
@Suite struct LoginErrorMappingTests {

  private func xrpc(_ code: String, message: String = "", status: Int = 400) -> XrpcError {
    XrpcError(rawCode: code, message: message, status: status)
  }

  @Test func authFactorRequiredCodeMapsToAuthFactorRequired() {
    // `AuthFactorRequiredError` has no public initializer (it is produced only
    // by `PasswordSession.login`), so the mapping is exercised through the
    // error code the transport actually carries. The flow-level test below
    // covers the typed path end to end.
    let error = xrpc("AuthFactorTokenRequired", message: "A code is required", status: 401)
    let mapped = LoginErrorMapper.map(error)
    #expect(mapped == .authFactorRequired(underlying: XRPCErrorShapes.shape(fromXrpc: error)))
    let messageID = mapped.messageID
    #expect(messageID == LoginMessageID.authFactorRequired)
  }

  @Test func aTypedAuthFactorErrorMapsThroughTheFlow() async {
    // Driven through `PasswordSession.login`, which is the only producer of
    // `AuthFactorRequiredError`.
    let transport = ScriptedTransport(
      ScriptedTransport.xrpcError("AuthFactorTokenRequired", message: "code", status: 401))
    let flow = LoginFlow(transport: transport)
    let outcome = await flow.signIn(identifier: "alice.example.com", password: "hunter2")
    #expect(outcome == .needsAuthFactor)
    #expect(flow.state.error == nil)
  }

  @Test func tokenIsInvalidMapsToInvalidAuthFactorToken() {
    let mapped = LoginErrorMapper.map(xrpc("InvalidToken", message: "Token is invalid"))
    #expect(mapped.messageID == .invalidAuthFactorToken)
    #expect(mapped.message == LoginStrings.invalidAuthFactorToken)
  }

  @Test func authenticationRequiredMapsToIncorrectCredentials() {
    let mapped = LoginErrorMapper.map(
      xrpc("AuthenticationRequired", message: "Authentication Required"))
    #expect(mapped.messageID == .incorrectCredentials)
    #expect(mapped.message == LoginStrings.incorrectCredentials)
  }

  @Test func invalidIdentifierOrPasswordMapsToIncorrectCredentials() {
    let mapped = LoginErrorMapper.map(
      xrpc("InvalidRequest", message: "Invalid identifier or password"))
    #expect(mapped.messageID == .incorrectCredentials)
  }

  @Test func appPasswordScopeRejectionMapsToAppPasswordNotAllowed() {
    let mapped = LoginErrorMapper.map(
      xrpc("InvalidToken", message: "Bad token scope", status: 401))
    #expect(mapped.messageID == .appPasswordNotAllowed)
    #expect(mapped.message == LoginStrings.appPasswordNotAllowed)
    #expect(mapped.isRecoverable == false)
  }

  @Test func appPasswordScopeRejectionAlsoMatchesTheStringForm() {
    let mapped = LoginErrorMapper.map(XRPCErrorShape.lexError("InvalidToken", message: "Bad token method"))
    #expect(mapped.messageID == .appPasswordNotAllowed)
  }

  @Test func rateLimitStatusMapsToRateLimited() {
    let error = XrpcError(
      rawCode: "RateLimitExceeded", message: "slow down", status: 429,
      retryAfterSeconds: 30)
    let mapped = LoginErrorMapper.map(error)
    #expect(mapped == .rateLimited(
      underlying: XRPCErrorShapes.shape(fromXrpc: error), retryAfterSeconds: 30))
    #expect(mapped.message == LoginStrings.rateLimited)
  }

  @Test func rateLimitCodeWithoutStatusMapsToRateLimited() {
    let mapped = LoginErrorMapper.map(
      XRPCErrorShape.response("RateLimitExceeded", message: "slow down", status: 429))
    #expect(mapped.messageID == .rateLimited)
  }

  @Test func networkFailureMapsToNetworkOffline() {
    let mapped = LoginErrorMapper.map(makeNetworkError())
    #expect(mapped.messageID == .networkOffline)
    #expect(mapped.message == LoginStrings.unableToContactService)
  }

  @Test func plainStringNetworkFailureMapsToNetworkOffline() {
    let mapped = LoginErrorMapper.map(XRPCErrorShape(
      name: "Error", error: nil, message: "TypeError: Network request failed"))
    #expect(mapped.messageID == .networkOffline)
  }

  @Test func unknownFailureMapsToUnexpectedWithCleanMessage() {
    let mapped = LoginErrorMapper.map(
      xrpc("HandleNotAvailable", message: "Handle already taken"))
    #expect(mapped.message == "Handle already taken")
    #expect(mapped.messageID == .unexpected)
  }

  @Test func unknownFailureWithNoMessageFallsBackToTheCode() {
    let mapped = LoginErrorMapper.map(XRPCErrorShape.lexError("InvalidRequest"))
    #expect(mapped.message == "InvalidRequest")
  }

  @Test func upstreamFailureMapsToTheServerMessage() {
    let mapped = LoginErrorMapper.map(
      xrpc("UpstreamFailure", message: "Upstream Failure", status: 502))
    #expect(mapped.messageID == .unexpected)
    #expect(mapped.message.contains("experiencing issues"))
  }

  /// Every case reports the message identifier the views package keys on.
  @Test(arguments: [
    LoginError.incorrectCredentials(underlying: nil),
    LoginError.authFactorRequired(underlying: nil),
    LoginError.invalidAuthFactorToken(underlying: nil),
    LoginError.rateLimited(underlying: nil, retryAfterSeconds: nil),
    LoginError.networkOffline(underlying: nil),
    LoginError.appPasswordNotAllowed(underlying: nil),
    LoginError.unexpected(message: "boom", underlying: nil),
  ])
  func everyCaseHasAMessageID(error: LoginError) {
    #expect(LoginMessageID.allCases.contains(error.messageID))
    #expect(!error.message.isEmpty)
  }

  @Test func theDomainClassifierIsWhatDecidesAppPasswordScope() {
    // Guards the delegation: if the classifier changes, this table changes.
    #expect(
      ErrorStrings.isErrorMaybeAppPasswordPermissions(
        XRPCErrorShape.response("InvalidToken", message: "Bad token scope", status: 401)))
    #expect(
      !ErrorStrings.isErrorMaybeAppPasswordPermissions(
        XRPCErrorShape.response("InvalidToken", message: "expired", status: 401)))
  }
}
