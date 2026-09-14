import Foundation
import QueryStore

/// Query-key builders for the starter-pack surfaces.
///
/// Ports the RN key roots so a persisted snapshot and a live key agree:
/// `starter-pack` (`RQKEY` in `src/state/queries/starter-packs.ts`),
/// `actor-starter-packs` and `actor-starter-packs-with-membership`
/// (`actor-starter-packs.ts`), `starter-pack-search`
/// (`starter-pack-search.ts`), and `list-members` / `list-members-all`
/// (`list-members.ts`).
public enum StarterPackKeys {
  /// Root for a single pack view. RN: `RQKEY_ROOT = 'starter-pack'`.
  public static let packRoot = "starter-pack"
  /// Root for a user's own packs. RN: `actor-starter-packs`.
  public static let actorStarterPacksRoot = "actor-starter-packs"
  /// Root for a user's packs with the viewer's membership. RN:
  /// `actor-starter-packs-with-membership`.
  public static let actorStarterPacksWithMembershipRoot = "actor-starter-packs-with-membership"
  /// Root for pack search. RN: `starter-pack-search`.
  public static let searchRoot = "starter-pack-search"
  /// Root for a paged list-members read. RN: `list-members`.
  public static let listMembersRoot = "list-members"
  /// Root for the exhaustive list-members read. RN: `list-members-all`.
  public static let listMembersAllRoot = "list-members-all"

  /// Args for a single pack view.
  ///
  /// RN's `RQKEY` is `[root, parsed?.name, parsed?.rkey]` when it is handed a
  /// URI and `[root, did, rkey]` when it is handed a DID and rkey. Both forms
  /// resolve to the same `(name, rkey)` pair once a URI is parsed, so one args
  /// type covers them: `name` is the URI authority (a DID or a handle), which is
  /// what RN keys on.
  public struct PackArgs: QueryArgs {
    /// The URI authority: a DID for an `at://` input, a handle for an http one.
    public let name: String
    /// The record key.
    public let rkey: String

    /// Creates the args.
    public init(name: String, rkey: String) {
      self.name = name
      self.rkey = rkey
    }

    /// Args for a DID plus rkey pair.
    public init(did: String, rkey: String) {
      self.init(name: did, rkey: rkey)
    }
  }

  /// The key for one pack view, ported from `RQKEY(uri ? {uri} : {did, rkey})`.
  ///
  /// A URI input that parses to a pack contributes its `(name, rkey)`; an
  /// unparseable URI falls back to the raw string so two different bad inputs
  /// never share an entry.
  public static func pack(name: String, rkey: String, scope: String? = nil) -> QueryKey {
    QueryKey(
      packRoot, PackArgs(name: name, rkey: rkey), options: QueryOptions(scope: scope))
  }

  /// The key for one pack view from an `at://` or `https://` URI.
  public static func pack(uri: String, scope: String? = nil) -> QueryKey {
    if let parsed = StarterPackURI.parse(uri) {
      return pack(name: parsed.name, rkey: parsed.rkey, scope: scope)
    }
    return QueryKey(
      packRoot, PackArgs(name: uri, rkey: ""), options: QueryOptions(scope: scope))
  }

  /// Args for an actor-scoped pack list.
  public struct ActorArgs: QueryArgs {
    /// The actor's DID, or `""` when the read is not yet enabled.
    public let actor: String

    /// Creates the args.
    public init(actor: String) {
      self.actor = actor
    }
  }

  /// The key for a user's starter packs, ported from `RQKEY(did)`.
  public static func actorStarterPacks(actor: String?, scope: String? = nil) -> QueryKey {
    QueryKey(
      actorStarterPacksRoot, ActorArgs(actor: actor ?? ""), options: QueryOptions(scope: scope))
  }

  /// The key for a user's packs with membership, ported from
  /// `RQKEY_WITH_MEMBERSHIP(did)`.
  public static func actorStarterPacksWithMembership(
    actor: String?, scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      actorStarterPacksWithMembershipRoot, ActorArgs(actor: actor ?? ""),
      options: QueryOptions(scope: scope))
  }

  /// Args for pack search. RN: `[root, query, limit]`.
  public struct SearchArgs: QueryArgs {
    /// The search query.
    public let query: String
    /// The page limit, which participates in the key exactly as RN's does.
    public let limit: Int

    /// Creates the args.
    public init(query: String, limit: Int) {
      self.query = query
      self.limit = limit
    }
  }

  /// The key for pack search, ported from `RQKEY(query, limit)`.
  public static func search(
    query: String, limit: Int = StarterPackConstants.searchPageSize, scope: String? = nil
  ) -> QueryKey {
    QueryKey(
      searchRoot, SearchArgs(query: query, limit: limit), options: QueryOptions(scope: scope))
  }

  /// Args for a list-members read. RN: `[root, uri]`.
  public struct ListMembersArgs: QueryArgs {
    /// The list URI, or `""` when the read is not yet enabled.
    public let uri: String

    /// Creates the args.
    public init(uri: String) {
      self.uri = uri
    }
  }

  /// The key for a paged list-members read, ported from `RQKEY(uri)`.
  public static func listMembers(uri: String?, scope: String? = nil) -> QueryKey {
    QueryKey(
      listMembersRoot, ListMembersArgs(uri: uri ?? ""), options: QueryOptions(scope: scope))
  }

  /// The key for the exhaustive list-members read, ported from `RQKEY_ALL(uri)`.
  public static func listMembersAll(uri: String?, scope: String? = nil) -> QueryKey {
    QueryKey(
      listMembersAllRoot, ListMembersArgs(uri: uri ?? ""), options: QueryOptions(scope: scope))
  }
}
