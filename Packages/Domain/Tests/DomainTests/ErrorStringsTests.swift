import Foundation
import Testing

@testable import Domain

/// Port of `src/lib/strings/__tests__/errors.test.ts` (`cleanError` suite),
/// case for case.
///
/// The RN test builds real `XrpcResponseError`/`LexError` values. Domain must
/// not depend on ATProtoClient or the lex SDK, so the equivalent shapes are
/// built through ``XRPCErrorShape``'s helpers, which reproduce the same
/// `Class: [ErrorCode] message` stringification the RN assertions check.
@Suite("cleanError")
struct ErrorStringsTests {

  let methodDeclaredErrors: Set<String> = ["HandleNotAvailable"]

  /// An error as the lex client builds one from a JSON error response body.
  func xrpcResponseError(_ error: String, _ message: String, status: Int = 400) -> XRPCErrorShape {
    XRPCErrorShape.responsePayload(error: error, message: message, status: status)
  }

  /// An error as the lex client builds one from a response with no XRPC error
  /// payload: the code is derived from the HTTP status.
  func xrpcStatusError(_ status: Int) -> XRPCErrorShape {
    XRPCErrorShape.responseStatus(status)
  }

  @Test func surfacesTheCleanMessageOfALexError() {
    let e = xrpcResponseError("HandleNotAvailable", "Handle already taken")
    // The raw stringification is class- and code-prefixed, so it must not leak.
    #expect(e.description == "XrpcResponseError: [HandleNotAvailable] Handle already taken")
    #expect(ErrorStrings.cleanError(e) == "Handle already taken")
  }

  @Test func fallsBackToTheLexiconCodeWhenALexErrorHasNoMessage() {
    let e = XRPCErrorShape.lexError("InvalidRequest")
    #expect(e.description == "LexError: [InvalidRequest] ")
    #expect(ErrorStrings.cleanError(e) == "InvalidRequest")
  }

  @Test func matchesTheUpstreamFailureBranchOnALexErrorCode() {
    // 502 maps to the space-free `UpstreamFailure` lexicon code.
    let e = xrpcStatusError(502)
    #expect(e.error == "UpstreamFailure")
    #expect(
      ErrorStrings.cleanError(e)
        == "The server appears to be experiencing issues. Please try again in a few moments.")
  }

  @Test func matchesNotEnoughResources() {
    #expect(
      ErrorStrings.cleanError(xrpcStatusError(503))
        == "The server appears to be experiencing issues. Please try again in a few moments.")
  }

  @Test func matchesTheAppPasswordBranchOnALexErrorMessage() {
    let e = xrpcResponseError("InvalidToken", "Bad token scope")
    #expect(
      ErrorStrings.cleanError(e)
        == "This feature is not available while using an App Password. Please sign in with your main password."
    )
  }

  @Test func matchesTheNetworkErrorBranchOnALexErrorMessage() {
    let e = xrpcResponseError("InternalServerError", "Failed to fetch", status: 500)
    #expect(
      ErrorStrings.cleanError(e)
        == "Unable to connect. Please check your internet connection and try again.")
  }

  @Test func matchesExpoFetchNetworkErrors() {
    let e = TextError(
      "Unexpected fetchHandler() error: fetch failed: UnexpectedException: The network connection was lost. (at ExpoModulesCore/Promise.swift:56)"
    )
    #expect(
      ErrorStrings.cleanError(e)
        == "Unable to connect. Please check your internet connection and try again.")
  }

  @Test func surfacesTheAuthenticationRequiredCodeOfALexError() {
    let e = xrpcStatusError(401)
    #expect(e.error == "AuthenticationRequired")
    #expect(ErrorStrings.cleanError(e) == "Upstream server responded with a 401 error")
  }

  @Test func stripsALeadingErrorFromAPlainError() {
    #expect(ErrorStrings.cleanError(TextError("Error: Something broke")) == "Something broke")
    #expect(ErrorStrings.cleanError("Error: Something broke") == "Something broke")
  }

  @Test func passesStringsThrough() {
    #expect(ErrorStrings.cleanError("Something broke") == "Something broke")
    #expect(ErrorStrings.cleanError("") == "")
    #expect(ErrorStrings.cleanError(nil) == "")
  }
}

/// A minimal error whose stringification is its message, standing in for the
/// JS `Error` the RN tests construct.
struct TextError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
