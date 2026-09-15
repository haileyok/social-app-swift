import ATProtoClient
import Foundation

/// Per-request headers the search endpoints need.
///
/// Ported from `createBskyTopicsHeader` + the `Accept-Language` header the
/// unspecced "suggested"/"trends" queries send in the RN app.
public struct SearchRequestHeaders: Sendable, Equatable {
  /// `X-Bsky-Topics` - the aggregated user interests driving recommendations.
  public var topics: String?
  /// `Accept-Language` - the content languages, comma-joined.
  public var acceptLanguage: String?

  public init(topics: String? = nil, acceptLanguage: String? = nil) {
    self.topics = topics
    self.acceptLanguage = acceptLanguage
  }

  /// The header dictionary actually sent. Empty when nothing is set.
  public var dictionary: [String: String] {
    var headers: [String: String] = [:]
    if let topics { headers["X-Bsky-Topics"] = topics }
    if let acceptLanguage { headers["Accept-Language"] = acceptLanguage }
    return headers
  }
}

/// The narrow slice of XRPC the search feature needs: one typed GET.
///
/// Everything the fetchers do goes through this, so a test can drive the whole
/// feature with a fake that records the method, parameter list and headers
/// instead of standing up a transport. `XrpcClient` conforms below;
/// `FakeSearchClient` in the test target is the other implementation.
///
/// Parameters are pre-encoded as ordered `(name, value)` pairs because that is
/// what ``XrpcClient/url(method:params:)`` consumes, and because a pair list
/// makes "which params did this call send?" directly assertable in a test.
public protocol SearchXRPCCalling: Sendable {
  /// Performs a GET against `method` and decodes the response body as `Output`.
  ///
  /// - Parameters:
  ///   - method: the NSID, e.g. `app.bsky.actor.searchActors`.
  ///   - params: encoded query parameters; `nil` values are omitted.
  ///   - headers: per-request headers (topics, accept-language).
  func get<Output: Decodable & Sendable>(
    _ method: String,
    params: [(String, String?)],
    headers: [String: String]
  ) async throws -> Output
}

extension SearchXRPCCalling {
  /// Convenience overload for requests that carry no extra headers.
  public func get<Output: Decodable & Sendable>(
    _ method: String,
    params: [(String, String?)] = []
  ) async throws -> Output {
    try await get(method, params: params, headers: [:])
  }
}

extension XrpcClient: SearchXRPCCalling {
  public func get<Output: Decodable & Sendable>(
    _ method: String,
    params: [(String, String?)],
    headers: [String: String]
  ) async throws -> Output {
    try await withHeaders(extraHeaders.merging(headers) { _, new in new })
      .get(method, params: params)
  }
}
