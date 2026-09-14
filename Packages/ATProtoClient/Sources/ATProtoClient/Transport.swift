import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The single platform-networking shim in the repo (per AGENTS.md, no other
/// package does this).

/// Raw XRPC error payload (`{"error": "...", "message": "..."}`).
public struct XrpcErrorBody: Codable, Sendable {
  public let error: String?
  public let message: String?
}

/// Typed XRPC failure. The `code` mirrors the server's `error` field; common
/// atproto error codes get dedicated cases for exhaustive handling.
public struct XrpcError: Error, Sendable {
  /// Canonical atproto error codes.
  public enum Code: String, Sendable {
    case expiredToken = "ExpiredToken"
    case invalidToken = "InvalidToken"
    case rateLimitExceeded = "RateLimitExceeded"
    case recordNotFound = "RecordNotFound"
    case invalidRequest = "InvalidRequest"
    case authRequired = "AuthenticationRequired"
    case authFactorTokenRequired = "AuthFactorTokenRequired"
    case accountTakedown = "AccountTakedown"
    case blobTooLarge = "BlobTooLarge"
    case invalidSwap = "InvalidSwap"
    case couldNotFindBlob = "CouldNotFindBlob"
    case unsupportedAlgorithm = "UnsupportedAlgorithm"
    case blockedActor = "BlockedActor"
    case chatGone = "ChatGone"
  }

  /// The raw `error` string from the server (nil when the body was not an
  /// XRPC error shape).
  public let rawCode: String?

  /// Typed code when it matches a known constant.
  public let code: Code?

  public let message: String?

  /// HTTP status of the response.
  public let status: Int

  /// `Retry-After` header seconds, when the server sent one.
  public let retryAfterSeconds: Int?

  /// The full response body bytes (for unrecognized shapes).
  public let bodyData: Data?

  public init(
    rawCode: String?, message: String?, status: Int,
    retryAfterSeconds: Int? = nil, bodyData: Data? = nil
  ) {
    self.rawCode = rawCode
    self.code = rawCode.flatMap(Code.init(rawValue:))
    self.message = message
    self.status = status
    self.retryAfterSeconds = retryAfterSeconds
    self.bodyData = bodyData
  }

  public static func from(
    status: Int, headers: [String: String], data: Data?
  ) -> XrpcError {
    var rawCode: String?
    var message: String?
    if let data,
      let body = try? JSONDecoder().decode(XrpcErrorBody.self, from: data),
      body.error != nil || body.message != nil
    {
      rawCode = body.error
      message = body.message
    }
    let retryHeaderValue = headers.first(where: {
      $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame
    })?.value
    let retryAfter = retryHeaderValue.flatMap { value in Int(value) }
    return XrpcError(
      rawCode: rawCode, message: message, status: status,
      retryAfterSeconds: retryAfter, bodyData: data)
  }
}

/// A minimal HTTP response abstraction so the transport can be driven by
/// URLSession or the TestSupport fake server interchangeably.
public struct HTTPResponse: Sendable {
  public let status: Int
  /// Header names lowercased.
  public let headers: [String: String]
  public let body: Data

  public init(status: Int, headers: [String: String], body: Data) {
    self.status = status
    self.headers = Dictionary(
      headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    self.body = body
  }

  public var contentType: String? {
    headers["content-type"]?.split(separator: ";").first.map {
      $0.trimmingCharacters(in: .whitespaces).lowercased()
    }
  }
}

/// The network transport the XRPC client runs over. `URLSessionTransport`
/// is the production impl; TestSupport provides fakes.
public protocol HTTPTransport: Sendable {
  /// Performs a request. `headers` names are case-preserved as given.
  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse
}

/// URLSession-backed transport. Owns the `User-Agent` default.
public struct URLSessionTransport: HTTPTransport {
  public let userAgent: String
  public let session: URLSession

  public init(userAgent: String = "SocialAppSwift/0.1 (Linux; atproto)") {
    self.userAgent = userAgent
    self.session = URLSession(configuration: .ephemeral)
  }

  public func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = method
    request.httpBody = body
    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }
    if headers["User-Agent"] == nil {
      request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }
    // URLSession on Linux does not auto-decompress responses, and advertising
    // any encoding makes servers compress bodies we then can't decode.
    // Request identity until decompression is handled explicitly.
    if headers["Accept-Encoding"] == nil {
      request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    }
    let (data, resp) = try await session.data(for: request)
    guard let http = resp as? HTTPURLResponse else {
      throw XrpcError(
        rawCode: nil, message: "non-HTTP response", status: -1)
    }
    var hdrs: [String: String] = [:]
    for (k, v) in http.allHeaderFields {
      if let key = k as? String, let val = v as? String {
        hdrs[key] = val
      }
    }
    return HTTPResponse(status: http.statusCode, headers: hdrs, body: data)
  }
}
