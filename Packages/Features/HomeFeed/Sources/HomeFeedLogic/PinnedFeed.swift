import Foundation
import Lexicons
import Preferences
import QueryStore
import SwiftAtproto

/// A saved-feed entry interpreted from the v2 saved-feeds preference.
///
/// Port of the SDK's `SavedFeed` reading in `src/state/queries/feed.ts`. The
/// stored `value` is `following` for the timeline and an `at://` URI otherwise.
public struct SavedFeedEntry: Sendable, Hashable {
  /// The stable id the preference stores.
  public let id: String
  /// `timeline`, `feed` or `list`.
  public let type: SavedFeedType
  /// The stored value: `following`, or the feed/list URI.
  public let value: String
  /// Whether the user pinned this feed to the top bar.
  public let pinned: Bool

  public init(id: String, type: SavedFeedType, value: String, pinned: Bool) {
    self.id = id
    self.type = type
    self.value = value
    self.pinned = pinned
  }

  /// Reads an entry from the stored preference object.
  ///
  /// Tolerates an unknown `type` by inferring it from the URI with
  /// ``SavedFeeds/type(forUri:)``, which is what the RN model does when v1
  /// entries are still in play. Returns `nil` when neither yields a type.
  public init?(prefObject: PrefObject) {
    guard let id = prefObject["id"]?.stringValue,
      let value = prefObject["value"]?.stringValue
    else { return nil }

    let rawType = prefObject["type"]?.stringValue
    guard let type = rawType.flatMap(SavedFeedType.init(rawValue:)) ?? SavedFeedEntry.inferType(for: value)
    else { return nil }

    self.init(
      id: id,
      type: type,
      value: value,
      pinned: prefObject["pinned"]?.boolValue ?? false)
  }

  /// Infers a saved-feed type from its value, mapping anything that is not a
  /// generator or list URI to the timeline.
  static func inferType(for value: String) -> SavedFeedType? {
    guard let inferred = SavedFeeds.type(forUri: value) else { return nil }
    return SavedFeedType(rawValue: inferred)
  }

  /// The feed descriptor this saved feed selects.
  public var descriptor: FeedDescriptor {
    switch type {
    case .timeline: return .following
    case .feed: return .feedgen(uri: value)
    case .list: return .list(uri: value)
    }
  }
}

/// The three saved-feed kinds. Port of the v2 `type` field.
public enum SavedFeedType: String, Sendable, Hashable {
  case timeline
  case feed
  case list
}

/// One entry of the pinned-feed list: the saved config plus its resolved
/// display info.
///
/// Port of the `SavedFeedSourceInfo` items `usePinnedFeedsInfos` returns, with
/// the UI-rich parts (RichText description, route) reduced to the fields the
/// Logic layer needs to render a tab and pick a feed.
public struct PinnedFeed: Sendable {
  /// The stored config, kept so a view can re-order or unpin.
  public let config: SavedFeedEntry
  /// The resolved feed generator, for generator feeds.
  public let generatorView: App.Bsky.FeedDefs_GeneratorView?
  /// The display name. RN falls back to "Feed by <handle>", then "Following".
  public let displayName: String
  /// The feed's avatar, when the generator supplied one.
  public let avatar: String?
  /// The creator's handle, when known.
  public let creatorHandle: String?
  /// The creator's DID, when known.
  public let creatorDid: String?
  /// The descriptor to query this feed with.
  public var descriptor: FeedDescriptor { config.descriptor }

  public init(
    config: SavedFeedEntry,
    generatorView: App.Bsky.FeedDefs_GeneratorView? = nil,
    displayName: String,
    avatar: String? = nil,
    creatorHandle: String? = nil,
    creatorDid: String? = nil
  ) {
    self.config = config
    self.generatorView = generatorView
    self.displayName = displayName
    self.avatar = avatar
    self.creatorHandle = creatorHandle
    self.creatorDid = creatorDid
  }

  /// The timeline stub RN builds when the saved entry is the pinned timeline.
  ///
  /// Port of the `pinnedItem.type === 'timeline'` branch in
  /// `usePinnedFeedsInfos`, whose display name is "Following" and whose
  /// descriptor is `following`.
  public static func timeline(_ config: SavedFeedEntry) -> PinnedFeed {
    PinnedFeed(config: config, displayName: "Following")
  }

  /// Builds a feed's entry from a resolved generator view, using RN's
  /// display-name fallback (`Feed by <handle>` when the generator has no name).
  public static func generator(
    _ view: App.Bsky.FeedDefs_GeneratorView, config: SavedFeedEntry
  ) -> PinnedFeed {
    let name = view.displayName.isEmpty
      ? "Feed by @\(view.creator.handle.rawValue)" : view.displayName
    return PinnedFeed(
      config: config,
      generatorView: view,
      displayName: name,
      avatar: view.avatar?.rawValue,
      creatorHandle: view.creator.handle.rawValue,
      creatorDid: view.creator.did.rawValue)
  }
}

/// The resolved feed-info payload for a set of saved feeds.
///
/// This is the persisted shape under the `feed-info` key root: RN sets
/// `persistedVersion: 1` and `gcTime: GCTIME.INFINITY` on exactly these queries,
/// which is why this, and not the feed pages, is ``QueryPayload``.
public struct ResolvedFeedInfo: Sendable, Codable {
  /// The number of feeds the resolution produced. RN's placeholder uses the
  /// saved-item count before the real count is known.
  public var count: Int
  /// The resolved entries, in saved order.
  public var feeds: [ResolvedPinnedFeed]

  public init(count: Int = 0, feeds: [ResolvedPinnedFeed] = []) {
    self.count = count
    self.feeds = feeds
  }

  public init(from pinned: [PinnedFeed]) {
    self.count = pinned.count
    self.feeds = pinned.map(ResolvedPinnedFeed.init)
  }
}

extension ResolvedFeedInfo: QueryPayload {}

/// A `Codable` mirror of ``PinnedFeed`` for persistence.
///
/// `PinnedFeed` holds a generated `GeneratorView`, which is `Codable` but bulky;
/// the persisted entry keeps only the fields a restored top bar needs, matching
/// RN's `shouldDehydrateQuery` posture of persisting feed metadata.
public struct ResolvedPinnedFeed: Sendable, Codable, Hashable {
  public var id: String
  public var type: String
  public var value: String
  public var pinned: Bool
  public var displayName: String
  public var avatar: String?
  public var creatorHandle: String?
  public var creatorDid: String?

  public init(_ pinned: PinnedFeed) {
    self.id = pinned.config.id
    self.type = pinned.config.type.rawValue
    self.value = pinned.config.value
    self.pinned = pinned.config.pinned
    self.displayName = pinned.displayName
    self.avatar = pinned.avatar
    self.creatorHandle = pinned.creatorHandle
    self.creatorDid = pinned.creatorDid
  }

  /// Rebuilds the pinned entry without the (unavailable) generator view.
  public var pinnedFeed: PinnedFeed {
    let type = SavedFeedType(rawValue: type) ?? .feed
    return PinnedFeed(
      config: SavedFeedEntry(id: id, type: type, value: value, pinned: pinned),
      displayName: displayName,
      avatar: avatar,
      creatorHandle: creatorHandle,
      creatorDid: creatorDid)
  }
}
