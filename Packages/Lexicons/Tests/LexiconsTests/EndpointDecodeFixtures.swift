import Testing
import Foundation
@testable import Lexicons

/// Fixture decode coverage for the additional generated endpoint shapes the
/// app consumes: `app.bsky.feed.getPostThread`, `app.bsky.feed.getAuthorFeed`,
/// `app.bsky.notification.listNotifications`, `app.bsky.actor.getPreferences`
/// (preferences v3 defs), and `chat.bsky.convo.getLog`.
///
/// Fixtures are trimmed real-shaped responses; the goal is to pin the generated
/// Codable surface (field names, optionals, open-union `$type` dispatch) so
/// codegen changes that break decoding fail here rather than at runtime.
@Suite struct EndpointDecodeFixtures {
  private static let postUri = "at://did:plc:abcdef/app.bsky.feed.post/3k2f7r"
  private static let postCid =
    "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdbejg4lf4hwbpf3cli"

  /// One `app.bsky.feed.defs#postView` payload, reused across fixtures.
  private static func postJSON(additional: String = "") -> String {
    """
    {
      "uri": "\(postUri)",
      "cid": "\(postCid)",
      "author": {"did": "did:plc:abcdef", "handle": "alice.example"},
      "record": {
        "$type": "app.bsky.feed.post",
        "text": "Hello world",
        "createdAt": "2026-01-01T00:00:00Z"
      },
      "indexedAt": "2026-01-01T00:00:00Z"\(additional)
    }
    """
  }

  // MARK: - getPostThread

  /// A thread whose root is a `#threadViewPost` with a nested reply.
  @Test func decodesPostThreadWithNestedReply() throws {
    let json = """
    {
      "thread": {
        "$type": "app.bsky.feed.defs#threadViewPost",
        "post": \(Self.postJSON()),
        "replies": [
          {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:abcdef/app.bsky.feed.post/3k2f7s",
              "cid": "\(Self.postCid)",
              "author": {"did": "did:plc:bob", "handle": "bob.example"},
              "record": {
                "$type": "app.bsky.feed.post",
                "text": "a reply",
                "createdAt": "2026-01-01T00:01:00Z"
              },
              "indexedAt": "2026-01-01T00:01:00Z"
            }
          }
        ]
      }
    }
    """
    let output = try JSONDecoder().decode(
      App.Bsky.FeedGetPostThread_Output.self, from: Data(json.utf8))
    guard case .feedDefsThreadViewPost(let root) = output.thread else {
      Issue.record("expected threadViewPost, got \(output.thread)")
      return
    }
    #expect(root.post.record.type == "app.bsky.feed.post")
    #expect(root.replies?.count == 1)
  }

  /// A `#notFoundPost` thread root decodes to its own union case, not `_other`.
  @Test func decodesNotFoundThreadRoot() throws {
    let json = """
    {"thread": {
      "$type": "app.bsky.feed.defs#notFoundPost",
      "uri": "\(Self.postUri)",
      "notFound": true
    }}
    """
    let output = try JSONDecoder().decode(
      App.Bsky.FeedGetPostThread_Output.self, from: Data(json.utf8))
    guard case .feedDefsNotFoundPost(let notFound) = output.thread else {
      Issue.record("expected notFoundPost, got \(output.thread)")
      return
    }
    #expect(notFound.notFound == true)
  }

  /// An unknown thread `$type` falls back to the open-union escape hatch.
  @Test func decodesUnknownThreadTypeAsOther() throws {
    let json = """
    {"thread": {"$type": "app.bsky.feed.defs#someFutureThreadView", "x": 1}}
    """
    let output = try JSONDecoder().decode(
      App.Bsky.FeedGetPostThread_Output.self, from: Data(json.utf8))
    guard case ._other = output.thread else {
      Issue.record("expected open-union fallback, got \(output.thread)")
      return
    }
  }

  // MARK: - getAuthorFeed

  /// `getAuthorFeed` feed items carry `feedViewPost` wrappers and a cursor.
  @Test func decodesAuthorFeed() throws {
    let json = """
    {
      "cursor": "next-page",
      "feed": [
        {
          "post": \(Self.postJSON()),
          "reply": {
            "root": {"$type": "com.atproto.repo.strongRef",
              "uri": "\(Self.postUri)", "cid": "\(Self.postCid)"},
            "parent": {"$type": "com.atproto.repo.strongRef",
              "uri": "\(Self.postUri)", "cid": "\(Self.postCid)"}
          }
        },
        {"post": \(Self.postJSON())}
      ]
    }
    """
    let output = try JSONDecoder().decode(
      App.Bsky.FeedGetAuthorFeed_Output.self, from: Data(json.utf8))
    #expect(output.cursor == "next-page")
    #expect(output.feed.count == 2)
    #expect(output.feed[0].reply != nil)
    #expect(output.feed[1].reply == nil)
  }

  // MARK: - listNotifications

  /// Notifications decode with their `reason` enum and an opaque `record`.
  @Test func decodesNotifications() throws {
    let json = """
    {
      "cursor": "cursor-1",
      "seenAt": "2026-01-01T00:00:00.000Z",
      "notifications": [
        {
          "uri": "\(Self.postUri)",
          "cid": "\(Self.postCid)",
          "author": {"did": "did:plc:bob", "handle": "bob.example"},
          "reason": "reply",
          "reasonSubject": "\(Self.postUri)",
          "record": {
            "$type": "app.bsky.feed.post",
            "text": "a reply",
            "createdAt": "2026-01-01T00:01:00Z"
          },
          "isRead": false,
          "indexedAt": "2026-01-01T00:01:00Z"
        }
      ]
    }
    """
    let output = try JSONDecoder().decode(
      App.Bsky.NotificationListNotifications_Output.self, from: Data(json.utf8))
    #expect(output.cursor == "cursor-1")
    #expect(output.seenAt != nil)
    let note = try #require(output.notifications.first)
    #expect(note.reason == .reply)
    #expect(note.isRead == false)
    #expect(note.reasonSubject?.rawValue == Self.postUri)
  }

  /// An unknown notification `reason` must not throw.
  @Test func decodesUnknownNotificationReason() throws {
    let json = """
    {"notifications": [{
      "uri": "\(Self.postUri)",
      "cid": "\(Self.postCid)",
      "author": {"did": "did:plc:bob", "handle": "bob.example"},
      "reason": "someFutureReason",
      "record": {"$type": "app.bsky.feed.post", "text": "x",
        "createdAt": "2026-01-01T00:00:00Z"},
      "isRead": true,
      "indexedAt": "2026-01-01T00:00:00Z"
    }]}
    """
    let output = try JSONDecoder().decode(
      App.Bsky.NotificationListNotifications_Output.self, from: Data(json.utf8))
    #expect(output.notifications.first?.reason == ._other("someFutureReason"))
  }

  // MARK: - getPreferences (preferences v3 defs)

  /// The v3 preferences list decodes into the open union of
  /// `app.bsky.actor.defs#*Pref` members, including nested `savedFeedsPrefV2`.
  @Test func decodesPreferencesV3() throws {
    let json = """
    {
      "preferences": [
        {"$type": "app.bsky.actor.defs#adultContentPref", "enabled": false},
        {"$type": "app.bsky.actor.defs#contentLabelPref",
          "label": "nudity", "visibility": "hide"},
        {"$type": "app.bsky.actor.defs#savedFeedsPrefV2", "items": [
          {"id": "default", "pinned": true, "type": "timeline",
            "value": "following"},
          {"id": "custom-1", "pinned": false, "type": "feed",
            "value": "at://did:plc:abc/app.bsky.feed.generator/whats-hot"}
        ]},
        {"$type": "app.bsky.actor.defs#interestsPref",
          "tags": ["tech", "music"]},
        {"$type": "app.bsky.actor.defs#labelersPref", "labelers": []}
      ]
    }
    """
    let output = try JSONDecoder().decode(
      App.Bsky.ActorGetPreferences_Output.self, from: Data(json.utf8))
    #expect(output.preferences.count == 5)

    guard case .actorDefsSavedFeedsPrefV2(let saved) = output.preferences[2] else {
      Issue.record("expected savedFeedsPrefV2, got \(output.preferences[2])")
      return
    }
    #expect(saved.items.count == 2)
    #expect(saved.items[0].type == .timeline)
    #expect(saved.items[1].type == .feed)
    #expect(saved.items[0].pinned == true)

    guard case .actorDefsInterestsPref(let interests) = output.preferences[3] else {
      Issue.record("expected interestsPref")
      return
    }
    #expect(interests.tags == ["tech", "music"])
  }

  /// An unknown preference `$type` (a newer client's pref) decodes to `_other`.
  @Test func decodesUnknownPreferenceType() throws {
    let json = """
    {"preferences": [{"$type": "app.bsky.actor.defs#futurePref", "a": 1}]}
    """
    let output = try JSONDecoder().decode(
      App.Bsky.ActorGetPreferences_Output.self, from: Data(json.utf8))
    guard case ._other = output.preferences[0] else {
      Issue.record("expected open-union fallback, got \(output.preferences[0])")
      return
    }
  }

  // MARK: - chat.bsky.convo.getLog

  /// Chat log entries decode as a discriminated union of convo events.
  @Test func decodesChatConvoLog() throws {
    let convoId = "3k2f7rconvoid"
    let json = """
    {
      "cursor": "log-cursor",
      "logs": [
        {"$type": "chat.bsky.convo.defs#logBeginConvo",
          "rev": "rev-1", "convoId": "\(convoId)"},
        {"$type": "chat.bsky.convo.defs#logCreateMessage",
          "rev": "rev-2", "convoId": "\(convoId)",
          "message": {
            "$type": "chat.bsky.convo.defs#messageView",
            "id": "msg-1", "rev": "rev-2", "text": "hi",
            "sender": {"did": "did:plc:abcdef"},
            "sentAt": "2026-01-01T00:00:00.000Z"
          }}
      ]
    }
    """
    let output = try JSONDecoder().decode(
      Chat.Bsky.ConvoGetLog_Output.self, from: Data(json.utf8))
    #expect(output.cursor == "log-cursor")
    #expect(output.logs.count == 2)

    guard case .convoDefsLogBeginConvo(let begin) = output.logs[0] else {
      Issue.record("expected logBeginConvo, got \(output.logs[0])")
      return
    }
    #expect(begin.convoId == convoId)

    guard case .convoDefsLogCreateMessage(let created) = output.logs[1] else {
      Issue.record("expected logCreateMessage, got \(output.logs[1])")
      return
    }
    guard case .convoDefsMessageView(let message) = created.message else {
      Issue.record("expected messageView, got \(created.message)")
      return
    }
    #expect(message.text == "hi")
  }

  // MARK: - com.germnetwork.declaration (record, newly allowlisted)

  /// The Germ declaration record decodes now that its namespace is generated.
  @Test func decodesGermDeclarationRecord() throws {
    let json = """
    {
      "$type": "com.germnetwork.declaration",
      "version": "1.0.0",
      "currentKey": "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
      "messageMe": {
        "showButtonTo": "everyone",
        "messageMeUrl": "https://example.com/msg"
      }
    }
    """
    let record = try JSONDecoder().decode(
      Com.Germnetwork.Declaration.self, from: Data(json.utf8))
    #expect(record.type == "com.germnetwork.declaration")
  }
}
