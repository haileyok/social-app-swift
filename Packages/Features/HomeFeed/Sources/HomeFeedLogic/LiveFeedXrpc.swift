import ATProtoClient
import Foundation
import Lexicons
import SwiftAtproto

/// The live ``FeedXrpc`` over a proxy-routed appview ``XrpcClient``.
///
/// The client is built by `ATProtoClient.SessionClients` and already carries the
/// `atproto-proxy: <did>#bsky_appview` header, the acceptor labelers and the
/// bearer token, so nothing here re-implements routing. Only the per-request
/// feed headers (`Accept-Language`, `X-Bsky-Topics`) are added, matching the RN
/// feed APIs.
///
/// Deviation: `XrpcClient` has no per-call header override, so the feed headers
/// are applied by producing a per-call copy of the client via
/// ``XrpcClient/withHeaders(_:)``, which merges into `extraHeaders`. This
/// preserves the client's auth/proxy/labeler headers.
public struct LiveFeedXrpc: FeedXrpc {
  /// The signed-in appview client.
  public let client: XrpcClient
  /// Authorization token, forwarded per request.
  public let authorization: String?

  public init(client: XrpcClient, authorization: String? = nil) {
    self.client = client
    self.authorization = authorization
  }

  /// A copy of the client with `headers` merged into its always-on headers.
  private func withHeaders(_ headers: FeedRequestHeaders) -> XrpcClient {
    var merged = client.extraHeaders
    for (key, value) in headers.asHeaders {
      merged[key] = value
    }
    return client.withHeaders(merged)
  }

  public func getTimeline(cursor: String?, limit: Int) async throws -> FeedTimelinePage {
    let output: App.Bsky.FeedGetTimeline_Output = try await client.get(
      App.Bsky.FeedGetTimeline.id,
      params: [("cursor", cursor), ("limit", String(limit))],
      authorization: authorization)
    return FeedTimelinePage(cursor: output.cursor, feed: output.feed)
  }

  public func getFeed(
    feed: String, cursor: String?, limit: Int, headers: FeedRequestHeaders
  ) async throws -> FeedPageOutput {
    let output: App.Bsky.FeedGetFeed_Output = try await withHeaders(headers).get(
      App.Bsky.FeedGetFeed.id,
      params: [
        ("feed", feed),
        ("cursor", cursor),
        ("limit", String(limit)),
      ],
      authorization: authorization)
    return FeedPageOutput(cursor: output.cursor, feed: output.feed)
  }

  public func getFeedSkeleton(
    feed: String, cursor: String?, limit: Int
  ) async throws -> FeedSkeletonOutput {
    let output: App.Bsky.FeedGetFeedSkeleton_Output = try await client.get(
      App.Bsky.FeedGetFeedSkeleton.id,
      params: [
        ("feed", feed),
        ("cursor", cursor),
        ("limit", String(limit)),
      ],
      authorization: authorization)
    return FeedSkeletonOutput(
      cursor: output.cursor, feed: output.feed, reqId: output.reqId)
  }

  public func getListFeed(
    list: String, cursor: String?, limit: Int
  ) async throws -> FeedPageOutput {
    let output: App.Bsky.FeedGetListFeed_Output = try await client.get(
      App.Bsky.FeedGetListFeed.id,
      params: [
        ("list", list),
        ("cursor", cursor),
        ("limit", String(limit)),
      ],
      authorization: authorization)
    return FeedPageOutput(cursor: output.cursor, feed: output.feed)
  }

  public func getList(list: String) async throws -> ListViewInfo {
    let output: App.Bsky.GraphGetList_Output = try await client.get(
      App.Bsky.GraphGetList.id,
      params: [
        ("list", list),
        ("limit", String(HomeFeedConstants.listHydrationLimit)),
      ],
      authorization: authorization)
    return ListViewInfo(
      uri: output.list.uri.rawValue,
      name: output.list.name,
      creatorHandle: output.list.creator.handle.rawValue,
      creatorDid: output.list.creator.did.rawValue)
  }

  public func getPosts(uris: [String]) async throws -> [App.Bsky.FeedDefs_PostView] {
    // `uris` is a repeated query parameter; the client's `url` builder emits
    // one `uris=` entry per tuple.
    let output: App.Bsky.FeedGetPosts_Output = try await client.get(
      App.Bsky.FeedGetPosts.id,
      params: uris.map { ("uris", $0) },
      authorization: authorization)
    return output.posts
  }

  public func getFeedGenerator(feed: String) async throws -> App.Bsky.FeedDefs_GeneratorView {
    let output: App.Bsky.FeedGetFeedGenerator_Output = try await client.get(
      App.Bsky.FeedGetFeedGenerator.id,
      params: [("feed", feed)],
      authorization: authorization)
    return output.view
  }

  public func getFeedGenerators(
    feeds: [String]
  ) async throws -> [App.Bsky.FeedDefs_GeneratorView] {
    let output: App.Bsky.FeedGetFeedGenerators_Output = try await client.get(
      App.Bsky.FeedGetFeedGenerators.id,
      params: feeds.map { ("feeds", $0) },
      authorization: authorization)
    return output.feeds
  }

  public func getActorFeeds(
    actor: String, cursor: String?, limit: Int
  ) async throws -> ActorFeedsPage {
    let output: App.Bsky.FeedGetActorFeeds_Output = try await client.get(
      App.Bsky.FeedGetActorFeeds.id,
      params: [
        ("actor", actor),
        ("cursor", cursor),
        ("limit", String(limit)),
      ],
      authorization: authorization)
    return ActorFeedsPage(cursor: output.cursor, feeds: output.feeds)
  }

  public func getConfig() async throws -> App.Bsky.UnspeccedGetConfig_Output {
    try await client.get(
      App.Bsky.UnspeccedGetConfig.id, params: [], authorization: authorization)
  }
}
