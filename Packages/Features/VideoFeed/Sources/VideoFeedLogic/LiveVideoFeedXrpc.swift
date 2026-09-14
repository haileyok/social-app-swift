import ATProtoClient
import Foundation
import Lexicons
import SwiftAtproto

/// The live ``VideoFeedXrpc`` over a proxy-routed appview ``XrpcClient``.
///
/// The client is built by `ATProtoClient.SessionClients` and already carries the
/// `atproto-proxy` header, the acceptor labelers and the bearer token, so nothing
/// here re-implements routing; only the per-request feed headers are added.
///
/// Deviation: `XrpcClient` has no per-call header override, so the feed headers
/// are applied by producing a per-call copy via ``XrpcClient/withHeaders(_:)``,
/// which merges into `extraHeaders` and preserves auth/proxy/labeler headers.
public struct LiveVideoFeedXrpc: VideoFeedXrpc {
  /// The signed-in appview client.
  public let client: XrpcClient
  /// Authorization token, forwarded per request.
  public let authorization: String?

  public init(client: XrpcClient, authorization: String? = nil) {
    self.client = client
    self.authorization = authorization
  }

  /// A copy of the client with `headers` merged into its always-on headers.
  private func withHeaders(_ headers: VideoFeedRequestHeaders) -> XrpcClient {
    var merged = client.extraHeaders
    for (key, value) in headers.asHeaders {
      merged[key] = value
    }
    return client.withHeaders(merged)
  }

  public func getFeed(
    feed: String, cursor: String?, limit: Int, headers: VideoFeedRequestHeaders
  ) async throws -> VideoFeedPageOutput {
    let output: App.Bsky.FeedGetFeed_Output = try await withHeaders(headers).get(
      App.Bsky.FeedGetFeed.id,
      params: [
        ("feed", feed),
        ("cursor", cursor),
        ("limit", String(limit)),
      ],
      authorization: authorization)
    return VideoFeedPageOutput(cursor: output.cursor, feed: output.feed)
  }

  public func getAuthorFeed(
    actor: String, filter: String, cursor: String?, limit: Int
  ) async throws -> VideoFeedPageOutput {
    let output: App.Bsky.FeedGetAuthorFeed_Output = try await client.get(
      App.Bsky.FeedGetAuthorFeed.id,
      params: [
        ("actor", actor),
        ("filter", filter),
        ("cursor", cursor),
        ("limit", String(limit)),
      ],
      authorization: authorization)
    return VideoFeedPageOutput(cursor: output.cursor, feed: output.feed)
  }

  public func getFeedGenerator(feed: String) async throws -> App.Bsky.FeedDefs_GeneratorView {
    let output: App.Bsky.FeedGetFeedGenerator_Output = try await client.get(
      App.Bsky.FeedGetFeedGenerator.id,
      params: [("feed", feed)],
      authorization: authorization)
    return output.view
  }
}
