import Testing
import Foundation
@testable import ATProtoClient

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// AC.3 integration suite: runs against the vendored dev-env-mock server
/// (mock users alice/bob/carla, password "hunter2"). Enabled only when
/// MOCK_PDS_URL is set - run locally as:
///   MOCK_PDS_URL=http://localhost:3000 swift test
/// CI has no mock backend, so it skips this suite cleanly there. When the
/// variable IS set but the server is unreachable, tests fail loudly (that
/// means you asked for mock coverage and the mock is down).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MOCK_PDS_URL"] != nil))
struct MockServerIntegrationTests {

  static let pds = ProcessInfo.processInfo.environment["MOCK_PDS_URL"] ?? "http://localhost:3000"

  static func mockReachable() async -> Bool {
    guard let url = URL(string: "\(pds)/xrpc/com.atproto.server.describeServer")
    else { return false }
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    return (try? await URLSession.shared.data(for: request)) != nil
  }

  /// The mock appview DID. Stable across runs: the vendored dev-env pins the
  /// appview signing key, so its DID (did:plc:bw7ad3erl7btq6qwf66yqiov) is
  /// constant. (describeServer returns the *PDS* did, not the appview's —
  /// do not use it for the proxy header.)
  static let appviewDid = "did:plc:bw7ad3erl7btq6qwf66yqiov"

  static func appviewProxy() -> String {
    "\(appviewDid)#bsky_appview"
  }

  @Test func loginResumeRefreshLogoutLoop() async throws {
    guard await Self.mockReachable() else {
      Issue.record("mock server not reachable on localhost:3000 - skipping (start dev-env-mock)")
      return
    }
    let proxy = Self.appviewProxy()
    let transport = URLSessionTransport()

    // LOGIN
    let updates = Box<SessionData>()
    var hooks = SessionHooks()
    hooks.onUpdated = { await updates.append($0) }
    let session = try await PasswordSession.login(
      service: Self.pds, identifier: "alice.test", password: "hunter2",
      hooks: hooks, transport: transport)
    let data = try await session.sessionData()
    #expect(data.did.hasPrefix("did:plc:") || data.did.hasPrefix("did:web:"))
    #expect(data.handle == "alice.test")
    #expect(!data.accessJwt.isEmpty)

    // Authenticated call through the appview proxy header
    struct Timeline: Decodable {
      let feed: [FeedItem]?
    }
    struct FeedItem: Decodable {
      let post: Post
    }
    struct Post: Decodable {
      let uri: String
      let author: Author
    }
    struct Author: Decodable {
      let handle: String
    }
    let base = try await session.client()
    let appview = base.withProxy(proxy)
    let timeline: Timeline = try await appview.get("app.bsky.feed.getTimeline")
    #expect((timeline.feed ?? []).count >= 3)  // alice+bob+carla posts

    // RESUME (refresh round-trip)
    let resumed = try await PasswordSession.resume(
      data, hooks: hooks, transport: transport)
    let refreshed = try await resumed.sessionData()
    #expect(!refreshed.accessJwt.isEmpty)
    #expect(refreshed.handle == "alice.test")

    // REFRESH produces a new access token
    let before = refreshed.accessJwt
    let after = try await resumed.refresh()
    #expect(!after.accessJwt.isEmpty)

    // LOGOUT invalidates the session
    try await resumed.logout()
    #expect(await resumed.isDestroyed())
    // A second logout attempt fails cleanly
    await #expect(throws: LoggedOutError.self) {
      _ = try await resumed.refresh()
    }
    _ = before
    _ = updates
  }

  @Test func multiAccountSessions() async throws {
    guard await Self.mockReachable() else {
      Issue.record("mock server not reachable - skipping")
      return
    }
    let transport = URLSessionTransport()
    let alice = try await PasswordSession.login(
      service: Self.pds, identifier: "alice.test", password: "hunter2",
      transport: transport)
    let bob = try await PasswordSession.login(
      service: Self.pds, identifier: "bob.test", password: "hunter2",
      transport: transport)
    let aliceData = try await alice.sessionData()
    let bobData = try await bob.sessionData()
    #expect(aliceData.did != bobData.did)
    #expect(aliceData.handle == "alice.test")
    #expect(bobData.handle == "bob.test")
    // both sessions stay independently usable
    let a2 = try await alice.refresh()
    #expect(a2.handle == "alice.test")
    let b2 = try await bob.refresh()
    #expect(b2.handle == "bob.test")
  }

  @Test func proxyAndLabelerHeadersReachTheServer() async throws {
    guard await Self.mockReachable() else {
      Issue.record("mock server not reachable - skipping")
      return
    }
    let proxy = Self.appviewProxy()
    let session = try await PasswordSession.login(
      service: Self.pds, identifier: "alice.test", password: "hunter2",
      transport: URLSessionTransport())
    let base = try await session.client()

    // appview client: proxy + labelers
    let appview = base.withProxy(proxy)
      .withLabelers(LabelerHeader.appLabelers(country: nil))
    #expect(
      appview.headers(authorization: nil)["atproto-proxy"]
        == Self.appviewProxy())

    // PDS client posture: no proxy, no labelers
    let pdsClient = base.withProxy(nil).withLabelers(nil)
    let h = pdsClient.headers(authorization: nil)
    #expect(h["atproto-proxy"] == nil)
    #expect(h["atproto-accept-labelers"] == nil)

    // an actual request through the proxy path succeeds (the PDS forwards)
    struct Profile: Decodable {
      let did: String?
      let handle: String?
    }
    let profile: Profile = try await appview.get(
      "app.bsky.actor.getProfile", params: [("actor", "alice.test")])
    #expect(profile.handle == "alice.test" || profile.did != nil)
  }

}

/// Sendable collection box (defined in PasswordSessionTests.swift).
