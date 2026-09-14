import Foundation

/// One persisted page of an infinite query.
public struct PersistedPage: Codable, Sendable, Hashable {
  /// Cursor handed to the request that produced this page.
  public var requestCursor: String?
  /// Cursor returned by the page, or `nil` when the list was exhausted.
  public var cursor: String?
  /// Ids of the items on the page, in order.
  public var itemIds: [String]

  public init(requestCursor: String? = nil, cursor: String? = nil, itemIds: [String] = []) {
    self.requestCursor = requestCursor
    self.cursor = cursor
    self.itemIds = itemIds
  }
}

/// A single persisted cache entry, the Swift analogue of one dehydrated TanStack
/// query.
///
/// Only successful entries are persisted, which is the `shouldDehydrateQuery`
/// predicate from `src/lib/react-query.tsx`:
/// `isQueryPersisted(query.queryKey) && query.state.status === 'success'`.
public struct PersistedQuery: Codable, Sendable, Hashable {
  /// Stable identifier of the key, including scope and persisted version.
  public var keyIdentifier: String
  /// Key root.
  public var root: String
  /// Account scope the entry belongs to.
  public var scope: String?
  /// Persisted payload version the key was built with.
  public var persistedVersion: Int?
  /// Rendered argument payload, matched on restore.
  public var args: String
  /// Wall-clock microseconds at which the payload was produced.
  public var fetchedAt: Int64
  /// Staleness budget the entry was fetched under, in seconds.
  public var staleTime: TimeInterval
  /// JSON-encoded payload.
  public var payload: Data

  public init(
    keyIdentifier: String,
    root: String,
    scope: String? = nil,
    persistedVersion: Int? = nil,
    args: String,
    fetchedAt: Int64,
    staleTime: TimeInterval,
    payload: Data
  ) {
    self.keyIdentifier = keyIdentifier
    self.root = root
    self.scope = scope
    self.persistedVersion = persistedVersion
    self.args = args
    self.fetchedAt = fetchedAt
    self.staleTime = staleTime
    self.payload = payload
  }
}

/// A whole cache snapshot for one account.
///
/// The RN app writes one persister per account, keyed
/// `queryClient-<did|logged-out>`, and busts the whole snapshot when
/// `env.APP_VERSION` changes. `PersistedSnapshot.buster` is that version string;
/// a snapshot whose buster does not match the live buster is discarded wholesale
/// (the TanStack `buster` semantics), while a per-entry mismatch on
/// `persistedVersion` only drops that entry.
public struct PersistedSnapshot: Codable, Sendable, Hashable {
  /// Account the snapshot belongs to.
  public var scope: String
  /// Version buster the snapshot was written under.
  public var buster: String
  /// Wall-clock microseconds at which the snapshot was written.
  public var writtenAt: Int64
  /// Entries, one per persisted query.
  public var entries: [PersistedQuery]

  public init(
    scope: String,
    buster: String,
    writtenAt: Int64 = 0,
    entries: [PersistedQuery] = []
  ) {
    self.scope = scope
    self.buster = buster
    self.writtenAt = writtenAt
    self.entries = entries
  }

  /// The entry whose key parts match, after the buster and entry version have
  /// been checked.
  ///
  /// - Parameters:
  ///   - key: live key being restored.
  ///   - buster: live version buster.
  /// - Returns: the matching payload, or `nil` when the snapshot is stale, the
  ///   key is scoped to another account, or the entry's persisted version does
  ///   not match the live key.
  public func payload(for key: QueryKey, buster: String) -> Data? {
    guard self.buster == buster, scope == (key.scope ?? "logged-out") else { return nil }
    return entries.first {
      $0.root == key.keyRoot && $0.scope == key.scope
        && $0.persistedVersion == key.persistedVersion
        && $0.args == key.argsDebugDescription
    }?.payload
  }

  /// Number of entries in the snapshot.
  public var count: Int { entries.count }
}

/// Destination for persisted cache snapshots.
///
/// Implementations only need to move bytes: the store owns the encoding. That
/// keeps sinks trivially fakeable in tests and keeps platform storage details
/// out of this package.
///
/// `save` may be called from any thread; implementations must be thread-safe.
public protocol QueryPersistSink: Sendable {
  /// Writes the snapshot for `scope`, replacing whatever was there.
  func save(_ snapshot: PersistedSnapshot) async throws
  /// Reads the snapshot for `scope`, or `nil` when none was written.
  func load(scope: String) async throws -> PersistedSnapshot?
  /// Removes the snapshot for `scope`.
  func remove(scope: String) async throws
}
