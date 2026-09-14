import Foundation
import Lexicons
import SwiftAtproto

@testable import VideoFeedLogic

/// A scripted ``VideoFeedXrpc`` that records every call and returns queued pages.
///
/// Package-local, matching the `HomeFeedLogicTests` convention: the package does
/// not depend on `TestSupport`.
final class RecordingVideoFeedXrpc: VideoFeedXrpc, @unchecked Sendable {
  /// One recorded call, with the exact parameters it carried.
  enum Call: Sendable, Equatable {
    case feed(
      feed: String, cursor: String?, limit: Int, headers: VideoFeedRequestHeaders)
    case authorFeed(actor: String, filter: String, cursor: String?, limit: Int)
    case feedGenerator(feed: String)
  }

  private let lock = NSLock()
  private var _calls: [Call] = []

  /// Queued generator pages, consumed in order. The last repeats.
  private var feedPages: [VideoFeedPageOutput] = []
  /// Queued author pages, consumed in order. The last repeats.
  private var authorPages: [VideoFeedPageOutput] = []
  /// Generator views keyed by URI.
  private var generators: [String: App.Bsky.FeedDefs_GeneratorView] = [:]
  /// Accessors configured to throw.
  private var throwOn: Set<String> = []
  /// The error a failing accessor throws.
  var thrownError: any Error = VideoFeedTestError.boom

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  var calls: [Call] { withLock { _calls } }

  func fail(_ accessor: String) {
    withLock { throwOn.insert(accessor) }
  }

  func shouldThrow(_ accessor: String) -> Bool {
    withLock { throwOn.contains(accessor) }
  }

  // MARK: - Configuration

  func setFeedPages(_ pages: [VideoFeedPageOutput]) { withLock { feedPages = pages } }
  func setAuthorPages(_ pages: [VideoFeedPageOutput]) { withLock { authorPages = pages } }
  func setGenerators(_ views: [App.Bsky.FeedDefs_GeneratorView]) {
    withLock {
      generators = Dictionary(
        views.map { ($0.uri.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
    }
  }

  // MARK: - VideoFeedXrpc

  func getFeed(
    feed: String, cursor: String?, limit: Int, headers: VideoFeedRequestHeaders
  ) async throws -> VideoFeedPageOutput {
    withLock { _calls.append(.feed(feed: feed, cursor: cursor, limit: limit, headers: headers)) }
    if shouldThrow("feed") { throw thrownError }
    return withLock { feedPages.isEmpty ? VideoFeedPageOutput() : feedPages.removeFirst() }
  }

  func getAuthorFeed(
    actor: String, filter: String, cursor: String?, limit: Int
  ) async throws -> VideoFeedPageOutput {
    withLock {
      _calls.append(.authorFeed(actor: actor, filter: filter, cursor: cursor, limit: limit))
    }
    if shouldThrow("authorFeed") { throw thrownError }
    return withLock { authorPages.isEmpty ? VideoFeedPageOutput() : authorPages.removeFirst() }
  }

  func getFeedGenerator(feed: String) async throws -> App.Bsky.FeedDefs_GeneratorView {
    withLock { _calls.append(.feedGenerator(feed: feed)) }
    if shouldThrow("feedGenerator") { throw thrownError }
    guard let view = withLock({ generators[feed] }) else {
      throw XrpcTestError.notFound
    }
    return view
  }
}

/// A page fetcher that records cursors and replays a scripted page list.
final class ScriptedVideoPageFetcher: VideoPageFetcher, @unchecked Sendable {
  private let lock = NSLock()
  private var pages: [VideoFeedPageOutput]
  private var _cursors: [String?] = []
  /// Every `limit` requested, so a suite can assert the page size.
  private var _limits: [Int] = []

  init(pages: [VideoFeedPageOutput]) {
    self.pages = pages
  }

  var cursors: [String?] { lock.withLock { _cursors } }
  var limits: [Int] { lock.withLock { _limits } }

  func fetch(cursor: String?, limit: Int) async throws -> VideoFeedPageOutput {
    lock.withLock {
      _cursors.append(cursor)
      _limits.append(limit)
    }
    return lock.withLock {
      pages.isEmpty ? VideoFeedPageOutput() : pages.removeFirst()
    }
  }
}

/// Errors used by the fakes.
enum VideoFeedTestError: Error, Equatable {
  case boom
}

/// Errors the fake XRPC raises directly.
enum XrpcTestError: Error, Equatable {
  case notFound
}

extension NSLock {
  /// A synchronous critical section, because `NSLock.lock()` is `noasync`.
  func withLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
