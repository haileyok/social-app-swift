import Testing
import Foundation
@testable import ATProtoClient

/// Sendable collection box for hook assertions.
final class Box<T>: @unchecked Sendable {
  var items: [T] = []
  func append(_ item: T) { items.append(item) }
}

@Suite struct PasswordSessionTests {

  static func makeData(access: String = "acc1", refresh: String = "ref1") -> SessionData {
    SessionData(
      service: "https://pds.example", did: "did:plc:abc", handle: "alice.example",
      accessJwt: access, refreshJwt: refresh)
  }

  @Test func loginFlow() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json([
        "accessJwt": "a1", "refreshJwt": "r1", "did": "did:plc:abc",
        "handle": "alice.example", "email": "a@b.c", "emailConfirmed": true,
      ])
    )
    let session = try await PasswordSession.login(
      service: "https://pds.example", identifier: "alice.example",
      password: "hunter2", transport: transport)
    let data = try await session.sessionData()
    #expect(data.did == "did:plc:abc")
    #expect(data.accessJwt == "a1")
    // the login POST body
    #expect(transport.received.count == 1)
    let req = transport.received[0]
    #expect(req.url.hasSuffix("/xrpc/com.atproto.server.createSession"))
    let body = try #require(
      try JSONSerialization.jsonObject(with: req.body ?? Data()) as? [String: Any])
    #expect(body["identifier"] as? String == "alice.example")
  }

  @Test func loginAuthFactorRequired() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(
        ["error": "AuthFactorTokenRequired", "message": "2FA required"],
        status: 401)
    )
    await #expect(throws: AuthFactorRequiredError.self) {
      _ = try await PasswordSession.login(
        service: "https://pds.example", identifier: "alice.example",
        password: "hunter2", transport: transport)
    }
  }

  @Test func refreshSingleFlight() async throws {
    // First: refreshSession returns new tokens.
    // Concurrent callers must share ONE refresh call.
    let transport = ScriptedTransport(
      ScriptedTransport.json(["accessJwt": "a2", "refreshJwt": "r2", "did": "did:plc:abc",
             "handle": "alice.example"]),
      // getSession fallback (refreshSession omitted didDoc/emailConfirmed)
      ScriptedTransport.json(["did": "did:plc:abc", "emailConfirmed": true, "email": "a@b.c"]),
      ScriptedTransport.json(["accessJwt": "a2", "refreshJwt": "r2", "did": "did:plc:abc",
             "handle": "alice.example"])
    )
    let session = PasswordSession(data: Self.makeData(), transport: transport)
    async let r1: SessionData = session.refresh()
    async let r2: SessionData = session.refresh()
    let (d1, d2) = try await (r1, r2)
    #expect(d1.accessJwt == "a2")
    #expect(d2.accessJwt == "a2")
    // refreshSession + getSession only once each (single-flight)
    let refreshCalls = transport.received.filter {
      $0.url.hasSuffix("com.atproto.server.refreshSession")
    }
    #expect(refreshCalls.count == 1)
    let sessionCalls = transport.received.filter {
      $0.url.hasSuffix("com.atproto.server.getSession")
    }
    #expect(sessionCalls.count == 1)
  }

  @Test func requestRetriesOnExpiredToken() async throws {
    // 1st request: 400 ExpiredToken. 2nd: refreshSession. 3rd: retry OK.
    let transport = ScriptedTransport(
      ScriptedTransport.json(
        ["error": "ExpiredToken", "message": "token expired"], status: 400),
      ScriptedTransport.json(["accessJwt": "a2", "refreshJwt": "r2", "did": "did:plc:abc",
             "handle": "alice.example", "emailConfirmed": true,
             "didDoc": ["service": []]]),
      ScriptedTransport.json(["ok": true])
    )
    let session = PasswordSession(data: Self.makeData(), transport: transport)
    let response = try await session.request(
      method: "app.bsky.feed.getTimeline", httpMethod: "GET")
    #expect(response.status == 200)
    // 3 requests total, and the retry carries the NEW token
    #expect(transport.received.count == 3)
    #expect(
      transport.received[2].headers["Authorization"] == "Bearer a2")
  }

  @Test func sessionTransportRefreshesFeatureClientsAndPreservesProxy() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(
        ["error": "ExpiredToken", "message": "token expired"], status: 400),
      ScriptedTransport.json([
        "accessJwt": "a2", "refreshJwt": "r2", "did": "did:plc:abc",
        "handle": "alice.example", "emailConfirmed": true,
        "didDoc": ["service": []],
      ]),
      ScriptedTransport.json(["feed": []])
    )
    let session = PasswordSession(data: Self.makeData(), transport: transport)
    let client = XrpcClient(
      baseURL: "https://pds.example",
      proxyService: "did:web:api.bsky.app#bsky_appview",
      transport: PasswordSessionTransport(session: session))

    let _: EmptyBody = try await client.get("app.bsky.feed.getTimeline")

    #expect(transport.received.count == 3)
    #expect(transport.received[0].headers["Authorization"] == "Bearer acc1")
    #expect(transport.received[2].headers["Authorization"] == "Bearer a2")
    #expect(
      transport.received[2].headers["atproto-proxy"]
        == "did:web:api.bsky.app#bsky_appview")
  }

  @Test func refreshSchemaErrorDestroysSession() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(
        ["error": "ExpiredToken", "message": "expired"], status: 400)
    )
    let deleted = Box<SessionData>()
    var hooks = SessionHooks()
    hooks.onDeleted = { await deleted.append($0) }
    let session = PasswordSession(
      data: Self.makeData(), hooks: hooks, transport: transport)
    await #expect(throws: SessionInvalidError.self) {
      _ = try await session.refresh()
    }
    #expect(await session.isDestroyed())
    #expect(deleted.items.count == 1)
    #expect(deleted.items[0].did == "did:plc:abc")
  }

  @Test func refreshNetworkFailureKeepsSession() async throws {
    let transport = ScriptedTransport()
    transport.networkError = URLError(.notConnectedToInternet)
    let failures = Box<SessionData>()
    var hooks = SessionHooks()
    hooks.onUpdateFailure = { data, _ in await failures.append(data) }
    let session = PasswordSession(
      data: Self.makeData(), hooks: hooks, transport: transport)
    // Network failure resolves with the OLD session (no throw).
    let data = try await session.refresh()
    #expect(data.accessJwt == "acc1")
    #expect(!(await session.isDestroyed()))
    #expect(failures.items.count == 1)
  }

  @Test func logoutFlow() async throws {
    let transport = ScriptedTransport(ScriptedTransport.json([:]))
    let deleted = Box<SessionData>()
    var hooks = SessionHooks()
    hooks.onDeleted = { await deleted.append($0) }
    let session = PasswordSession(
      data: Self.makeData(), hooks: hooks, transport: transport)
    try await session.logout()
    #expect(await session.isDestroyed())
    #expect(deleted.items.count == 1)
    // deleteSession called with the REFRESH token
    #expect(
      transport.received[0].headers["Authorization"] == "Bearer ref1")
    #expect(transport.received[0].method == "POST")
    #expect(
      transport.received[0].url.hasSuffix("com.atproto.server.deleteSession"))
  }

  @Test func didDocPdsEndpointExtraction() throws {
    let doc = DidDocument(service: [
      .init(id: "#atproto_pds", type: "AtprotoPersonalDataServer",
            serviceEndpoint: "https://real-pds.example"),
      .init(id: "#other", type: "Other", serviceEndpoint: "https://nope"),
    ])
    #expect(extractPdsEndpoint(doc) == "https://real-pds.example")
    #expect(extractPdsEndpoint(nil) == nil)
    #expect(extractPdsEndpoint(DidDocument(service: nil)) == nil)
  }

  @Test func resumeFlow() async throws {
    let transport = ScriptedTransport(
      ScriptedTransport.json(["accessJwt": "a2", "refreshJwt": "r2", "did": "did:plc:abc",
             "handle": "alice.example", "emailConfirmed": true,
             "didDoc": ["service": []]])
    )
    let session = try await PasswordSession.resume(
      Self.makeData(), transport: transport)
    let data = try await session.sessionData()
    #expect(data.accessJwt == "a2")
  }
}
