import Foundation
import Lexicons
import QueryStore
import SwiftAtproto

/// The video feed generator's display metadata, reduced to data.
///
/// Port of the `useFeedInfo(feedUri)` read in `src/state/queries/feed.ts` as the
/// immersive screen consumes it. The header shows the feed's name and avatar, and
/// the feedback pipeline needs the URI and creator.
public struct VideoFeedInfo: Sendable, Hashable {
  /// The generator URI.
  public let uri: String
  /// The generator's display name. RN falls back to `Feed by <handle>`.
  public let displayName: String
  /// The generator's avatar, when it has one.
  public let avatar: String?
  /// The creator's handle.
  public let creatorHandle: String
  /// The creator's DID.
  public let creatorDid: String
  /// The generator's `acceptsInteractions` flag, when the appview set one.
  public let acceptsInteractions: Bool?
  /// The generator's content mode (`app.bsky.feed.defs#generatorView`), when set.
  /// The appview uses `video` for video-only feeds.
  public let contentMode: String?
  /// True when the appview reported this generator as available.
  ///
  /// `app.bsky.feed.defs#generatorView` has no `isOnline` in the generated types
  /// (the field lives on the older `describeFeedGenerator` response), so this is
  /// derived from the view being present at all.
  public let isAvailable: Bool

  public init(
    uri: String,
    displayName: String,
    avatar: String? = nil,
    creatorHandle: String,
    creatorDid: String,
    acceptsInteractions: Bool? = nil,
    contentMode: String? = nil,
    isAvailable: Bool = true
  ) {
    self.uri = uri
    self.displayName = displayName
    self.avatar = avatar
    self.creatorHandle = creatorHandle
    self.creatorDid = creatorDid
    self.acceptsInteractions = acceptsInteractions
    self.contentMode = contentMode
    self.isAvailable = isAvailable
  }

  /// Builds the model from a decoded generator view, applying RN's display-name
  /// fallback.
  public init(_ view: App.Bsky.FeedDefs_GeneratorView) {
    let handle = view.creator.handle.rawValue
    self.init(
      uri: view.uri.rawValue,
      displayName: view.displayName.isEmpty ? "Feed by @\(handle)" : view.displayName,
      avatar: view.avatar?.rawValue,
      creatorHandle: handle,
      creatorDid: view.creator.did.rawValue,
      acceptsInteractions: view.acceptsInteractions,
      contentMode: view.contentMode?.rawValue)
  }

  /// True when the feed is one of the Bluesky-owned video feeds, which the app
  /// treats specially for interstitials.
  public var isVideoFeedGenerator: Bool {
    VideoFeedConstants.videoFeedURIs.contains(uri)
  }
}

/// Reads a video feed generator's metadata through a ``QueryStore``.
///
/// Mirrors the Home feed's generator-detail query: the same `feedInfo` key root
/// RN uses, so the Home screen's cached generator view and this share an entry.
public struct VideoFeedInfoQuery: Sendable {
  /// The store this read lives in.
  public let store: QueryStore
  /// The XRPC surface.
  public let xrpc: any VideoFeedXrpc
  /// The generator URI.
  public let uri: String

  public init(store: QueryStore, xrpc: any VideoFeedXrpc, uri: String) {
    self.store = store
    self.xrpc = xrpc
    self.uri = uri
  }

  /// This read's key.
  public var key: QueryKey { VideoFeedKeys.feedInfo(uri: uri) }

  /// Fetches the generator's info, returning the model.
  ///
  /// - Parameter force: refetch even when a fresh entry is held.
  @discardableResult
  public func load(force: Bool = false) async throws -> VideoFeedInfo {
    let xrpc = self.xrpc
    let uri = self.uri
    let entry: QueryEntry<VideoFeedInfo> = try await store.fetchEntry(
      key,
      force: force
    ) {
      VideoFeedInfo(try await xrpc.getFeedGenerator(feed: uri))
    }
    if let error = entry.error { throw error }
    guard let info = entry.data else {
      throw VideoFeedError.missingGenerator(uri: uri)
    }
    return info
  }
}

/// Errors the video feed raises directly.
public enum VideoFeedError: Error, Equatable, Sendable {
  /// The generator read succeeded but returned nothing usable.
  case missingGenerator(uri: String)
  /// A descriptor string could not be parsed into a source.
  case invalidDescriptor(String)

  /// A short, user-facing description.
  public var errorDescription: String? {
    switch self {
    case .missingGenerator(let uri): return "Could not load the feed (\(uri))."
    case .invalidDescriptor(let descriptor): return "Unrecognised feed (\(descriptor))."
    }
  }
}
