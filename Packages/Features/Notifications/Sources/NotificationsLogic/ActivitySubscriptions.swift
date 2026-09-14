import Foundation

import Lexicons
import QueryStore

public struct ActivitySubscription: Sendable, Hashable {
  /// Notify on new posts.
  public var post: Bool
  /// Notify on replies.
  public var reply: Bool

  public init(post: Bool = false, reply: Bool = false) {
    self.post = post
    self.reply = reply
  }

  /// The lexicon shape.
  public var lexical: App.Bsky.NotificationDefs_ActivitySubscription {
    App.Bsky.NotificationDefs_ActivitySubscription(post: post, reply: reply)
  }

  public init(_ lexical: App.Bsky.NotificationDefs_ActivitySubscription) {
    self.post = lexical.post
    self.reply = lexical.reply
  }

  /// True when neither channel is on, i.e. there is no subscription.
  public var isEmpty: Bool { !post && !reply }

  /// The subscription on a profile's viewer state, when the server sent one.
  public static func from(
    _ viewer: App.Bsky.ActorDefs_ViewerState?
  ) -> ActivitySubscription? {
    viewer?.activitySubscription.map(ActivitySubscription.init)
  }
}

/// The activity-subscriptions read/write API.
///
/// The read is the port of `useActivitySubscriptionsQuery`, an infinite query
/// with no page size (the server defaults it). The write is the port of the
/// `putActivitySubscription` mutation in `SubscribeProfileDialog.tsx`; there is
/// no optimistic cache write here, because in this port the caller holds the
/// profile it just updated.
public struct ActivitySubscriptionsAPI: Sendable {
  /// The client every request goes through.
  public let client: NotificationClient
  /// Account scope for key identity.
  public let scope: String?

  public init(client: NotificationClient, scope: String? = nil) {
    self.client = client
    self.scope = scope
  }

  /// The infinite query key.
  public var key: QueryKey {
    NotificationQueryKey.activitySubscriptions(scope: scope)
  }

  /// The infinite query over subscribed accounts.
  ///
  /// Items are `ProfileView`s, each carrying the subscription in
  /// `viewer.activitySubscription`. Identity is the DID.
  public func query(store: QueryStore) -> InfiniteQuery<App.Bsky.ActorDefs_ProfileView> {
    InfiniteQuery(
      store: store,
      key: key,
      identity: { $0.did.rawValue },
      page: { [client] cursor in
        let output = try await client.listActivitySubscriptions(cursor: cursor, limit: nil)
        return QueryPage(
          items: output.subscriptions,
          cursor: output.cursor,
          requestCursor: cursor
        )
      }
    )
  }

  /// Writes a subscription for `subject`.
  ///
  /// A subscription with neither channel on is what the app sends to
  /// unsubscribe: the endpoint has no delete verb.
  @discardableResult
  public func put(
    subject: String,
    subscription: ActivitySubscription
  ) async throws -> ActivitySubscription {
    let output = try await client.putActivitySubscription(
      subject: subject,
      post: subscription.post,
      reply: subscription.reply
    )
    guard let written = output.activitySubscription else { return subscription }
    return ActivitySubscription(written)
  }

  /// Every subscribed DID held in the cache, for the "already subscribed"
  /// check.
  ///
  /// Loads the first page when the cache is empty, so a caller does not have to
  /// prime it first.
  public func subscribedDids(store: QueryStore) async -> Set<String> {
    let query = self.query(store: store)
    if await query.items().isEmpty {
      _ = try? await query.loadFirstPage()
    }
    let profiles = await query.items()
    return Set(profiles.map(\.did.rawValue))
  }
}
