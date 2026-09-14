import Foundation

import Lexicons
import Moderation
import SwiftAtproto

public struct NotificationPageFetcher: Sendable {
  /// The client every request goes through.
  public let client: NotificationClient
  /// Moderation options, or `nil` when the caller has none yet.
  public let moderationOpts: ModerationOpts?
  /// Whether to resolve subjects now. The unread poller skips this unless the
  /// page is about to be used in the feed, matching `fetchAdditionalData`.
  public let fetchAdditionalData: Bool
  /// Page size.
  public let limit: Int
  /// `reasons` query parameter. Empty means "all".
  public let reasons: [String]
  /// `priority` query parameter, for the priority-only view.
  public let priority: Bool?

  public init(
    client: NotificationClient,
    moderationOpts: ModerationOpts? = nil,
    fetchAdditionalData: Bool = true,
    limit: Int = NotificationFeeds.pageSize,
    reasons: [String] = [],
    priority: Bool? = nil
  ) {
    self.client = client
    self.moderationOpts = moderationOpts
    self.fetchAdditionalData = fetchAdditionalData
    self.limit = limit
    self.reasons = reasons
    self.priority = priority
  }

  /// The result of fetching a page: the page itself and the newest
  /// notification's `indexedAt`, which the unread poller uses to advance its
  /// sync watermark.
  public struct Result: Sendable {
    public var page: NotificationFeedPage
    public var indexedAt: String?
  }

  /// Fetches one page.
  public func page(cursor: String?) async throws -> NotificationFeedPage {
    try await result(cursor: cursor).page
  }

  /// Fetches one page along with its `indexedAt`.
  public func result(cursor: String?) async throws -> Result {
    let output = try await client.listNotifications(
      cursor: cursor,
      limit: limit,
      priority: priority,
      reasons: reasons.isEmpty ? nil : reasons
    )

    let indexedAt = output.notifications.first?.indexedAt.rawValue

    // Moderation filtering happens before grouping, so a filtered row never
    // swallows a grouped one.
    let kept = output.notifications.filter {
      !NotificationReasons.shouldFilter($0, moderationOpts: moderationOpts)
    }

    var grouped = NotificationReasons.group(kept)

    if fetchAdditionalData {
      let subjects = try await SubjectResolver(client: client).resolve(grouped)
      for index in grouped.indices {
        guard let subjectUri = grouped[index].subjectUri else { continue }
        let key = grouped[index].notification.reasonSubject?.rawValue
        if grouped[index].type == .starterpackJoined, let key {
          grouped[index].subject = subjects.starterPacks[key].map(ResolvedSubject.starterPack)
        } else {
          grouped[index].subject = subjects.posts[subjectUri].map(ResolvedSubject.post)
        }
      }
    }

    return Result(
      page: NotificationFeedPage(
        cursor: output.cursor,
        seenAt: Self.seenAt(from: output.seenAt),
        items: grouped,
        priority: output.priority ?? false
      ),
      indexedAt: indexedAt
    )
  }

  /// The page's read watermark, falling back to now when the server sends
  /// nothing parseable, exactly as `fetchPage` does.
  static func seenAt(from wire: FormatString<Date>?) -> Date {
    guard let wire, let parsed = NotificationReasons.parseATProtoDate(wire.rawValue) else {
      return Date()
    }
    return parsed
  }
}

/// Resolves the subjects a page's notifications point at, in bulk.
///
/// Ported from `fetchSubjects`: post subjects and starter-pack subjects are
/// collected separately and requested in chunks of twenty-five, in parallel.
public struct SubjectResolver: Sendable {
  /// Maximum URIs per request, matching the RN chunk size.
  public static let chunkSize = 25

  public let client: NotificationClient

  public init(client: NotificationClient) {
    self.client = client
  }

  /// The resolved subjects, keyed by URI.
  public struct Subjects: Sendable {
    public var posts: [String: App.Bsky.FeedDefs_PostView]
    public var starterPacks: [String: App.Bsky.GraphDefs_StarterPackViewBasic]
  }

  /// Resolves every subject referenced by `items`.
  ///
  /// A post URI is only requested when it names `app.bsky.feed.post`, and a
  /// starter pack only when the notification's `reasonSubject` names
  /// `app.bsky.graph.starterpack`, matching the RN collection pass.
  public func resolve(_ items: [FeedNotification]) async throws -> Subjects {
    var postUris: [String] = []
    var seenPosts = Set<String>()
    var packUris: [String] = []
    var seenPacks = Set<String>()

    for item in items {
      if let uri = item.subjectUri, uri.contains("app.bsky.feed.post"),
        seenPosts.insert(uri).inserted {
        postUris.append(uri)
      }
      if let reasonSubject = item.notification.reasonSubject?.rawValue,
        reasonSubject.contains("app.bsky.graph.starterpack"),
        seenPacks.insert(reasonSubject).inserted {
        packUris.append(reasonSubject)
      }
    }

    async let posts = fetchPosts(postUris)
    async let packs = fetchStarterPacks(packUris)
    return try await Subjects(posts: posts, starterPacks: packs)
  }

  private func fetchPosts(_ uris: [String]) async throws -> [String: App.Bsky.FeedDefs_PostView] {
    var map: [String: App.Bsky.FeedDefs_PostView] = [:]
    for chunk in uris.chunked(into: Self.chunkSize) {
      let output = try await client.getPosts(uris: chunk)
      for post in output.posts {
        // Only posts whose record really is a post are usable as subjects.
        if case .record(let value) = post.record, value is App.Bsky.FeedPost {
          map[post.uri.rawValue] = post
        }
      }
    }
    return map
  }

  private func fetchStarterPacks(
    _ uris: [String]
  ) async throws -> [String: App.Bsky.GraphDefs_StarterPackViewBasic] {
    var map: [String: App.Bsky.GraphDefs_StarterPackViewBasic] = [:]
    for chunk in uris.chunked(into: Self.chunkSize) {
      let output = try await client.getStarterPacks(uris: chunk)
      for pack in output.starterPacks {
        if case .record(let value) = pack.record, value is App.Bsky.GraphStarterpack {
          map[pack.uri.rawValue] = pack
        }
      }
    }
    return map
  }
}

extension Array {
  /// Splits into chunks of at most `size`, preserving order.
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return isEmpty ? [] : [self] }
    var chunks: [[Element]] = []
    var index = 0
    while index < count {
      chunks.append(Array(self[index..<Swift.min(index + size, count)]))
      index += size
    }
    return chunks
  }
}
