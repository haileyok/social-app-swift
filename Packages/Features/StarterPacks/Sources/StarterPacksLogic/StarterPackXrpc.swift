import Foundation
import Lexicons

/// The XRPC surface the starter-pack feature needs, behind a protocol so tests
/// can record and script exact calls.
///
/// Ported from `src/state/queries/starter-packs.ts`,
/// `src/state/queries/actor-starter-packs.ts`,
/// `src/state/queries/starter-pack-search.ts` and
/// `src/state/queries/list-members.ts`. The live implementation
/// (``LiveStarterPackXrpc``) runs over `ATProtoClient.XrpcClient`, so proxy
/// routing, labelers and auth headers are emitted by the client exactly as they
/// are for every other feature.
///
/// Reads go to the appview; repo writes go to the PDS. The two clients are
/// separate properties because RN uses `useAppviewClient()` for the reads and
/// `usePdsClient()` for the writes.
public protocol StarterPackXrpc: Sendable {
  /// `app.bsky.graph.getStarterPack`. Port of `useStarterPackQuery`.
  func getStarterPack(uri: String) async throws -> App.Bsky.GraphDefs_StarterPackView

  /// `app.bsky.graph.getStarterPacks` (batch). Port of the notification
  /// hydration read in `notifications/util.ts`.
  func getStarterPacks(uris: [String]) async throws -> [App.Bsky.GraphDefs_StarterPackViewBasic]

  /// `app.bsky.graph.getActorStarterPacks`. Port of `useActorStarterPacksQuery`.
  func getActorStarterPacks(
    actor: String, cursor: String?, limit: Int
  ) async throws -> StarterPackBasicPage

  /// `app.bsky.graph.getStarterPacksWithMembership`. Port of
  /// `useActorStarterPacksWithMembershipsQuery`.
  func getStarterPacksWithMembership(
    actor: String, cursor: String?, limit: Int
  ) async throws -> StarterPackWithMembershipPage

  /// `app.bsky.graph.searchStarterPacksV2`. Port of `useStarterPackSearch`.
  func searchStarterPacks(
    query: String, cursor: String?, limit: Int
  ) async throws -> StarterPackViewPage

  /// `app.bsky.graph.getList`, one page. Port of `useListMembersQuery`.
  func getList(list: String, cursor: String?, limit: Int) async throws -> StarterPackListMembersPage

  // MARK: - Repo writes

  /// `com.atproto.repo.applyWrites`. The batch write the list items and the
  /// edit diff go through.
  func applyWrites(repo: String, writes: [StarterPackWrite]) async throws

  /// `com.atproto.repo.createRecord`.
  func createRecord(
    repo: String, collection: String, rkey: String?, record: StarterPackJSON
  ) async throws -> StarterPackRecordRef

  /// `com.atproto.repo.putRecord`.
  func putRecord(
    repo: String, collection: String, rkey: String, record: StarterPackJSON
  ) async throws -> StarterPackRecordRef

  /// `com.atproto.repo.deleteRecord`.
  func deleteRecord(repo: String, collection: String, rkey: String) async throws
}

/// A page of basic pack views.
public struct StarterPackBasicPage: Sendable {
  /// The next cursor, when there is one.
  public var cursor: String?
  /// The packs on this page.
  public var starterPacks: [App.Bsky.GraphDefs_StarterPackViewBasic]

  /// Creates a page.
  public init(
    cursor: String? = nil, starterPacks: [App.Bsky.GraphDefs_StarterPackViewBasic] = []
  ) {
    self.cursor = cursor
    self.starterPacks = starterPacks
  }
}

/// A page of packs with the viewer's membership attached.
public struct StarterPackWithMembershipPage: Sendable {
  /// The next cursor, when there is one.
  public var cursor: String?
  /// The packs on this page.
  public var packs: [App.Bsky.GraphGetStarterPacksWithMembership_StarterPackWithMembership]

  /// Creates a page.
  public init(
    cursor: String? = nil,
    packs: [App.Bsky.GraphGetStarterPacksWithMembership_StarterPackWithMembership] = []
  ) {
    self.cursor = cursor
    self.packs = packs
  }
}

/// A page of full pack views (search results).
public struct StarterPackViewPage: Sendable {
  /// The next cursor, when there is one.
  public var cursor: String?
  /// The packs on this page.
  public var starterPacks: [App.Bsky.GraphDefs_StarterPackView]

  /// Creates a page.
  public init(cursor: String? = nil, starterPacks: [App.Bsky.GraphDefs_StarterPackView] = []) {
    self.cursor = cursor
    self.starterPacks = starterPacks
  }
}

/// A page of a reference list's members.
public struct StarterPackListMembersPage: Sendable {
  /// The next cursor, when there is one.
  public var cursor: String?
  /// The list-item views on this page.
  public var items: [App.Bsky.GraphDefs_ListItemView]

  /// Creates a page.
  public init(cursor: String? = nil, items: [App.Bsky.GraphDefs_ListItemView] = []) {
    self.cursor = cursor
    self.items = items
  }
}

/// One `applyWrites` write, held as the exact JSON object RN sends.
///
/// The wire shape is a union tagged by `$type`
/// (`com.atproto.repo.applyWrites#create|update|delete`); keeping it as a plain
/// JSON object is what lets the payload tables in the tests compare the bytes
/// that go out, rather than a round-tripped approximation.
public typealias StarterPackWrite = StarterPackJSON

/// A `{uri, cid}` reference returned by a repo write.
public struct StarterPackRecordRef: Sendable, Equatable {
  /// The record's AT URI.
  public let uri: String
  /// The record's CID.
  public let cid: String

  /// Creates a record reference.
  public init(uri: String, cid: String = "") {
    self.uri = uri
    self.cid = cid
  }
}
