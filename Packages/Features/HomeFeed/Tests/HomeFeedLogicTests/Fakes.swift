import ATProtoClient
import Domain
import Foundation
import Lexicons
import SwiftAtproto

@testable import HomeFeedLogic

/// A scripted ``FeedXrpc`` that records every call and returns queued pages.
///
/// The package deliberately does not reach into `TestSupport` (a placeholder),
/// so this is a package-local fake, following the `ScriptedTransport` pattern in
/// the Login package.
final class RecordingFeedXrpc: FeedXrpc, @unchecked Sendable {
  /// One recorded call, with the exact parameters it carried.
  enum Call: Sendable, Equatable {
    case timeline(cursor: String?, limit: Int)
    case feed(feed: String, cursor: String?, limit: Int, headers: FeedRequestHeaders)
    case feedSkeleton(feed: String, cursor: String?, limit: Int)
    case posts(uris: [String])
    case feedGenerator(feed: String)
    case feedGenerators(feeds: [String])
    case actorFeeds(actor: String, cursor: String?, limit: Int)
    case listFeed(list: String, cursor: String?, limit: Int)
    case list(list: String)
    case config
  }

  private let lock = NSLock()
  private var _calls: [Call] = []

  /// Queued timeline pages, consumed in order. The last one repeats.
  private var timelinePages: [FeedTimelinePage] = []
  /// Queued custom-feed pages, consumed in order.
  private var feedPages: [FeedPageOutput] = []
  /// Queued skeleton pages, consumed in order.
  private var skeletonPages: [FeedSkeletonOutput] = []
  /// Post views returned by `getPosts`, keyed by URI.
  private var postsByURI: [String: App.Bsky.FeedDefs_PostView] = [:]
  /// Generator views returned by the batch read.
  private var generatorViews: [App.Bsky.FeedDefs_GeneratorView] = []
  /// List views returned by `getList`, keyed by URI.
  private var listViews: [String: ListViewInfo] = [:]
  /// When set, the call at this index (per accessor) throws.
  private var throwOn: Set<String> = []
  /// The error thrown by a failing accessor.
  var thrownError: any Error = XrpcError(
    rawCode: nil, message: "boom", status: 500)

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var calls: [Call] { withLock { _calls } }

  func record(_ call: Call) {
    withLock { _calls.append(call) }
  }

  func fail(_ accessor: String) {
    withLock { throwOn.insert(accessor) }
  }

  func shouldThrow(_ accessor: String) -> Bool {
    withLock { throwOn.contains(accessor) }
  }

  // MARK: - Configuration

  func setTimelinePages(_ pages: [FeedTimelinePage]) { withLock { timelinePages = pages } }
  func setFeedPages(_ pages: [FeedPageOutput]) { withLock { feedPages = pages } }
  func setSkeletonPages(_ pages: [FeedSkeletonOutput]) { withLock { skeletonPages = pages } }
  func setPosts(_ posts: [App.Bsky.FeedDefs_PostView]) {
    withLock { postsByURI = Dictionary(posts.map { ($0.uri.rawValue, $0) }, uniquingKeysWith: { a, _ in a }) }
  }
  func setGenerators(_ views: [App.Bsky.FeedDefs_GeneratorView]) { withLock { generatorViews = views } }
  func setLists(_ views: [ListViewInfo]) {
    withLock { listViews = Dictionary(views.map { ($0.uri, $0) }, uniquingKeysWith: { a, _ in a }) }
  }

  // MARK: - FeedXrpc

  func getTimeline(cursor: String?, limit: Int) async throws -> FeedTimelinePage {
    record(.timeline(cursor: cursor, limit: limit))
    if shouldThrow("timeline") { throw thrownError }
    return withLock { timelinePages.isEmpty ? FeedTimelinePage() : timelinePages.removeFirst() }
  }

  func getFeed(
    feed: String, cursor: String?, limit: Int, headers: FeedRequestHeaders
  ) async throws -> FeedPageOutput {
    record(.feed(feed: feed, cursor: cursor, limit: limit, headers: headers))
    if shouldThrow("feed") { throw thrownError }
    return withLock { feedPages.isEmpty ? FeedPageOutput() : feedPages.removeFirst() }
  }

  func getFeedSkeleton(
    feed: String, cursor: String?, limit: Int
  ) async throws -> FeedSkeletonOutput {
    record(.feedSkeleton(feed: feed, cursor: cursor, limit: limit))
    if shouldThrow("skeleton") { throw thrownError }
    return withLock { skeletonPages.isEmpty ? FeedSkeletonOutput() : skeletonPages.removeFirst() }
  }

  func getListFeed(list: String, cursor: String?, limit: Int) async throws -> FeedPageOutput {
    record(.listFeed(list: list, cursor: cursor, limit: limit))
    if shouldThrow("listFeed") { throw thrownError }
    return withLock { feedPages.isEmpty ? FeedPageOutput() : feedPages.removeFirst() }
  }

  func getList(list: String) async throws -> ListViewInfo {
    record(.list(list: list))
    if shouldThrow("list") { throw thrownError }
    guard let view = withLock({ listViews[list] }) else {
      throw XrpcError(rawCode: "NotFound", message: "no list", status: 404)
    }
    return view
  }

  func getPosts(uris: [String]) async throws -> [App.Bsky.FeedDefs_PostView] {
    record(.posts(uris: uris))
    if shouldThrow("posts") { throw thrownError }
    return withLock { uris.compactMap { postsByURI[$0] } }
  }

  func getFeedGenerator(feed: String) async throws -> App.Bsky.FeedDefs_GeneratorView {
    record(.feedGenerator(feed: feed))
    if shouldThrow("feedGenerator") { throw thrownError }
    guard let view = withLock({ generatorViews.first { $0.uri.rawValue == feed } }) else {
      throw XrpcError(rawCode: "NotFound", message: "no generator", status: 404)
    }
    return view
  }

  func getFeedGenerators(feeds: [String]) async throws -> [App.Bsky.FeedDefs_GeneratorView] {
    record(.feedGenerators(feeds: feeds))
    if shouldThrow("feedGenerators") { throw thrownError }
    return withLock { generatorViews.filter { feeds.contains($0.uri.rawValue) } }
  }

  func getActorFeeds(actor: String, cursor: String?, limit: Int) async throws -> ActorFeedsPage {
    record(.actorFeeds(actor: actor, cursor: cursor, limit: limit))
    if shouldThrow("actorFeeds") { throw thrownError }
    return ActorFeedsPage(feeds: withLock { generatorViews })
  }

  func getConfig() async throws -> App.Bsky.UnspeccedGetConfig_Output {
    record(.config)
    if shouldThrow("config") { throw thrownError }
    return App.Bsky.UnspeccedGetConfig_Output()
  }
}

/// A transport that records requests and replays JSON bodies, used to assert
/// that the live client emits proxy routing and feed headers byte-for-byte.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
  struct Received: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data?
  }

  private let lock = NSLock()
  private var _received: [Received] = []
  private var responseBody: Data

  init(responseBody: Data = Data("{}".utf8)) {
    self.responseBody = responseBody
  }

  var received: [Received] { lock.withLock { _received } }

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    lock.withLock {
      _received.append(Received(method: method, url: url, headers: headers, body: body))
    }
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"],
      body: responseBody)
  }
}

extension NSLock {
  /// A synchronous critical section, because `NSLock.lock()` is `noasync`.
  func withLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
