import Testing
import Foundation
@testable import ATProtoClient

/// A transport that plays a scripted sequence of responses, recording every
/// request for byte-for-byte header assertion.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
  struct Received: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?
  }

  var received: [Received] = []
  private var responses: [(HTTPResponse)?]
  private var index = 0
  /// When set, the transport throws this instead of playing the script.
  var networkError: (any Error)?

  init(_ responses: (HTTPResponse)?...) {
    self.responses = responses
  }

  static func json(
    _ payload: [String: Any?],
    status: Int = 200,
    headers: [String: String] = ["Content-Type": "application/json"]
  ) -> HTTPResponse {
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return HTTPResponse(status: status, headers: headers, body: data)
  }

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    received.append(Received(method: method, url: url, headers: headers, body: body))
    if let networkError {
      throw networkError
    }
    guard index < responses.count else {
      return HTTPResponse(
        status: 500, headers: [:], body: Data("script exhausted".utf8))
    }
    let response = responses[index]
    index += 1
    if let response {
      return response
    } else {
      throw URLError(.badServerResponse)
    }
  }
}

@Suite struct HeaderAssemblyTests {
  @Test func appviewProxyHeader() {
    let client = XrpcClient(
      baseURL: "https://pds.example", proxyService: BlueskyAPI.appService,
      labelers: [], transport: ScriptedTransport())
    let h = client.headers(authorization: "Bearer tok")
    #expect(h["atproto-proxy"] == "did:web:api.bsky.app#bsky_appview")
    #expect(h["Authorization"] == "Bearer tok")
  }

  @Test func pdsClientHasNoProxyNoLabelers() {
    let client = XrpcClient(
      baseURL: "https://pds.example", proxyService: nil, labelers: nil,
      transport: ScriptedTransport())
    let h = client.headers(authorization: nil)
    #expect(h["atproto-proxy"] == nil)
    #expect(h["atproto-accept-labelers"] == nil)
  }

  @Test func labelerHeaderByteForByte() {
    // Default (no country): app labeler ;redact + ALL country labelers ;redact
    let appLabelers = LabelerHeader.appLabelers(country: nil)
    #expect(appLabelers.count == 12)  // moderation + 11 country/eu labelers
    #expect(appLabelers.first == "did:plc:ar7c4by46qjdydhdevvrndac;redact")
    let joined = appLabelers.joined(separator: ",")
    #expect(joined.contains("did:plc:ekitcvx7uwnauoqy5oest3hm;redact"))

    // Subscribed: Bluesky's own moderation did is filtered out; arbitrary
    // labelers pass through unredacted.
    let subscribed = LabelerHeader.subscribedLabelers([
      "did:plc:ar7c4by46qjdydhdevvrndac",
      "did:plc:wwwwwwwwwwwwwwwwwwwwwwwww",
    ])
    #expect(subscribed == ["did:plc:wwwwwwwwwwwwwwwwwwwwwwwww"])

    let client = XrpcClient(
      baseURL: "https://pds.example", proxyService: BlueskyAPI.appService,
      labelers: appLabelers + subscribed, transport: ScriptedTransport())
    let h = client.headers(authorization: nil)
    #expect(h["atproto-accept-labelers"] == joined + ",did:plc:wwwwwwwwwwwwwwwwwwwwwwwww")
  }

  @Test func countryLabelers() {
    #expect(
      LabelerHeader.appLabelers(country: "BR")
        == ["did:plc:ar7c4by46qjdydhdevvrndac;redact",
            "did:plc:ekitcvx7uwnauoqy5oest3hm;redact"])
    #expect(
      LabelerHeader.appLabelers(country: "DE")
        == ["did:plc:ar7c4by46qjdydhdevvrndac;redact",
            "did:plc:z57lz5dhgz2dkjogoysm3vut;redact",
            "did:plc:r55ow3tocux5kafs5dq445fy;redact"])
  }

  @Test func queryEncoding() {
    let client = XrpcClient(baseURL: "https://pds.example", transport: ScriptedTransport())
    let url = client.url(
      method: "app.bsky.feed.getTimeline",
      params: [("limit", "10"), ("cursor", "abc/def"), ("skip", nil)])
    #expect(
      url == "https://pds.example/xrpc/app.bsky.feed.getTimeline?limit=10&cursor=abc%2Fdef")
  }
}

@Suite struct XrpcErrorTests {
  @Test func typedErrorAndRetryAfter() {
    let body = try! JSONSerialization.data(
      withJSONObject: ["error": "RateLimitExceeded", "message": "slow down"])
    let error = XrpcError.from(
      status: 429, headers: ["Retry-After": "30"], data: body)
    #expect(error.code == .rateLimitExceeded)
    #expect(error.retryAfterSeconds == 30)
    #expect(error.status == 429)
  }

  @Test func unknownCodeStaysRaw() {
    let body = try! JSONSerialization.data(
      withJSONObject: ["error": "SomethingNew"])
    let error = XrpcError.from(status: 400, headers: [:], data: body)
    #expect(error.code == nil)
    #expect(error.rawCode == "SomethingNew")
  }
}
