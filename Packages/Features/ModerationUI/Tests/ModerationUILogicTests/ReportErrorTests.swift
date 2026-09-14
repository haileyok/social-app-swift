import Foundation
import Testing

@testable import ModerationUILogic

/// Port of `src/components/moderation/ReportDialog/errors.test.ts`.
@Suite("Report error classification")
struct ReportErrorTests {

  /// Builds the shaped error the classifier reads, mirroring the lex
  /// `XrpcResponseError` the RN test constructs.
  private func xrpcError(status: Int, error: String, message: String) -> ReportXrpcError {
    ReportXrpcError(error: error, message: message, status: status)
  }

  @Test("an account takedown is an expected rejection")
  func accountTakedown() {
    let result = ReportErrorClassifier.classify(
      xrpcError(status: 403, error: "AccountTakedown", message: "Report not accepted from takendown account"))

    #expect(result.kind == .accountTakedown)
    #expect(!result.shouldReport)
    #expect(result.fingerprint == ["{{ default }}", "report-dialog:account-takedown"])
    #expect(result.tags["report_error_kind"] == "account-takedown")
    #expect(result.tags["report_error_bucket"] == "account-takedown")
    #expect(result.tags["report_xrpc_error"] == "AccountTakedown")
    #expect(result.tags["report_http_status"] == "403")
  }

  @Test(
    "upstream failures classify as unavailable",
    arguments: [
      (502, "InternalServerError", "Failed to perform upstream request", "upstream-fetch"),
      (502, "UpstreamFailure", "Internal Server Error", "upstream-internal"),
      (502, "UpstreamFailure", "Upstream server responded with a 502 error", "upstream-http-502"),
      (504, "UpstreamTimeout", "Upstream server responded with a 504 error", "upstream-http-504"),
    ])
  func upstreamUnavailable(_ input: (Int, String, String, String)) {
    let (status, error, message, bucket) = input
    let result = ReportErrorClassifier.classify(
      xrpcError(status: status, error: error, message: message))
    #expect(result.kind == .serviceUnavailable)
    #expect(result.shouldReport)
    #expect(result.fingerprint == ["{{ default }}", "report-dialog:\(bucket)"])
  }

  @Test("an invalid reason type classifies separately")
  func invalidReasonType() {
    let result = ReportErrorClassifier.classify(
      xrpcError(
        status: 400, error: "InvalidRequest",
        message: "Invalid reason type: tools.ozone.report.defs#reasonOther"))
    #expect(result.kind == .invalidReasonType)
    #expect(result.shouldReport)
    #expect(result.fingerprint == ["{{ default }}", "report-dialog:invalid-reason-type"])
  }

  @Test(
    "a non-retryable upstream status is unexpected, not temporary",
    arguments: [400, 404])
  func nonRetryableUpstream(_ upstream: Int) {
    let result = ReportErrorClassifier.classify(
      xrpcError(
        status: 502, error: "UpstreamFailure",
        message: "Upstream server responded with a \(upstream) error"))
    #expect(result.kind == .unexpected)
    #expect(result.shouldReport)
    #expect(result.fingerprint == ["{{ default }}", "report-dialog:upstream-http-\(upstream)"])
  }

  @Test("a non-XRPC error classifies as unexpected")
  func nonXrpcError() {
    // Deliberately not a local `struct X: Error {}` declaration: the test
    // manifest checker's suite extractor keys on `struct <Name>` at the start
    // of a line and would rebind every later @Test in this file to it.
    let result = ReportErrorClassifier.classify(
      ReportFlow.ValidationError.noReason)
    #expect(result.kind == .unexpected)
    #expect(result.shouldReport)
    #expect(result.fingerprint == ["{{ default }}", "report-dialog:unexpected"])
  }

  @Test("an unknown XRPC status falls through to xrpc-other")
  func unknownXrpcStatus() {
    let result = ReportErrorClassifier.classify(
      xrpcError(status: 418, error: "Teapot", message: "I'm a teapot"))
    #expect(result.kind == .unexpected)
    #expect(result.bucket == "xrpc-other-418")
  }

  @Test("a retryable status falls through to xrpc-retryable")
  func retryableStatus() {
    let result = ReportErrorClassifier.classify(
      xrpcError(status: 429, error: "RateLimitExceeded", message: "slow down"))
    #expect(result.kind == .serviceUnavailable)
    #expect(result.bucket == "xrpc-retryable-429")
  }

  @Test("an unanchored upstream-status message is not treated as upstream")
  func unanchoredUpstreamMessage() {
    // The RN regex is anchored, so a suffix breaks the match.
    let result = ReportErrorClassifier.classify(
      xrpcError(
        status: 502, error: "UpstreamFailure",
        message: "Upstream server responded with a 502 error (via proxy)"))
    #expect(result.bucket == "xrpc-retryable-502")
  }

  @Test("a four-digit upstream status does not match")
  func fourDigitUpstreamStatus() {
    let result = ReportErrorClassifier.classify(
      xrpcError(
        status: 502, error: "UpstreamFailure",
        message: "Upstream server responded with a 5020 error"))
    #expect(result.bucket == "xrpc-retryable-502")
  }

  @Test("the upstream status extractor reads the exact RN shape")
  func upstreamStatusExtraction() {
    #expect(ReportErrorClassifier.upstreamStatus(in: "Upstream server responded with a 502 error") == 502)
    #expect(ReportErrorClassifier.upstreamStatus(in: "Upstream server responded with a 50 error") == nil)
    #expect(ReportErrorClassifier.upstreamStatus(in: "upstream server responded with a 502 error") == nil)
  }
}
