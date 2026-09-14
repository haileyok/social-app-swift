import Foundation

/// XRPC client: GET with query params + POST procedures, JSON bodies, typed
/// errors, proxy/labeler header emission.
public struct XrpcClient: Sendable {

  /// How the PDS-side endpoint host is resolved.
  public var baseURL: String

  /// `atproto-proxy: <did#service>` emitted on every request when set.
  public var proxyService: String?

  /// `atproto-accept-labelers: <did>[;redact],...` emitted when non-empty.
  /// `nil` suppresses the header entirely (the PDS-client posture).
  public var labelers: [String]?

  /// Extra headers on every request (e.g. Authorization).
  public var extraHeaders: [String: String]

  public let transport: HTTPTransport

  public init(
    baseURL: String,
    proxyService: String? = nil,
    labelers: [String]? = nil,
    extraHeaders: [String: String] = [:],
    transport: HTTPTransport
  ) {
    self.baseURL = baseURL
    self.proxyService = proxyService
    self.labelers = labelers
    self.extraHeaders = extraHeaders
    self.transport = transport
  }

  /// Returns a copy with a different proxy header value.
  public func withProxy(_ service: String?) -> XrpcClient {
    var copy = self
    copy.proxyService = service
    return copy
  }

  /// Returns a copy with different labeler list (`nil` = suppress).
  public func withLabelers(_ labelers: [String]?) -> XrpcClient {
    var copy = self
    copy.labelers = labelers
    return copy
  }

  /// Returns a copy with different always-on headers.
  public func withHeaders(_ headers: [String: String]) -> XrpcClient {
    var copy = self
    copy.extraHeaders = headers
    return copy
  }

  /// Headers for a request (exposed for tests to assert byte-for-byte).
  public func headers(authorization: String?) -> [String: String] {
    var h = extraHeaders
    if let authorization {
      // callers pass the raw jwt; the header is always Bearer-wrapped
      h["Authorization"] = authorization.hasPrefix("Bearer ")
        ? authorization : "Bearer \(authorization)"
    }
    if let proxyService {
      h["atproto-proxy"] = proxyService
    }
    if let labelers, !labelers.isEmpty {
      h["atproto-accept-labelers"] = labelers.joined(separator: ",")
    }
    return h
  }

  /// URL-encodes a query value (RFC 3986 unreserved + typical XRPC chars).
  static func encodeQueryValue(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  /// Builds the request URL, encoding params. Values may be arrays
  /// (repeated params) or nil (skipped).
  public func url(
    method: String, params: [(String, String?)] = []
  ) -> String {
    var url = baseURL + "/xrpc/" + method
    var queryItems: [String] = []
    for (name, value) in params {
      guard let value else { continue }
      queryItems.append(
        Self.encodeQueryValue(name) + "=" + Self.encodeQueryValue(value))
    }
    if !queryItems.isEmpty {
      url += "?" + queryItems.joined(separator: "&")
    }
    return url
  }

  /// GET query with typed output.
  public func get<Output: Decodable>(
    _ method: String, params: [(String, String?)] = [],
    authorization: String? = nil
  ) async throws -> Output {
    let response = try await rawGet(
      method, params: params, authorization: authorization)
    return try Self.decode(response)
  }

  /// GET returning raw bytes (blob endpoints).
  public func getBlob(
    _ method: String, params: [(String, String?)] = [],
    authorization: String? = nil
  ) async throws -> Data {
    let response = try await rawGet(
      method, params: params, authorization: authorization)
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers, data: response.body)
    }
    return response.body
  }

  public func rawGet(
    _ method: String, params: [(String, String?)] = [],
    authorization: String? = nil
  ) async throws -> HTTPResponse {
    try await transport.send(
      method: "GET", url: url(method: method, params: params),
      headers: headers(authorization: authorization), body: nil)
  }

  /// POST procedure with an optional JSON body (nil = no body bytes sent).
  public func procedure<Body: Encodable & Sendable, Output: Decodable>(
    _ method: String, body: Body?, contentType: String = "application/json",
    authorization: String? = nil
  ) async throws -> Output {
    let bodyData = try body.map { try JSONEncoder().encode($0) }
    let response = try await rawPost(
      method, body: bodyData, contentType: contentType,
      authorization: authorization)
    return try Self.decode(response)
  }

  /// POST with no body (e.g. deleteSession).
  public func procedure<Output: Decodable>(
    _ method: String, authorization: String?
  ) async throws -> Output {
    let response = try await rawPost(
      method, body: nil, contentType: "application/json",
      authorization: authorization)
    return try Self.decode(response)
  }

  public func rawPost(
    _ method: String, body: Data?, contentType: String,
    authorization: String?
  ) async throws -> HTTPResponse {
    var h = headers(authorization: authorization)
    h["Content-Type"] = contentType
    return try await transport.send(
      method: "POST", url: url(method: method), headers: h, body: body)
  }

  static func decode<Output: Decodable>(_ response: HTTPResponse) throws -> Output {
    guard 200..<300 ~= response.status else {
      throw XrpcError.from(
        status: response.status, headers: response.headers,
        data: response.body)
    }
    // Some endpoints (deleteSession, deleteRecord) return an empty body.
    if response.body.isEmpty {
      if let empty = EmptyResponse() as? Output {
        return empty
      }
      // Empty-but-required decoding: only Optional properties can succeed,
      // so an all-optional struct decodes from "{}".
      if let fromObject = try? JSONDecoder().decode(
        Output.self, from: Data("{}".utf8)) {
        return fromObject
      }
    }
    return try JSONDecoder().decode(Output.self, from: response.body)
  }

  /// Sentinel used when a body-less output is acceptable.
  public struct EmptyResponse: Codable, Sendable {
    public init() {}
  }
}

/// Cursor-paginated output shape shared by atproto endpoints.
public struct PaginatedOutput<Item: Decodable & Sendable>: Decodable, Sendable {
  public let cursor: String?
  public let items: [Item]?
}

extension XrpcClient {
  /// Fetches a cursor-paginated endpoint, deduping on merge (by key).
  public func paginate<Item: Decodable & Sendable & Identifiable>(
    _ method: String, params: [(String, String?)] = [],
    authorization: String? = nil, limit: Int? = nil,
    maxPages: Int = 5
  ) async throws -> (items: [Item], cursor: String?) {
    var all: [Item] = []
    var seen = Set<Item.ID>()
    var cursor: String?
    var page = 0
    var currentParams = params
    if let limit {
      currentParams.append(("limit", String(limit)))
    }
    while page < maxPages {
      if let cursor {
        currentParams = currentParams.filter { $0.0 != "cursor" }
        currentParams.append(("cursor", cursor))
      }
      let output: PaginatedOutput<Item> = try await get(
        method, params: currentParams, authorization: authorization)
      for item in output.items ?? [] where !seen.contains(item.id) {
        seen.insert(item.id)
        all.append(item)
      }
      cursor = output.cursor
      page += 1
      if cursor == nil { break }
    }
    return (all, cursor)
  }
}
