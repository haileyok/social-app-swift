import Foundation

import ATProtoClient
import Domain

/// The kinds of report failure the dialog distinguishes.
///
/// Port of `ReportErrorKind` in
/// `src/components/moderation/ReportDialog/errors.ts`.
public enum ReportErrorKind: String, Sendable, Hashable {
  /// The reporting account is taken down; the report is refused and the
  /// rejection is expected (not reported to telemetry).
  case accountTakedown = "account-takedown"
  /// The labeler rejected the reason type.
  case invalidReasonType = "invalid-reason-type"
  /// A transient upstream/service problem; retrying may work.
  case serviceUnavailable = "service-unavailable"
  /// Anything else.
  case unexpected
}

/// The result of classifying a report failure.
///
/// Port of `ReportErrorClassification`. The `fingerprint`/`tags` fields are the
/// RN telemetry shape; the Swift port keeps them because they encode the
/// buckets the RN tests assert on, and a Views-layer analytics hook can forward
/// them as-is.
public struct ReportErrorClassification: Sendable, Equatable {
  public let kind: ReportErrorKind
  /// Whether this failure should be reported to telemetry.
  public let shouldReport: Bool
  public let fingerprint: [String]
  public let tags: [String: String]

  /// The bucket name, i.e. the fingerprint's second element after
  /// `report-dialog:`.
  public var bucket: String {
    String(fingerprint.last?.dropFirst("report-dialog:".count) ?? "")
  }
}

/// An error shaped like the lex client's `XrpcResponseError`.
///
/// The package's classifier reads only `error`, `message` and `status`, which
/// is exactly what RN reads off the lex error class. Values are normalized into
/// this shape by ``ReportErrorClassifier/classify(_:)``'s overloads.
public struct ReportXrpcError: Error, Sendable, Equatable {
  public let error: String?
  public let message: String
  public let status: Int

  public init(error: String?, message: String, status: Int) {
    self.error = error
    self.message = message
    self.status = status
  }
}

/// Classifies report failures into user-facing and telemetry buckets.
///
/// Port of `classifyReportError`.
public enum ReportErrorClassifier {

  /// The classifier's default fingerprint prefix (RN's `'{{ default }}'`).
  public static let fingerprintPrefix = "{{ default }}"

  /// Classifies a lex-style response error.
  public static func classify(_ error: ReportXrpcError) -> ReportErrorClassification {
    let xrpcTags = [
      "report_xrpc_error": error.error ?? "",
      "report_http_status": String(error.status),
    ]

    if error.error == "AccountTakedown" {
      return classification(
        .accountTakedown, "account-takedown", shouldReport: false, tags: xrpcTags)
    }

    if error.message.hasPrefix("Invalid reason type") {
      return classification(
        .invalidReasonType, "invalid-reason-type", shouldReport: true, tags: xrpcTags)
    }

    if error.message == "Failed to perform upstream request" {
      return classification(
        .serviceUnavailable, "upstream-fetch", shouldReport: true, tags: xrpcTags)
    }

    if error.message == "Internal Server Error" {
      return classification(
        .serviceUnavailable, "upstream-internal", shouldReport: true, tags: xrpcTags)
    }

    if let upstreamStatus = upstreamStatus(in: error.message) {
      return classification(
        ErrorStrings.isRetryableHttpStatus(upstreamStatus)
          ? .serviceUnavailable : .unexpected,
        "upstream-http-\(upstreamStatus)", shouldReport: true, tags: xrpcTags)
    }

    if ErrorStrings.isRetryableHttpStatus(error.status) {
      return classification(
        .serviceUnavailable, "xrpc-retryable-\(error.status)", shouldReport: true, tags: xrpcTags)
    }

    return classification(
      .unexpected, "xrpc-other-\(error.status)", shouldReport: true, tags: xrpcTags)
  }

  /// Classifies any thrown error: anything that is not a lex-style response
  /// error is `unexpected`. `XrpcError` from the Swift client is normalized
  /// into the shape the RN classifier reads.
  public static func classify(_ error: any Error) -> ReportErrorClassification {
    if let shaped = error as? ReportXrpcError {
      return classify(shaped)
    }
    if let xrpc = error as? XrpcError {
      return classify(
        ReportXrpcError(error: xrpc.rawCode, message: xrpc.message ?? "", status: xrpc.status))
    }
    return classification(.unexpected, "unexpected", shouldReport: true)
  }

  /// Extracts the status from `Upstream server responded with a NNN error`.
  ///
  /// RN matches `/^Upstream server responded with a (\d{3}) error$/`. The
  /// Swift port uses the same anchored three-digit match.
  static func upstreamStatus(in message: String) -> Int? {
    let prefix = "Upstream server responded with a "
    let suffix = " error"
    guard message.hasPrefix(prefix), message.hasSuffix(suffix) else { return nil }
    let middle = message.dropFirst(prefix.count).dropLast(suffix.count)
    guard middle.count == 3, middle.allSatisfy(\.isNumber) else { return nil }
    return Int(middle)
  }

  static func classification(
    _ kind: ReportErrorKind, _ bucket: String, shouldReport: Bool,
    tags: [String: String] = [:]
  ) -> ReportErrorClassification {
    var merged = [
      "report_error_kind": kind.rawValue,
      "report_error_bucket": bucket,
    ]
    for (key, value) in tags { merged[key] = value }
    return ReportErrorClassification(
      kind: kind, shouldReport: shouldReport,
      fingerprint: [fingerprintPrefix, "report-dialog:\(bucket)"], tags: merged)
  }
}
