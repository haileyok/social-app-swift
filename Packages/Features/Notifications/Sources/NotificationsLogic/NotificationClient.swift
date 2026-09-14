import Foundation

import ATProtoClient
import Lexicons
import SwiftAtproto

public protocol NotificationClient: Sendable {
  /// `app.bsky.notification.listNotifications`.
  func listNotifications(
    cursor: String?,
    limit: Int?,
    priority: Bool?,
    reasons: [String]?
  ) async throws -> App.Bsky.NotificationListNotifications_Output

  /// `app.bsky.feed.getPosts`, for resolving notification subjects in bulk.
  func getPosts(uris: [String]) async throws -> App.Bsky.FeedGetPosts_Output

  /// `app.bsky.graph.getStarterPacks`, for resolving starter-pack subjects.
  func getStarterPacks(uris: [String]) async throws -> App.Bsky.GraphGetStarterPacks_Output

  /// `app.bsky.notification.listActivitySubscriptions`.
  func listActivitySubscriptions(
    cursor: String?,
    limit: Int?
  ) async throws -> App.Bsky.NotificationListActivitySubscriptions_Output

  /// `app.bsky.notification.putActivitySubscription`.
  func putActivitySubscription(
    subject: String,
    post: Bool,
    reply: Bool
  ) async throws -> App.Bsky.NotificationPutActivitySubscription_Output

  /// `app.bsky.notification.getPreferences`.
  func getNotificationPreferences() async throws -> App.Bsky.NotificationGetPreferences_Output

  /// `app.bsky.notification.putPreferencesV2`.
  func putNotificationPreferences(
    _ preferences: App.Bsky.NotificationDefs_Preferences
  ) async throws -> App.Bsky.NotificationPutPreferencesV2_Output

  /// `app.bsky.notification.updateSeen`.
  func updateSeen(seenAt: Date) async throws
}

/// Adapts an ``XrpcClient`` to ``NotificationClient``.
///
/// Construct one over the appview client. The adapter adds no caching and no
/// retries: it exists only to translate the protocol's plain arguments into the
/// lexicon endpoints' request shape. It goes through `XrpcClient`'s public
/// `get`/`procedure` methods rather than the generated `XRPCCallable` methods,
/// because `XrpcClient` does not conform to `XRPCCallable` (the generated
/// protocol is implemented by the appview service object, not by this client).
public struct XRPCNotificationClient: NotificationClient {
  private let client: XrpcClient
  private let authorization: @Sendable () async throws -> String?

  public init(
    client: XrpcClient,
    authorization: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    self.client = client
    self.authorization = authorization
  }

  public func listNotifications(
    cursor: String?,
    limit: Int?,
    priority: Bool?,
    reasons: [String]?
  ) async throws -> App.Bsky.NotificationListNotifications_Output {
    var params: [(String, String?)] = [
      ("cursor", cursor),
      ("limit", limit.map(String.init)),
      ("priority", priority.map(String.init)),
    ]
    // `reasons` is a repeated query item, which is what the wire format uses.
    for reason in reasons ?? [] { params.append(("reasons", reason)) }
    return try await client.get(
      "app.bsky.notification.listNotifications",
      params: params,
      authorization: try await authorization())
  }

  public func getPosts(uris: [String]) async throws -> App.Bsky.FeedGetPosts_Output {
    try await client.get(
      "app.bsky.feed.getPosts",
      params: uris.map { ("uris", $0) },
      authorization: try await authorization())
  }

  public func getStarterPacks(
    uris: [String]
  ) async throws -> App.Bsky.GraphGetStarterPacks_Output {
    try await client.get(
      "app.bsky.graph.getStarterPacks",
      params: uris.map { ("uris", $0) },
      authorization: try await authorization())
  }

  public func listActivitySubscriptions(
    cursor: String?,
    limit: Int?
  ) async throws -> App.Bsky.NotificationListActivitySubscriptions_Output {
    try await client.get(
      "app.bsky.notification.listActivitySubscriptions",
      params: [("cursor", cursor), ("limit", limit.map(String.init))],
      authorization: try await authorization())
  }

  public func putActivitySubscription(
    subject: String, post: Bool, reply: Bool
  ) async throws -> App.Bsky.NotificationPutActivitySubscription_Output {
    let input = App.Bsky.NotificationPutActivitySubscription_Input(
      activitySubscription: App.Bsky.NotificationDefs_ActivitySubscription(
        post: post, reply: reply),
      subject: FormatString<DID>(rawValue: subject))
    return try await client.procedure(
      "app.bsky.notification.putActivitySubscription",
      body: input,
      authorization: try await authorization())
  }

  public func getNotificationPreferences() async throws
    -> App.Bsky.NotificationGetPreferences_Output {
    try await client.get(
      "app.bsky.notification.getPreferences",
      authorization: try await authorization())
  }

  public func putNotificationPreferences(
    _ preferences: App.Bsky.NotificationDefs_Preferences
  ) async throws -> App.Bsky.NotificationPutPreferencesV2_Output {
    // putPreferencesV2 takes a patch of optional fields, not a whole Preferences
    // object, so every field is forwarded explicitly.
    let input = App.Bsky.NotificationPutPreferencesV2_Input(
      chat: preferences.chat,
      follow: preferences.follow,
      like: preferences.like,
      likeViaRepost: preferences.likeViaRepost,
      mention: preferences.mention,
      quote: preferences.quote,
      reply: preferences.reply,
      repost: preferences.repost,
      repostViaRepost: preferences.repostViaRepost,
      starterpackJoined: preferences.starterpackJoined,
      subscribedPost: preferences.subscribedPost,
      unverified: preferences.unverified,
      verified: preferences.verified
    )
    return try await client.procedure(
      "app.bsky.notification.putPreferencesV2",
      body: input,
      authorization: try await authorization())
  }

  public func updateSeen(seenAt: Date) async throws {
    let input = App.Bsky.NotificationUpdateSeen_Input(
      seenAt: FormatString<Date>(rawValue: Self.iso(seenAt)))
    // The endpoint answers with an empty body, so the adapter asks the client
    // for its own empty response type rather than the generated one.
    let _: XrpcClient.EmptyResponse = try await client.procedure(
      "app.bsky.notification.updateSeen",
      body: input,
      authorization: try await authorization())
  }

  /// `toISOString`-equivalent: always UTC, always `Z`-suffixed, millisecond
  /// precision, which is the format `app.bsky.notification.updateSeen` wants.
  static func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }
}
