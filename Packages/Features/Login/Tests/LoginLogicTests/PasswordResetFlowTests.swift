import ATProtoClient
import Foundation
import Testing

@testable import LoginLogic

/// The reset-code rule, ported from `checkAndFormatResetCode` in
/// `src/lib/strings/password.ts`.
@Suite struct ResetCodeTests {

  @Test(arguments: [
    ("ABCDE23456", "ABCDE-23456"),
    ("abcde23456", "ABCDE-23456"),
    ("  abcde23456  ", "ABCDE-23456"),
    ("ABCDE-23456", "ABCDE-23456"),
    ("abcde-23456", "ABCDE-23456"),
  ])
  func formattingTable(raw: String, expected: String) {
    #expect(ResetCode.format(raw) == expected)
  }

  @Test(arguments: [
    "",
    "ABCDE",
    "ABCDE2345",
    "ABCDE-234567",
    "ABCDE-2345",
    // A lone 10-char code gains the dash and then fails the alphabet check.
    "ABCDE12340",
    // `0`, `1`, `8`, and `9` are outside the base32 alphabet.
    "ABCDE-23450",
    "ABCDE-23451",
    "ABCDE-23458",
    "ABCDE-23459",
    // Not a dash separator.
    "ABCDE_23456",
    "ABCDE 23456",
  ])
  func invalidCodesAreRejected(raw: String) {
    #expect(ResetCode.format(raw) == nil)
  }
}

/// The forgotten-password journey, ported from `ForgotPasswordForm.tsx` and
/// `SetNewPasswordForm.tsx`.
@Suite struct PasswordResetFlowTests {

  private func makeFlow(
    _ service: FakePasswordResetService,
    serviceURL: String = LoginConstants.defaultService,
    emailValidator: @escaping @Sendable (String) -> Bool = { _ in true }
  ) -> PasswordResetFlow {
    PasswordResetFlow(
      service: service, serviceURL: serviceURL, emailValidator: emailValidator)
  }

  @Test func startsCollectingTheEmail() {
    let flow = makeFlow(FakePasswordResetService())
    #expect(flow.state.step == .enteringEmail)
    #expect(flow.state.service == LoginConstants.defaultService)
    #expect(flow.state.isProcessing == false)
    #expect(flow.state.error == nil)
  }

  @Test func aValidEmailRequestsAResetAndMovesOn() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service)
    flow.setEmail("  alice@example.com  ")

    #expect(await flow.requestReset())
    #expect(flow.state.step == .enteringNewPassword)
    #expect(service.calls == [
      FakePasswordResetService.Call(
        service: LoginConstants.defaultService, email: "alice@example.com",
        token: nil, password: nil)
    ])
  }

  @Test func anInvalidEmailFailsLocallyWithoutCallingTheService() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service, emailValidator: PasswordResetFlow.defaultEmailValidator)
    flow.setEmail("not-an-email")

    #expect(await flow.requestReset() == false)
    #expect(flow.state.step == .failed(.invalidEmail))
    #expect(flow.state.error?.message == LoginStrings.invalidEmail)
    #expect(service.calls.isEmpty)
  }

  @Test func aNetworkFailureReportingTheResetEmailIsReportedAsOffline() async {
    let service = FakePasswordResetService(requestError: makeNetworkError())
    let flow = makeFlow(service)
    flow.setEmail("alice@example.com")

    #expect(await flow.requestReset() == false)
    #expect(flow.state.error?.message == LoginStrings.unableToContactService)
  }

  @Test func aServerRejectionReportingTheResetEmailUsesTheCleanMessage() async {
    let service = FakePasswordResetService(
      requestError: XrpcError(
        rawCode: "InvalidRequest", message: "Email not found", status: 400))
    let flow = makeFlow(service)
    flow.setEmail("alice@example.com")

    #expect(await flow.requestReset() == false)
    #expect(flow.state.error?.message == "Email not found")
  }

  @Test func aValidCodeAndPasswordSetTheNewPassword() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service)
    flow.setEmail("alice@example.com")
    _ = await flow.requestReset()

    flow.setResetCode("abcde23456")
    // The code is formatted on entry, as the RN form does on blur.
    #expect(flow.state.resetCode == "ABCDE-23456")

    #expect(await flow.setNewPassword("new-password"))
    #expect(flow.state.step == .passwordUpdated)
    #expect(service.calls.last == FakePasswordResetService.Call(
      service: LoginConstants.defaultService, email: nil, token: "ABCDE-23456",
      password: "new-password"))
  }

  @Test func anInvalidCodeFailsLocally() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service)
    flow.setResetCode("nope")

    #expect(await flow.setNewPassword("new-password") == false)
    #expect(flow.state.step == .failed(.invalidCode))
    #expect(flow.state.error?.message == LoginStrings.invalidResetCode)
    #expect(service.calls.isEmpty)
  }

  @Test func anEmptyPasswordFailsLocally() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service)
    flow.setResetCode("ABCDE23456")

    #expect(await flow.setNewPassword("") == false)
    #expect(flow.state.step == .failed(.emptyPassword))
    #expect(service.calls.isEmpty)
  }

  @Test func aRejectedResetCodeUsesTheCleanServerMessage() async {
    let service = FakePasswordResetService(
      resetError: XrpcError(
        rawCode: "InvalidToken", message: "Token is invalid", status: 400))
    let flow = makeFlow(service)
    flow.setResetCode("ABCDE23456")

    #expect(await flow.setNewPassword("new-password") == false)
    #expect(flow.state.error?.message == "Token is invalid")
    #expect(flow.state.error?.underlying?.error == "InvalidToken")
  }

  @Test func aNetworkFailureSettingThePasswordIsReportedAsOffline() async {
    let service = FakePasswordResetService(resetError: makeNetworkError())
    let flow = makeFlow(service)
    flow.setResetCode("ABCDE23456")

    #expect(await flow.setNewPassword("new-password") == false)
    #expect(flow.state.error?.message == LoginStrings.unableToContactService)
  }

  @Test func theServiceAddressIsSharedWithTheSignInScreen() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service)
    flow.setServiceURL("pds.example.com")
    #expect(flow.state.service == "https://pds.example.com/")

    flow.setEmail("alice@example.com")
    _ = await flow.requestReset()
    #expect(service.calls.first?.service == "https://pds.example.com/")
  }

  @Test func goingBackAndResettingClearTheJourney() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service)
    flow.setEmail("alice@example.com")
    _ = await flow.requestReset()
    #expect(flow.state.step == .enteringNewPassword)

    flow.backToEmail()
    #expect(flow.state.step == .enteringEmail)

    flow.setResetCode("ABCDE23456")
    flow.reset()
    #expect(flow.state.step == .enteringEmail)
    #expect(flow.state.email.isEmpty)
    #expect(flow.state.resetCode.isEmpty)
  }

  @Test func observersSeeEveryResetTransition() async {
    let service = FakePasswordResetService()
    let flow = makeFlow(service)
    let recorder = ResetStateRecorder()
    flow.addListener { recorder.record($0) }

    flow.setEmail("alice@example.com")
    _ = await flow.requestReset()
    flow.setResetCode("ABCDE23456")
    _ = await flow.setNewPassword("new-password")

    let steps = recorder.steps
    #expect(steps.contains(.requestingReset))
    #expect(steps.contains(.enteringNewPassword))
    #expect(steps.contains(.settingPassword))
    #expect(steps.last == .passwordUpdated)
  }

  @Test func everyFailureHasUserFacingCopy() {
    let cases: [PasswordResetError] = [
      .invalidEmail, .invalidCode, .emptyPassword,
      .networkOffline(underlying: nil), .failed(message: "x", underlying: nil),
    ]
    for error in cases {
      #expect(!error.message.isEmpty)
    }
  }
}

/// Collects the reset steps a flow passes through.
final class ResetStateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _states: [PasswordResetState] = []

  var steps: [PasswordResetStep] {
    lock.lock()
    defer { lock.unlock() }
    return _states.map(\.step)
  }

  func record(_ state: PasswordResetState) {
    lock.lock()
    _states.append(state)
    lock.unlock()
  }
}
