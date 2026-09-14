import Foundation
import Testing

import ATProtoClient
import Lexicons
import NotificationsLogic
import SwiftAtproto

/// The XRPC adapter: the exact wire requests the real client emits.
///
/// These drive ``XRPCNotificationClient`` over a scripted transport rather than
/// a protocol-level fake, so a regression in the request shape (URL, method,
/// body) is caught here rather than only at runtime.
@Suite("Notification XRPC adapter")
struct NotificationClientAdapterTests {
  /// A transport that records requests and returns a fixed response.
  final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Received] = []
    private var response: HTTPResponse

    init(response: HTTPResponse) {
      self.response = response
    }

    /// Runs `body` in a synchronous critical section.
    private func withLock<T>(_ body: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return body()
    }

    var received: [Received] {
      withLock { storage }
    }

    func send(
      method: String, url: String, headers: [String: String], body: Data?
    ) async throws -> HTTPResponse {
      let response = withLock { () -> HTTPResponse in
        storage.append(Received(method: method, url: url, body: body))
        return self.response
      }
      return response
    }
  }

  /// One recorded request.
  struct Received: Sendable {
    let method: String
    let url: String
    let body: Data?
    var json: [String: Any] {
      guard let body,
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
      else { return [:] }
      return object
    }
  }

  private func client(_ transport: HTTPTransport) -> XRPCNotificationClient {
    XRPCNotificationClient(
      client: XrpcClient(baseURL: "https://example.test", transport: transport))
  }

  private func emptyOK() -> HTTPResponse {
    HTTPResponse(status: 200, headers: [:], body: Data("{}".utf8))
  }

  /// `updateSeen` posts the watermark as a Z-suffixed ISO-8601 datetime to the
  /// lexicon method, which is the format the endpoint requires.
  @Test func updateSeenSendsIsoDate() async throws {
    let transport = RecordingTransport(response: emptyOK())
    let adapter = client(transport)

    let seenAt = Date(timeIntervalSince1970: 1_800_000_000)
    try await adapter.updateSeen(seenAt: seenAt)

    let request = try #require(transport.received.first)
    #expect(request.method == "POST")
    #expect(request.url == "https://example.test/xrpc/app.bsky.notification.updateSeen")
    let seen = try #require(request.json["seenAt"] as? String)
    #expect(seen.hasSuffix("Z"))
    #expect(seen == "2027-01-15T08:00:00.000Z")
  }

  /// `listNotifications` sends the query parameters on a GET.
  @Test func listNotificationsQuery() async throws {
    let body = """
      {"notifications": [], "cursor": "c1", "priority": true,
       "seenAt": "2026-01-01T00:00:00.000Z"}
      """
    let transport = RecordingTransport(
      response: HTTPResponse(status: 200, headers: [:], body: Data(body.utf8)))
    let adapter = client(transport)

    let output = try await adapter.listNotifications(
      cursor: "abc", limit: 30, priority: true, reasons: ["mention", "reply"])

    let request = try #require(transport.received.first)
    #expect(request.method == "GET")
    #expect(request.url.contains("app.bsky.notification.listNotifications"))
    #expect(request.url.contains("cursor=abc"))
    #expect(request.url.contains("limit=30"))
    #expect(request.url.contains("priority=true"))
    #expect(request.url.contains("reasons=mention"))
    #expect(output.cursor == "c1")
    #expect(output.priority == true)
  }

  /// Omitting reasons leaves the parameter off entirely, which is how the
  /// `all` filter asks the server for everything.
  @Test func listNotificationsOmitsEmptyReasons() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(status: 200, headers: [:], body: Data(#"{"notifications": []}"#.utf8)))
    let adapter = client(transport)
    _ = try await adapter.listNotifications(cursor: nil, limit: 30, priority: nil, reasons: nil)

    let request = try #require(transport.received.first)
    #expect(!request.url.contains("reasons="))
    #expect(!request.url.contains("priority="))
  }

  /// `putActivitySubscription` posts the subscription and subject.
  @Test func putActivitySubscriptionBody() async throws {
    let body = """
      {"subject": "did:plc:alice",
       "activitySubscription": {"post": true, "reply": true}}
      """
    let transport = RecordingTransport(
      response: HTTPResponse(status: 200, headers: [:], body: Data(body.utf8)))
    let adapter = client(transport)

    let output = try await adapter.putActivitySubscription(
      subject: "did:plc:alice", post: true, reply: true)

    let request = try #require(transport.received.first)
    #expect(request.method == "POST")
    #expect(request.url.hasSuffix("app.bsky.notification.putActivitySubscription"))
    #expect(request.json["subject"] as? String == "did:plc:alice")
    let subscription = try #require(request.json["activitySubscription"] as? [String: Any])
    #expect(subscription["post"] as? Bool == true)
    #expect(output.activitySubscription?.reply == true)
  }

  /// `getPosts` posts the URIs as a JSON array.
  @Test func getPostsBody() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(status: 200, headers: [:], body: Data(#"{"posts": []}"#.utf8)))
    let adapter = client(transport)

    _ = try await adapter.getPosts(uris: [Fixtures.postUri])

    let request = try #require(transport.received.first)
    #expect(request.method == "GET")
    let uris = try #require(
      request.url.removingPercentEncoding?.contains("uris=at://did:plc:alice"))
    #expect(uris)
  }

  /// `putNotificationPreferences` forwards every field of the preferences.
  @Test func putPreferencesBody() async throws {
    let reply = """
      {"preferences": {"follow": {"include": "all", "list": true, "push": true},
       "like": {"include": "all", "list": false, "push": false},
       "likeViaRepost": {"include": "all", "list": true, "push": false},
       "mention": {"include": "all", "list": true, "push": true},
       "quote": {"include": "all", "list": true, "push": true},
       "reply": {"include": "all", "list": true, "push": true},
       "repost": {"include": "all", "list": true, "push": true},
       "repostViaRepost": {"include": "all", "list": true, "push": false},
       "starterpackJoined": {"list": false, "push": true},
       "subscribedPost": {"list": true, "push": true},
       "unverified": {"list": true, "push": false},
       "verified": {"list": true, "push": false},
       "chat": {"include": "all", "push": true}}}
      """
    let transport = RecordingTransport(
      response: HTTPResponse(status: 200, headers: [:], body: Data(reply.utf8))
    )
    let adapter = client(transport)
    let prefs = App.Bsky.NotificationDefs_Preferences(
      chat: App.Bsky.NotificationDefs_ChatPreference(include: .all, push: true),
      follow: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      like: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: false, push: false),
      likeViaRepost: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: false),
      mention: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      quote: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      reply: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      repost: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: true),
      repostViaRepost: App.Bsky.NotificationDefs_FilterablePreference(
        include: .all, list: true, push: false),
      starterpackJoined: App.Bsky.NotificationDefs_Preference(list: false, push: true),
      subscribedPost: App.Bsky.NotificationDefs_Preference(list: true, push: true),
      unverified: App.Bsky.NotificationDefs_Preference(list: true, push: false),
      verified: App.Bsky.NotificationDefs_Preference(list: true, push: false)
    )

    _ = try await adapter.putNotificationPreferences(prefs)

    let request = try #require(transport.received.first)
    #expect(request.method == "POST")
    let like = try #require(request.json["like"] as? [String: Any])
    #expect(like["list"] as? Bool == false)
    #expect(like["push"] as? Bool == false)
    let verified = try #require(request.json["verified"] as? [String: Any])
    #expect(verified["list"] as? Bool == true)
  }
}
