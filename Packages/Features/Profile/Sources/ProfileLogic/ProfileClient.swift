import ATProtoClient
import Foundation
import Lexicons
import QueryStore
import SwiftAtproto

/// A client for the profile feature's reads.
///
/// Wraps an ``XrpcClient`` and issues the exact requests the RN query functions
/// issue, so query functions stay one line and the request shape is asserted in
/// one place.
public struct ProfileClient: Sendable {
  /// The XRPC client reads go through - the appview.
  public let client: XrpcClient

  /// The XRPC client writes go through - the PDS.
  ///
  /// The RN app holds two clients per session (`useAppviewClient` and
  /// `usePdsClient`) and never mixes them: reads are proxied to the appview,
  /// writes go straight to the account's PDS. Defaults to ``client`` for reads
  /// that need no second host.
  public let writeClient: XrpcClient

  public init(client: XrpcClient, writeClient: XrpcClient? = nil) {
    self.client = client
    self.writeClient = writeClient ?? client
  }

  // MARK: - Profiles

  /// `app.bsky.actor.getProfile` - port of `useProfileQuery`.
  public func getProfile(actor: String, authorization: String? = nil) async throws
    -> App.Bsky.ActorDefs_ProfileViewDetailed
  {
    try await client.get(
      App.Bsky.ActorGetProfile.id,
      params: [("actor", actor)],
      authorization: authorization)
  }

  /// `app.bsky.actor.getProfiles` - port of `useProfilesQuery`.
  public func getProfiles(actors: [String], authorization: String? = nil) async throws
    -> App.Bsky.ActorGetProfiles_Output
  {
    try await client.get(
      App.Bsky.ActorGetProfiles.id,
      params: [("actors", actors.joined(separator: ","))],
      authorization: authorization)
  }

  // MARK: - Author feeds

  /// One page of an author feed, dispatched on the tab's endpoint.
  ///
  /// Port of `AuthorFeedAPI.fetch` / `LikesFeedAPI.fetch`, including the
  /// `posts_and_author_threads` reply filter `AuthorFeedAPI._filter` applies
  /// after the response arrives.
  public func getAuthorFeedPage(
    actor: String, tab: ProfileTab, cursor: String?, limit: Int, authorization: String? = nil
  ) async throws -> (items: [App.Bsky.FeedDefs_FeedViewPost], cursor: String?) {
    let request = ProfileFeedRequest(actor: actor, tab: tab)
    let params = request.parameters(cursor: cursor, limit: limit)
    if request.tab.usesAuthorFeed {
      let output: App.Bsky.FeedGetAuthorFeed_Output = try await client.get(
        request.endpoint, params: params, authorization: authorization)
      return (Self.filterAuthorFeed(output.feed, actor: actor, tab: tab), output.cursor)
    }
    let output: App.Bsky.FeedGetActorLikes_Output = try await client.get(
      request.endpoint, params: params, authorization: authorization)
    return (output.feed, output.cursor)
  }

  /// Applies `AuthorFeedAPI._filter` for the `posts_and_author_threads` tab.
  ///
  /// Only the posts tab filters. The rule keeps a post when it is not a reply,
  /// when it is a repost or a pin, or when it is part of a reply chain the author
  /// started. `isAuthorReplyChain` walks up the parents the page happens to
  /// contain and treats a missing parent as "show it".
  static func filterAuthorFeed(
    _ feed: [App.Bsky.FeedDefs_FeedViewPost], actor: String, tab: ProfileTab
  ) -> [App.Bsky.FeedDefs_FeedViewPost] {
    guard tab.authorFeedFilter == .postsAndAuthorThreads else { return feed }
    return feed.filter { item in
      guard item.reply != nil else { return true }
      if isRepost(item.reason) || isPin(item.reason) { return true }
      return isAuthorReplyChain(actor: actor, post: item, feed: feed)
    }
  }

  /// True for a `#reasonRepost`.
  static func isRepost(_ reason: App.Bsky.FeedDefs_FeedViewPost_Reason?) -> Bool {
    if case .feedDefsReasonRepost = reason { return true }
    return false
  }

  /// True for a `#reasonPin`.
  static func isPin(_ reason: App.Bsky.FeedDefs_FeedViewPost_Reason?) -> Bool {
    if case .feedDefsReasonPin = reason { return true }
    return false
  }

  /// Port of `isAuthorReplyChain`.
  ///
  /// Returns false when the post or its immediate parent is by someone other than
  /// `actor`. When the parent is not in the page, the chain is treated as intact
  /// and the post is shown; otherwise the walk continues upward. The `depth`
  /// bound is not in the RN recursion - RN relies on the parent lookup
  /// terminating - but a malformed page could otherwise cycle, so the bound is
  /// applied and documented as a deviation.
  static func isAuthorReplyChain(
    actor: String,
    post: App.Bsky.FeedDefs_FeedViewPost,
    feed: [App.Bsky.FeedDefs_FeedViewPost],
    depth: Int = 0
  ) -> Bool {
    guard depth < 32 else { return true }
    guard post.post.author.did.rawValue == actor else { return false }
    guard let parent = post.reply?.parent else { return true }
    switch parent {
    case .feedDefsPostView(let parentView):
      guard parentView.author.did.rawValue == actor else { return false }
      guard let parentPost = feed.first(where: { $0.post.uri == parentView.uri }) else {
        return true
      }
      return isAuthorReplyChain(actor: actor, post: parentPost, feed: feed, depth: depth + 1)
    default:
      return true
    }
  }

  // MARK: - Social graph lists

  /// One page of `app.bsky.graph.getFollows`.
  ///
  /// `sort` is omitted when `nil`, matching the RN conditional spread: the
  /// vendored lexicon rejects an undeclared key whose value is `undefined`.
  public func getFollowsPage(
    actor: String, sort: ActorListSort?, cursor: String?, limit: Int,
    authorization: String? = nil
  ) async throws -> (items: [App.Bsky.ActorDefs_ProfileView], cursor: String?) {
    var params: [(String, String?)] = [("actor", actor), ("cursor", cursor)]
    if let sort { params.append(("sort", sort.rawValue)) }
    params.append(("limit", String(limit)))
    let output: App.Bsky.GraphGetFollows_Output = try await client.get(
      App.Bsky.GraphGetFollows.id, params: params, authorization: authorization)
    return (output.follows, output.cursor)
  }

  /// One page of `app.bsky.graph.getFollowers`.
  public func getFollowersPage(
    actor: String, sort: ActorListSort?, cursor: String?, limit: Int,
    authorization: String? = nil
  ) async throws -> (items: [App.Bsky.ActorDefs_ProfileView], cursor: String?) {
    var params: [(String, String?)] = [("actor", actor), ("cursor", cursor)]
    if let sort { params.append(("sort", sort.rawValue)) }
    params.append(("limit", String(limit)))
    let output: App.Bsky.GraphGetFollowers_Output = try await client.get(
      App.Bsky.GraphGetFollowers.id, params: params, authorization: authorization)
    return (output.followers, output.cursor)
  }

  /// One page of `app.bsky.graph.getKnownFollowers`.
  public func getKnownFollowersPage(
    actor: String, cursor: String?, limit: Int, authorization: String? = nil
  ) async throws -> (items: [App.Bsky.ActorDefs_ProfileView], cursor: String?) {
    let output: App.Bsky.GraphGetKnownFollowers_Output = try await client.get(
      App.Bsky.GraphGetKnownFollowers.id,
      params: [("actor", actor), ("cursor", cursor), ("limit", String(limit))],
      authorization: authorization)
    return (output.followers, output.cursor)
  }

  // MARK: - Labelers

  /// `app.bsky.labeler.getServices` with `detailed: true`.
  public func getLabelerService(did: String, authorization: String? = nil) async throws
    -> App.Bsky.LabelerDefs_LabelerViewDetailed?
  {
    let output: App.Bsky.LabelerGetServices_Output = try await client.get(
      App.Bsky.LabelerGetServices.id,
      params: [("detailed", "true"), ("dids", did)],
      authorization: authorization)
    guard case .labelerDefsLabelerViewDetailed(let detailed) = output.views.first else {
      return nil
    }
    return detailed
  }

  /// `app.bsky.labeler.getServices` without `detailed`.
  public func getLabelerServices(dids: [String], authorization: String? = nil) async throws
    -> [App.Bsky.LabelerDefs_LabelerView]
  {
    let output: App.Bsky.LabelerGetServices_Output = try await client.get(
      App.Bsky.LabelerGetServices.id,
      params: [("dids", dids.joined(separator: ","))],
      authorization: authorization)
    return output.views.compactMap { view in
      if case .labelerDefsLabelerView(let basic) = view { return basic }
      return nil
    }
  }

  /// `app.bsky.labeler.getServices` with `detailed: true`, for many DIDs.
  public func getLabelerServicesDetailed(dids: [String], authorization: String? = nil)
    async throws -> [App.Bsky.LabelerDefs_LabelerViewDetailed]
  {
    let output: App.Bsky.LabelerGetServices_Output = try await client.get(
      App.Bsky.LabelerGetServices.id,
      params: [("detailed", "true"), ("dids", dids.joined(separator: ","))],
      authorization: authorization)
    return output.views.compactMap { view in
      if case .labelerDefsLabelerViewDetailed(let detailed) = view { return detailed }
      return nil
    }
  }

  // MARK: - Writes

  /// `app.bsky.graph.follow` - a `createRecord` on the PDS.
  ///
  /// Port of `useProfileFollowMutation`. The record is the generated
  /// ``App/Bsky/GraphFollow`` so its `$type` and field validation come from the
  /// lexicon rather than being hand-built. The record lands in the *viewer's*
  /// repo and names the followed account as its subject.
  public func follow(
    subject did: String, repo: String, createdAt: Date, authorization: String? = nil
  ) async throws -> (uri: String, cid: String?) {
    let record = FollowRecord(
      createdAt: FormatString<Date>(rawValue: Self.iso8601(createdAt)),
      subject: FormatString<DID>(rawValue: did))
    let result = try await writeClient.createRecord(
      repo: repo, collection: App.Bsky.GraphFollow.nsId, record: record,
      authorization: authorization)
    return (result.uri, result.cid)
  }

  /// `app.bsky.graph.follow` deletion.
  ///
  /// Port of `useProfileUnfollowMutation`, which deletes the record the
  /// *viewer's* repo holds rather than the subject's.
  public func unfollow(
    repo: String, followUri: String, authorization: String? = nil
  ) async throws {
    guard let rkey = Self.recordKey(from: followUri) else {
      throw ProfileWriteError.malformedRecordURI(followUri)
    }
    _ = try await writeClient.deleteRecord(
      repo: repo, collection: App.Bsky.GraphFollow.nsId, rkey: rkey,
      authorization: authorization)
  }

  /// `app.bsky.graph.block` - a `createRecord` on the PDS.
  ///
  /// Port of `useProfileBlockMutation`. RN builds this with `pdsClient.create`
  /// rather than a generated typed call; the record shape is the same.
  public func block(
    subject did: String, repo: String, createdAt: Date, authorization: String? = nil
  ) async throws -> (uri: String, cid: String?) {
    let record = BlockRecord(
      createdAt: FormatString<Date>(rawValue: Self.iso8601(createdAt)),
      subject: FormatString<DID>(rawValue: did))
    let result = try await writeClient.createRecord(
      repo: repo, collection: App.Bsky.GraphBlock.nsId, record: record,
      authorization: authorization)
    return (result.uri, result.cid)
  }

  /// `app.bsky.graph.block` deletion.
  ///
  /// Port of `useProfileUnblockMutation`, which splits the block URI and deletes
  /// from the viewer's repo.
  public func unblock(repo: String, blockUri: String, authorization: String? = nil)
    async throws
  {
    guard let rkey = Self.recordKey(from: blockUri) else {
      throw ProfileWriteError.malformedRecordURI(blockUri)
    }
    _ = try await writeClient.deleteRecord(
      repo: repo, collection: App.Bsky.GraphBlock.nsId, rkey: rkey,
      authorization: authorization)
  }

  /// The `app.bsky.graph.follow` record body.
  ///
  /// Hand-written for the same reason as ``BlockRecord``: the generated
  /// ``App/Bsky/GraphFollow`` encoder omits `$type`, which the PDS requires on a
  /// record body. The fields and their order match the lexicon.
  struct FollowRecord: Encodable, Sendable {
    var type: String
    var createdAt: FormatString<Date>
    var subject: FormatString<DID>

    init(createdAt: FormatString<Date>, subject: FormatString<DID>) {
      self.type = App.Bsky.GraphFollow.nsId
      self.createdAt = createdAt
      self.subject = subject
    }

    enum CodingKeys: String, CodingKey {
      case type = "$type"
      case createdAt
      case subject
    }
  }

  /// The `app.bsky.graph.block` record body.
  ///
  /// Hand-written rather than taken from ``App/Bsky/GraphBlock`` because the
  /// generated type's initialiser orders `createdAt` before `subject` while the
  /// lexicon JSON orders them the other way, and because the block path is the
  /// one place RN also constructs the record itself.
  struct BlockRecord: Encodable, Sendable {
    var type: String
    var createdAt: FormatString<Date>
    var subject: FormatString<DID>

    init(createdAt: FormatString<Date>, subject: FormatString<DID>) {
      self.type = App.Bsky.GraphBlock.nsId
      self.createdAt = createdAt
      self.subject = subject
    }

    enum CodingKeys: String, CodingKey {
      case type = "$type"
      case createdAt
      case subject
    }
  }

  // MARK: - Mutes

  /// `app.bsky.actor.mute` - port of `useProfileMuteMutation`.
  public func setMuted(did: String, muted: Bool, authorization: String? = nil) async throws {
    if muted {
      try await muteActor(actor: did, onlyReposts: nil, authorization: authorization)
    } else {
      try await unmuteActor(actor: did, authorization: authorization)
    }
  }

  /// A reposts-only mute, or its removal.
  ///
  /// Port of `useProfileMuteRepostsMutation` / `useProfileUnmuteMutation`: muting
  /// reposts sends `onlyReposts: true`, unmuting removes the mute entirely.
  public func setMutedOnlyReposts(
    did: String, muted: Bool, authorization: String? = nil
  ) async throws {
    if muted {
      try await muteActor(actor: did, onlyReposts: true, authorization: authorization)
    } else {
      try await unmuteActor(actor: did, authorization: authorization)
    }
  }

  /// `app.bsky.actor.mute`.
  func muteActor(actor: String, onlyReposts: Bool?, authorization: String?) async throws {
    _ = try await client.procedure(
      "app.bsky.actor.mute",
      body: MuteActorBody(actor: actor, onlyReposts: onlyReposts),
      authorization: authorization)
      as ATProtoClient.XrpcClient.EmptyResponse
  }

  /// `app.bsky.actor.unmute`.
  func unmuteActor(actor: String, authorization: String?) async throws {
    _ = try await client.procedure(
      "app.bsky.actor.unmute",
      body: MuteActorBody(actor: actor, onlyReposts: nil),
      authorization: authorization)
      as ATProtoClient.XrpcClient.EmptyResponse
  }

  /// The `app.bsky.actor.mute` request body.
  struct MuteActorBody: Encodable, Sendable {
    var actor: String
    /// Undeclared in the vendored lexicon at the time of writing; forwarded when
    /// set, exactly as the RN app does with its conditional spread.
    var onlyReposts: Bool?
  }

  /// The record key portion of an `at://` URI: `.../<collection>/<rkey>`.
  ///
  /// RN uses `new AtUri(uri).rkeySafe`; this is the same split without pulling in
  /// the URI parser, and it rejects a URI that is too short to carry one.
  public static func recordKey(from uri: String) -> String? {
    guard uri.hasPrefix("at://") else { return nil }
    let parts = uri.split(separator: "/", omittingEmptySubsequences: false)
    // ["at:", "", "did:...", "collection", "rkey"] - allow a trailing slash.
    guard parts.count >= 5, !parts[4].isEmpty else { return nil }
    return String(parts[4])
  }

  /// Formats a `Date` the way `toDatetimeString` does.
  static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

/// Failures the profile write paths raise before a request is sent.
public enum ProfileWriteError: Error, Sendable, Equatable {
  /// A follow or block URI could not be split into a repo and record key.
  case malformedRecordURI(String)
  /// The viewer is not signed in.
  case notSignedIn
  /// The chosen image could not be read.
  case unreadableImage(String)
}

/// Builds the page fetchers an ``InfiniteQuery`` needs.
public enum ProfileFetchers {
  /// Page size for the follows and followers lists. RN: `PAGE_SIZE = 30`.
  public static let followListPageSize = 30
  /// Page size for the known-followers list. RN: `PAGE_SIZE = 50`.
  public static let knownFollowersPageSize = 50

  /// A follows-list query.
  public static func followsQuery(
    store: QueryStore,
    client: ProfileClient,
    actor: String,
    sort: ActorListSort? = nil,
    scope: String? = nil,
    pageSize: Int = followListPageSize,
    authorization: @escaping @Sendable () -> String? = { nil }
  ) -> InfiniteQuery<App.Bsky.ActorDefs_ProfileView> {
    InfiniteQuery(
      store: store,
      key: ProfileQueryKeys.follows(actor: actor, sort: sort, scope: scope),
      identity: { $0.did.rawValue },
      page: { cursor in
        let page = try await client.getFollowsPage(
          actor: actor, sort: sort, cursor: cursor, limit: pageSize,
          authorization: authorization())
        return QueryPage(items: page.items, cursor: page.cursor)
      })
  }

  /// A followers-list query.
  public static func followersQuery(
    store: QueryStore,
    client: ProfileClient,
    actor: String,
    sort: ActorListSort? = nil,
    scope: String? = nil,
    pageSize: Int = followListPageSize,
    authorization: @escaping @Sendable () -> String? = { nil }
  ) -> InfiniteQuery<App.Bsky.ActorDefs_ProfileView> {
    InfiniteQuery(
      store: store,
      key: ProfileQueryKeys.followers(actor: actor, sort: sort, scope: scope),
      identity: { $0.did.rawValue },
      page: { cursor in
        let page = try await client.getFollowersPage(
          actor: actor, sort: sort, cursor: cursor, limit: pageSize,
          authorization: authorization())
        return QueryPage(items: page.items, cursor: page.cursor)
      })
  }

  /// A known-followers query.
  public static func knownFollowersQuery(
    store: QueryStore,
    client: ProfileClient,
    actor: String,
    scope: String? = nil,
    pageSize: Int = knownFollowersPageSize,
    authorization: @escaping @Sendable () -> String? = { nil }
  ) -> InfiniteQuery<App.Bsky.ActorDefs_ProfileView> {
    InfiniteQuery(
      store: store,
      key: ProfileQueryKeys.knownFollowers(actor: actor, scope: scope),
      identity: { $0.did.rawValue },
      page: { cursor in
        let page = try await client.getKnownFollowersPage(
          actor: actor, cursor: cursor, limit: pageSize, authorization: authorization())
        return QueryPage(items: page.items, cursor: page.cursor)
      })
  }

  /// An author-feed query for one tab.
  public static func authorFeedQuery(
    store: QueryStore,
    client: ProfileClient,
    actor: String,
    tab: ProfileTab,
    scope: String? = nil,
    authorization: @escaping @Sendable () -> String? = { nil }
  ) -> InfiniteQuery<App.Bsky.FeedDefs_FeedViewPost> {
    InfiniteQuery(
      store: store,
      key: ProfileQueryKeys.authorFeed(actor: actor, tab: tab, scope: scope),
      identity: { $0.post.uri.rawValue },
      page: { cursor in
        let page = try await client.getAuthorFeedPage(
          actor: actor, tab: tab, cursor: cursor, limit: tab.pageSize,
          authorization: authorization())
        return QueryPage(items: page.items, cursor: page.cursor)
      })
  }
}
