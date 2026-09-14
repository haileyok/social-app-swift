import Foundation

import ATProtoClient
import Lexicons
import QueryStore
import SwiftAtproto

/// A blocked or muted account list.
///
/// Port of `src/state/queries/my-blocked-accounts.ts` and
/// `src/state/queries/my-muted-accounts.ts`. Both are cursor-paginated appview
/// reads over `app.bsky.graph.getBlocks` / `getMutes` with `limit: 30`, an
/// undefined first page param, and `getNextPageParam: lastPage => lastPage.cursor`.
public enum BlockedMutedList {

  /// RN's `limit: 30` in both queries.
  public static let pageSize = 30

  /// The query-key roots, matching the RN `RQKEY_ROOT`s.
  public static let blockedRoot = "my-blocked-accounts"
  public static let mutedRoot = "my-muted-accounts"

  /// One list's key args. The account did scopes the cache so two accounts on
  /// one device do not share a block list.
  public struct ListArgs: QueryArgs {
    public var accountDid: String?

    public init(accountDid: String? = nil) {
      self.accountDid = accountDid
    }
  }

  /// The key for the viewer's block list.
  public static func blockedKey(_ args: ListArgs) -> QueryKey {
    QueryKey(blockedRoot, args, options: QueryOptions(scope: args.accountDid))
  }

  /// The key for the viewer's mute list.
  public static func mutedKey(_ args: ListArgs) -> QueryKey {
    QueryKey(mutedRoot, args, options: QueryOptions(scope: args.accountDid))
  }
}

/// The viewer's block list: an infinite query over `app.bsky.graph.getBlocks`.
public struct BlockedAccountsQuery: Sendable {
  public let query: InfiniteQuery<App.Bsky.ActorDefs_ProfileView>

  public init(store: QueryStore, client: XrpcClient, args: BlockedMutedList.ListArgs = .init()) {
    typealias Page = QueryPage<App.Bsky.ActorDefs_ProfileView>
    let fetch: @Sendable (String?) async throws -> Page = { cursor in
      let output: App.Bsky.GraphGetBlocks_Output = try await client.get(
        App.Bsky.GraphGetBlocks.id,
        params: [
          ("limit", String(BlockedMutedList.pageSize)),
          ("cursor", cursor),
        ]
      )
      return QueryPage(items: output.blocks, cursor: output.cursor)
    }
    self.query = InfiniteQuery(
      store: store,
      key: BlockedMutedList.blockedKey(args),
      identity: { $0.did.rawValue },
      page: fetch)
  }
}

/// The viewer's mute list: an infinite query over `app.bsky.graph.getMutes`.
public struct MutedAccountsQuery: Sendable {
  public let query: InfiniteQuery<App.Bsky.ActorDefs_ProfileView>

  public init(store: QueryStore, client: XrpcClient, args: BlockedMutedList.ListArgs = .init()) {
    typealias Page = QueryPage<App.Bsky.ActorDefs_ProfileView>
    let fetch: @Sendable (String?) async throws -> Page = { cursor in
      let output: App.Bsky.GraphGetMutes_Output = try await client.get(
        App.Bsky.GraphGetMutes.id,
        params: [
          ("limit", String(BlockedMutedList.pageSize)),
          ("cursor", cursor),
        ]
      )
      return QueryPage(items: output.mutes, cursor: output.cursor)
    }
    self.query = InfiniteQuery(
      store: store,
      key: BlockedMutedList.mutedKey(args),
      identity: { $0.did.rawValue },
      page: fetch)
  }
}

/// The writes that remove an entry from a list.
///
/// The two removals use different mechanisms, which is why they are separate
/// types:
///
/// - **Unblock** deletes the viewer's `app.bsky.graph.block` repo record. The
///   RN app needs the block record's uri, which it reads off
///   `profile.viewer.blocking`.
/// - **Unmute** is an appview procedure, `app.bsky.graph.unmuteActor`.
public struct BlockedMutedRemoval: Sendable {
  /// Deletes one block record.
  public typealias Unblock = @Sendable (_ repoDid: String, _ blockUri: String) async throws -> Void
  /// Unmutes one actor.
  public typealias Unmute = @Sendable (_ did: String) async throws -> Void

  let unblock: Unblock
  let unmute: Unmute

  public init(unblock: @escaping Unblock, unmute: @escaping Unmute) {
    self.unblock = unblock
    self.unmute = unmute
  }

  /// Builds removals over a PDS client (for the block record) and an appview
  /// client (for the mute procedure).
  ///
  /// - Parameters:
  ///   - pds: the account-host client. Block records live in the viewer's repo,
  ///     so deleting one is a PDS write.
  ///   - appview: the routed appview client that serves `unmuteActor`.
  public init(pds: XrpcClient, appview: XrpcClient) {
    self.init(
      unblock: { repoDid, blockUri in
        let rkey = BlockedMutedRemoval.rkey(fromBlockUri: blockUri)
        _ = try await pds.deleteRecord(
          repo: repoDid, collection: "app.bsky.graph.block", rkey: rkey)
      },
      unmute: { did in
        let _: PasswordSession.EmptyBody = try await appview.procedure(
          App.Bsky.GraphUnmuteActor.id,
          body: App.Bsky.GraphUnmuteActor_Input(
            actor: FormatString<AtIdentifier>(rawValue: did)),
          authorization: nil)
      })
  }

  /// Runs an unblock.
  public func unblock(repoDid: String, blockUri: String) async throws {
    try await unblock(repoDid, blockUri)
  }

  /// Runs an unmute.
  public func unmute(did: String) async throws {
    try await unmute(did)
  }

  /// The rkey of a block record, taken from its at-uri.
  ///
  /// Port of `new AtUri(blockUri).rkeySafe`. Returns `""` for a malformed uri,
  /// which the server rejects; the RN code would throw, so the caller sees an
  /// error either way.
  public static func rkey(fromBlockUri uri: String) -> String {
    let parts = uri.split(separator: "/")
    return parts.last.map(String.init) ?? ""
  }
}

/// Applies optimistic removals to the list queries.
///
/// RN invalidates the list query after an unblock/unmute. This port goes one
/// step further and removes the row locally first, then invalidates, so the row
/// disappears immediately and a failed write rolls back. The local step is the
/// whole point of the `QueryStore` integration here.
public enum BlockedMutedOptimistic {

  /// Removes one actor from the block list held in the store.
  ///
  /// - Returns: true when the actor was present and removed.
  @discardableResult
  public static func removeBlocked(
    _ store: QueryStore, did: String, args: BlockedMutedList.ListArgs = .init()
  ) async -> Bool {
    await remove(
      store, key: BlockedMutedList.blockedKey(args), did: did)
  }

  /// Removes one actor from the mute list held in the store.
  @discardableResult
  public static func removeMuted(
    _ store: QueryStore, did: String, args: BlockedMutedList.ListArgs = .init()
  ) async -> Bool {
    await remove(
      store, key: BlockedMutedList.mutedKey(args), did: did)
  }

  static func remove(_ store: QueryStore, key: QueryKey, did: String) async -> Bool {
    let query = InfiniteQuery<App.Bsky.ActorDefs_ProfileView>(
      store: store, key: key, identity: { $0.did.rawValue },
      page: { _ in QueryPage(items: [], cursor: nil) })
    guard let data = try? await store.payload(key, as: InfiniteQueryData<App.Bsky.ActorDefs_ProfileView>.self),
      data.items.contains(where: { $0.did.rawValue == did })
    else { return false }
    await query.updateItems { items in items.filter { $0.did.rawValue != did } }
    return true
  }
}
