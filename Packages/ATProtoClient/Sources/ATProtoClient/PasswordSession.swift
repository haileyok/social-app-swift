import Foundation

/// Persisted session shape (port of the TS `SessionData`).
public struct SessionData: Codable, Sendable, Equatable {
  public var service: String
  public var did: String
  public var handle: String
  public var accessJwt: String
  public var refreshJwt: String
  public var email: String?
  public var emailConfirmed: Bool?
  public var emailAuthFactor: Bool?
  public var active: Bool?
  public var didDoc: DidDocument?

  public init(
    service: String, did: String, handle: String, accessJwt: String,
    refreshJwt: String, email: String? = nil, emailConfirmed: Bool? = nil,
    emailAuthFactor: Bool? = nil, active: Bool? = nil,
    didDoc: DidDocument? = nil
  ) {
    self.service = service
    self.did = did
    self.handle = handle
    self.accessJwt = accessJwt
    self.refreshJwt = refreshJwt
    self.email = email
    self.emailConfirmed = emailConfirmed
    self.emailAuthFactor = emailAuthFactor
    self.active = active
    self.didDoc = didDoc
  }

  /// The PDS endpoint from the didDoc, when parseable; else nil.
  public var pdsEndpoint: String? {
    extractPdsEndpoint(didDoc)
  }
}

/// Minimal did-document shape we care about (service entries).
public struct DidDocument: Codable, Sendable, Equatable {
  public struct ServiceEntry: Codable, Sendable, Equatable {
    public let id: String?
    public let type: String?
    public let serviceEndpoint: String?
  }

  /// `service` may arrive as an array or (malformed servers) other shapes;
  /// decode tolerantly.
  public let service: [ServiceEntry]?

  public init(service: [ServiceEntry]? = nil) {
    self.service = service
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let arr = try? container.decode([ServiceEntry].self, forKey: .service) {
      self.service = arr
    } else if let single = try? container.decode(
      ServiceEntry.self, forKey: .service) {
      self.service = [single]
    } else {
      self.service = nil
    }
  }
}

/// Extracts the `#atproto_pds` service endpoint (port of util.ts).
public func extractPdsEndpoint(_ didDoc: DidDocument?) -> String? {
  guard let entry = didDoc?.service?.first(where: {
    $0.id?.hasSuffix("#atproto_pds") ?? false
  }), let endpoint = entry.serviceEndpoint,
    URL(string: endpoint) != nil
  else { return nil }
  return endpoint
}

/// 2FA-required login failure (mirrors LexAuthFactorError).
public struct AuthFactorRequiredError: Error, Sendable {
  public let underlying: XrpcError
}

/// Session destroyed (logged out).
public struct LoggedOutError: Error, Sendable {}

/// The session is definitely no longer valid (refresh got a schema error).
public struct SessionInvalidError: Error, Sendable {
  public let underlying: XrpcError
}

/// Hook bundle (all optional; none of them throw).
public struct SessionHooks: Sendable {
  public var onUpdated: (@Sendable (SessionData) async -> Void)?
  public var onDeleted: (@Sendable (SessionData) async -> Void)?
  public var onUpdateFailure: (@Sendable (SessionData, XrpcError) async -> Void)?
  public var onDeleteFailure: (@Sendable (SessionData, XrpcError) async -> Void)?

  public init(
    onUpdated: (@Sendable (SessionData) async -> Void)? = nil,
    onDeleted: (@Sendable (SessionData) async -> Void)? = nil,
    onUpdateFailure: (@Sendable (SessionData, XrpcError) async -> Void)? = nil,
    onDeleteFailure: (@Sendable (SessionData, XrpcError) async -> Void)? = nil
  ) {
    self.onUpdated = onUpdated
    self.onDeleted = onDeleted
    self.onUpdateFailure = onUpdateFailure
    self.onDeleteFailure = onDeleteFailure
  }
}

/// Port of @atproto/lex-password-session PasswordSession.
///
/// Owns a mutable session plus a single-flight refresh task: concurrent
/// expired-token failures share one refresh, exactly like the TS
/// `#sessionPromise` chaining.
public actor PasswordSession {

  public private(set) var data: SessionData?
  public let hooks: SessionHooks
  public let transport: HTTPTransport

  /// The in-flight (or completed) refresh task; single-flight semantics.
  private var refreshTask: Task<SessionData, Error>?

  public init(data: SessionData, hooks: SessionHooks = SessionHooks(), transport: HTTPTransport = URLSessionTransport()) {
    self.data = data
    self.hooks = hooks
    self.transport = transport
  }

  public func isDestroyed() -> Bool { data == nil }

  public func sessionData() throws -> SessionData {
    guard let data else { throw LoggedOutError() }
    return data
  }

  /// The PDS base URL for requests: didDoc endpoint when known, else the
  /// login service.
  var requestBase: String {
    data?.pdsEndpoint ?? data?.service ?? ""
  }

  /// An XRPC client bound to this session's PDS.
  public func client() throws -> XrpcClient {
    guard let data else { throw LoggedOutError() }
    return XrpcClient(
      baseURL: requestBase,
      extraHeaders: ["Authorization": "Bearer \(data.accessJwt)"],
      transport: transport)
  }

  // MARK: - fetchHandler equivalent

  /// Performs an authenticated request, refreshing on 401 / 400 ExpiredToken
  /// and retrying once with the new token (port of fetchHandler).
  public func request(
    method: String, httpMethod: String, params: [(String, String?)] = [],
    body: Data? = nil, contentType: String? = nil
  ) async throws -> HTTPResponse {
    guard let current = data else { throw LoggedOutError() }
    let sessionData = await currentSessionOrRefresh()
    var h: [String: String] = ["Authorization": "Bearer \(sessionData.accessJwt)"]
    if let contentType { h["Content-Type"] = contentType }

    let url = XrpcClient(baseURL: requestBase, transport: transport)
      .url(method: method, params: params)
    let initial = try await transport.send(
      method: httpMethod, url: url, headers: h, body: body)

    let refreshNeeded: Bool
    if initial.status == 401 {
      refreshNeeded = true
    } else if initial.status == 400 {
      let err = XrpcError.from(
        status: initial.status, headers: initial.headers, data: initial.body)
      refreshNeeded = err.code == .expiredToken
    } else {
      refreshNeeded = false
    }
    guard refreshNeeded else { return initial }

    // Single-flight: only refresh if we haven't already refreshed since.
    let newSession: SessionData
    do {
      newSession = try await refresh(allowConcurrent: sessionData)
    } catch {
      return initial  // refresh failed: surface the original error response
    }
    // Same token means the refresh didn't produce anything new; don't loop.
    if newSession.accessJwt == sessionData.accessJwt {
      return initial
    }
    h["Authorization"] = "Bearer \(newSession.accessJwt)"
    return try await transport.send(
      method: httpMethod, url: url, headers: h, body: body)
  }

  /// The session to use for a request; used to capture the "awaited an
  /// in-flight refresh" semantics.
  private func currentSessionOrRefresh() async -> SessionData {
    // If a refresh is in flight, await it (single-flight sharing).
    if let task = refreshTask {
      return (try? await task.value) ?? (data ?? SessionData(
        service: "", did: "", handle: "", accessJwt: "", refreshJwt: ""))
    }
    return data ?? SessionData(
      service: "", did: "", handle: "", accessJwt: "", refreshJwt: "")
  }

  // MARK: - refresh

  /// Refreshes tokens via refreshSession; single-flight (port of refresh()).
  /// On schema errors the session is destroyed (onDeleted) and
  /// SessionInvalidError is thrown; on network errors the old session is
  /// kept and returned.
  public func refresh() async throws -> SessionData {
    guard let current = data else { throw LoggedOutError() }
    return try await refresh(allowConcurrent: current)
  }

  private func refresh(allowConcurrent current: SessionData) async throws -> SessionData {
    if let task = refreshTask {
      // Someone is already refreshing; share their result.
      return try await task.value
    }
    let task = Task<SessionData, Error> { [weak self] in
      guard let self else { throw LoggedOutError() }
      return try await self.performRefresh(current: current)
    }
    refreshTask = task
    defer { refreshTask = nil }
    return try await task.value
  }

  private struct RefreshResponse: Codable, Sendable {
    var accessJwt: String?
    var refreshJwt: String?
    var handle: String?
    var did: String?
    var email: String?
    var emailConfirmed: Bool?
    var emailAuthFactor: Bool?
    var active: Bool?
    var didDoc: DidDocument?
  }

  private func performRefresh(current: SessionData) async throws -> SessionData {
    let service = XrpcClient(
      baseURL: current.service, transport: transport)
    // refreshSession targets the login service (not the PDS pin).
    do {
      let response: RefreshResponse = try await service.procedure(
        "com.atproto.server.refreshSession", body: nil as EmptyBody?,
        authorization: current.refreshJwt)
      var next = SessionData(
        service: current.service,
        did: response.did ?? current.did,
        handle: response.handle ?? current.handle,
        accessJwt: response.accessJwt ?? current.accessJwt,
        refreshJwt: response.refreshJwt ?? current.refreshJwt,
        email: response.email ?? current.email,
        emailConfirmed: response.emailConfirmed ?? current.emailConfirmed,
        emailAuthFactor: response.emailAuthFactor ?? current.emailAuthFactor,
        active: response.active ?? current.active,
        didDoc: response.didDoc ?? current.didDoc)
      // Historic quirk: refreshSession may omit emailConfirmed/didDoc; fill
      // via getSession (only trust it when the did matches).
      if next.emailConfirmed == nil || next.didDoc == nil {
        let extra: RefreshResponse? = try? await service.get(
          "com.atproto.server.getSession",
          authorization: next.accessJwt)
        if let extra, extra.did == nil || extra.did == next.did {
          next.email = next.email ?? extra.email
          next.emailConfirmed = next.emailConfirmed ?? extra.emailConfirmed
          next.emailAuthFactor = next.emailAuthFactor ?? extra.emailAuthFactor
          next.active = next.active ?? extra.active
          next.didDoc = next.didDoc ?? extra.didDoc
        }
      }
      data = next
      await hooks.onUpdated?(next)
      return next
    } catch let error as XrpcError {
      if error.code != nil {
        // A recognized XRPC error (ExpiredToken/InvalidRequest/...) means
        // the session is definitively dead.
        await hooks.onDeleted?(current)
        data = nil
        throw SessionInvalidError(underlying: error)
      }
      // Network-ish failure: keep the session, notify.
      await hooks.onUpdateFailure?(current, error)
      return current
    } catch {
      // Non-XRPC failure (URLError etc): keep the session, notify.
      let xrpcError = XrpcError(
        rawCode: nil, message: "\(error)", status: -1)
      await hooks.onUpdateFailure?(current, xrpcError)
      return current
    }
  }

  // MARK: - logout / login / resume

  /// Deletes the session server-side. On unexpected failure the session
  /// stays active and the error is rethrown.
  public func logout() async throws {
    guard let current = data else { throw LoggedOutError() }
    let service = XrpcClient(
      baseURL: current.service, transport: transport)
    do {
      let _: EmptyBody = try await service.procedure(
        "com.atproto.server.deleteSession",
        authorization: current.refreshJwt)
      await hooks.onDeleted?(current)
      data = nil
      refreshTask = nil
    } catch let error as XrpcError {
      if error.code != nil {
        // Server processed and rejected (e.g. already invalid): still a
        // successful logout from our perspective.
        await hooks.onDeleted?(current)
        data = nil
        refreshTask = nil
        return
      }
      await hooks.onDeleteFailure?(current, error)
      throw error
    }
  }

  public struct EmptyBody: Codable, Sendable {
    public init() {}
  }

  public struct CreateSessionBody: Codable, Sendable {
    public var identifier: String
    public var password: String
    public var allowTakendown: Bool?
    public var authFactorToken: String?

    public init(
      identifier: String, password: String, allowTakendown: Bool? = nil,
      authFactorToken: String? = nil
    ) {
      self.identifier = identifier
      self.password = password
      self.allowTakendown = allowTakendown
      self.authFactorToken = authFactorToken
    }
  }

  /// Logs in against `service` (port of PasswordSession.login).
  public static func login(
    service: String, identifier: String, password: String,
    allowTakendown: Bool? = nil, authFactorToken: String? = nil,
    hooks: SessionHooks = SessionHooks(),
    transport: HTTPTransport = URLSessionTransport()
  ) async throws -> PasswordSession {
    let client = XrpcClient(baseURL: service, transport: transport)
    do {
      let response: RefreshResponse = try await client.procedure(
        "com.atproto.server.createSession",
        body: CreateSessionBody(
          identifier: identifier, password: password,
          allowTakendown: allowTakendown, authFactorToken: authFactorToken))
      let data = SessionData(
        service: service,
        did: response.did ?? "",
        handle: response.handle ?? "",
        accessJwt: response.accessJwt ?? "",
        refreshJwt: response.refreshJwt ?? "",
        email: response.email,
        emailConfirmed: response.emailConfirmed,
        emailAuthFactor: response.emailAuthFactor,
        active: response.active,
        didDoc: response.didDoc)
      let session = PasswordSession(
        data: data, hooks: hooks, transport: transport)
      await hooks.onUpdated?(data)
      return session
    } catch let error as XrpcError where error.code == .authFactorTokenRequired {
      throw AuthFactorRequiredError(underlying: error)
    }
  }

  /// Resumes a persisted session by refreshing it (port of resume). Throws
  /// only when the session is *definitely* invalid; network failures keep
  /// the old data.
  public static func resume(
    _ data: SessionData, hooks: SessionHooks = SessionHooks(),
    transport: HTTPTransport = URLSessionTransport()
  ) async throws -> PasswordSession {
    let session = PasswordSession(data: data, hooks: hooks, transport: transport)
    _ = try await session.refresh()
    return session
  }
}
