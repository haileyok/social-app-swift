import Foundation
import ATProtoClient
import Lexicons
import SwiftAtproto
import QueryStore
import Testing

@testable import ProfileLogic

/// The optimistic follow/unfollow flow, including rollback.
@Suite("Profile follow flow") struct ProfileFollowFlowTests {

  private static let viewer = "did:plc:me"
  private static let alice = "did:plc:alice"

  /// Builds the queue over a scripted transport.
  private func makeQueue(
    transport: ScriptedTransport,
    store: QueryStore = QueryStore(),
    shadows: ProfileShadowStore = ProfileShadowStore(),
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
  ) -> (ProfileFollowQueue, ProfileShadowStore, QueryStore) {
    // Writes go to the PDS, reads to the appview - the two-client split the RN
    // session holds.
    let queue = ProfileFollowQueue(
      client: ProfileClient(client: makeClient(transport).client, writeClient: makeXrpcClient(transport)),
      store: store,
      shadows: shadows,
      did: Self.alice,
      viewerDid: Self.viewer,
      now: now)
    return (queue, shadows, store)
  }

  /// A `follow` writes a record to the viewer's repo and names the subject.
  @Test func followWritesTheRecordToTheViewersRepo() async throws {
    let transport = ScriptedTransport(script: [
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.graph.follow/1", "cid": "bafy1"])
    ])
    let (queue, shadows, _) = makeQueue(transport: transport)
    let uri = try await queue.follow()

    #expect(uri == "at://did:plc:me/app.bsky.graph.follow/1")
    let request = try #require(transport.lastRequest)
    #expect(request.method == "POST")
    #expect(request.path == "https://pds.example.com/xrpc/com.atproto.repo.createRecord")
    let json = request.json
    #expect(json["repo"] as? String == Self.viewer, "the record lands in the viewer's repo")
    #expect(json["collection"] as? String == "app.bsky.graph.follow")
    let record = try #require(json["record"] as? [String: Any])
    #expect(record["subject"] as? String == Self.alice)
    #expect(record["$type"] as? String == "app.bsky.graph.follow")
    #expect(record["createdAt"] != nil)

    // The shadow is finalised with the confirmed URI, in the queue's onSuccess
    // task, so poll for it.
    let finalised = try await waitForShadow(shadows, did: Self.alice) { shadow in
      shadow.followingUri?.value == "at://did:plc:me/app.bsky.graph.follow/1"
    }
    #expect(finalised)
  }

  /// The optimistic write happens before the request completes, showing the
  /// pending state.
  @Test func followWritesPendingBeforeTheRequestSettles() async throws {
    let transport = ScriptedTransport(script: [
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.graph.follow/1"])
    ])
    transport.responseDelay = .milliseconds(50)
    let shadows = ProfileShadowStore()
    let (queue, _, _) = makeQueue(transport: transport, shadows: shadows)

    // Start the follow and observe the shadow without awaiting the call.
    let task = Task { try await queue.follow() }
    let pending = try await waitForShadow(shadows, did: Self.alice) { shadow in
      shadow.followingUri?.value == FollowState.pendingSentinel
    }
    #expect(pending, "the optimistic write must set the pending sentinel")
    _ = try await task.value

    // The finalise runs in the queue's onSuccess task, so poll for it.
    let finalised = try await waitForShadow(shadows, did: Self.alice) { shadow in
      shadow.followingUri?.value == "at://did:plc:me/app.bsky.graph.follow/1"
    }
    #expect(finalised, "the confirmed URI replaces the pending sentinel")
  }

  /// A failed follow rolls the optimistic write back.
  ///
  /// The rollback is not an explicit undo: RN's `onSuccess` finaliser runs from a
  /// `finally`, so it fires on a throw as well, writing the last *confirmed*
  /// state over the optimistic one. With no prior follow that confirmed state is
  /// "not following", which is the rollback.
  @Test func aFailedFollowRollsBack() async throws {
    let transport = ScriptedTransport.failing(
      with: XrpcError(rawCode: "RateLimitExceeded", message: "slow down", status: 429))
    let shadows = ProfileShadowStore()
    let (queue, _, _) = makeQueue(transport: transport, shadows: shadows)

    await #expect(throws: (any Error).self) {
      try await queue.follow()
    }
    let shadow = try #require(await shadows.shadow(for: Self.alice))
    #expect(shadow.followingUri?.value == nil, "the follow is rolled back")
    #expect(shadow.followingUri?.isSet == true, "the shadow clears the field")
  }

  /// A failed unfollow restores the follow the queue started from.
  @Test func aFailedUnfollowRestoresThePreviousFollow() async throws {
    let followUri = "at://did:plc:me/app.bsky.graph.follow/5"
    let transport = ScriptedTransport.failing(
      with: XrpcError(rawCode: "InternalServerError", message: "boom", status: 500))
    let shadows = ProfileShadowStore()
    await shadows.update(did: Self.alice, with: ProfileShadow(followingUri: .set(followUri)))
    let (queue, _, _) = makeQueue(transport: transport, shadows: shadows)

    await #expect(throws: (any Error).self) {
      try await queue.unfollow()
    }
    let shadow = try #require(await shadows.shadow(for: Self.alice))
    #expect(shadow.followingUri?.value == followUri, "the follow comes back")
  }

  /// A successful unfollow deletes the follow record from the viewer's repo.
  @Test func unfollowDeletesTheFollowRecord() async throws {
    let followUri = "at://did:plc:me/app.bsky.graph.follow/1"
    let transport = ScriptedTransport(script: [ScriptedTransport.json([:])])
    let shadows = ProfileShadowStore()
    let (queue, _, _) = makeQueue(transport: transport, shadows: shadows)

    // Seed the shadow with an existing follow. (A follow the server reports but
    // no shadow records is covered by the raw-viewer fallback test below.)
    await shadows.update(did: Self.alice, with: ProfileShadow(followingUri: .set(followUri)))
    let uri = try await queue.unfollow()
    #expect(uri == nil)

    let request = try #require(transport.lastRequest)
    #expect(request.method == "POST")
    #expect(request.path == "https://pds.example.com/xrpc/com.atproto.repo.deleteRecord")
    let json = request.json
    #expect(json["repo"] as? String == Self.viewer)
    #expect(json["collection"] as? String == "app.bsky.graph.follow")
    #expect(json["rkey"] as? String == "1", "the rkey is split out of the follow URI")

    let finalised = try await waitForShadow(shadows, did: Self.alice) { shadow in
      shadow.followingUri == .cleared
    }
    #expect(finalised, "the shadow clears the field")
  }

  /// Unfollowing when no follow was ever confirmed sends no request.
  @Test func unfollowWithoutAPriorFollowSendsNothing() async throws {
    let transport = ScriptedTransport(script: [])
    let shadows = ProfileShadowStore()
    let (queue, _, _) = makeQueue(transport: transport, shadows: shadows)
    let uri = try await queue.unfollow()
    #expect(uri == nil)
    #expect(transport.requestCount == 0, "there is no record to delete")
  }

  /// A follow, then an unfollow, without awaiting the first: the queue runs the
  /// follow, then deletes the record it just minted. This is the behaviour that
  /// makes the queue more than a lock.
  @Test func queuedUnfollowDeletesTheJustCreatedFollow() async throws {
    let followUri = "at://did:plc:me/app.bsky.graph.follow/7"
    let transport = ScriptedTransport(script: [
      ScriptedTransport.json(["uri": followUri]),
      ScriptedTransport.json([:]),
    ])
    // A slow first response keeps the drain open long enough for the unfollow to
    // join it rather than start a fresh drain.
    transport.responseDelay = .milliseconds(40)
    let shadows = ProfileShadowStore()
    let (queue, _, _) = makeQueue(transport: transport, shadows: shadows)

    let followResult = Task { try await queue.follow() }
    // Let the first toggle claim the active slot, then queue the opposite.
    _ = try await waitFor { await queue.isBusy }
    let unfollowResult = Task { try await queue.unfollow() }
    let followed = try await followResult.value
    let unfollowed = try await unfollowResult.value

    #expect(followed == followUri)
    #expect(unfollowed == nil)
    #expect(transport.requestCount == 2)
    let delete = try #require(transport.received.last)
    #expect(delete.path.hasSuffix("deleteRecord"))
    #expect(delete.json["rkey"] as? String == "7")
  }

  /// A `notSignedIn` viewer cannot follow, and the optimistic write is not
  /// finalised into a real URI.
  @Test func followWithoutASessionThrows() async throws {
    let transport = ScriptedTransport(script: [])
    let shadows = ProfileShadowStore()
    let queue = ProfileFollowQueue(
      client: makeClient(transport), store: QueryStore(), shadows: shadows,
      did: Self.alice, viewerDid: nil)

    await #expect(throws: ProfileWriteError.notSignedIn) {
      try await queue.follow()
    }
    #expect(transport.requestCount == 0)
  }

  /// A confirmed follow is prepended to the viewer's own follows-list cache.
  @Test func confirmedFollowIsPrependedToTheViewersFollowsCache() async throws {
    let store = QueryStore()
    let key = ProfileQueryKeys.follows(actor: Self.viewer, scope: Self.viewer)
    let existing = InfiniteQueryData(pages: [
      QueryPage(items: [ProfileView.basic(makeBasicProfile(did: "did:plc:bob"))], cursor: "next")
    ])
    await store.setQueryData(existing, for: key)

    let transport = ScriptedTransport(script: [
      ScriptedTransport.json(["uri": "at://did:plc:me/app.bsky.graph.follow/1"])
    ])
    let (queue, _, _) = makeQueue(transport: transport, store: store)
    _ = try await queue.follow()

    // The splice runs in the queue's onSuccess task, so poll for it.
    let spliced = try await waitFor { @Sendable in
      guard let data = try? await store.payload(key, as: InfiniteQueryData<ProfileView>.self)
      else { return false }
      return data.items.count == 2
    }
    #expect(spliced)
    let data = try #require(try await store.payload(key, as: InfiniteQueryData<ProfileView>.self))
    #expect(data.items.first?.did == Self.alice, "the new follow goes to the front")
    #expect(data.items.last?.did == "did:plc:bob")
  }

  /// An unfollow removes the profile from every page of the cached list.
  @Test func unfollowRemovesFromEveryPageOfTheCache() async throws {
    let store = QueryStore()
    let key = ProfileQueryKeys.follows(actor: Self.viewer, scope: Self.viewer)
    let existing = InfiniteQueryData(pages: [
      QueryPage(items: [ProfileView.basic(makeBasicProfile(did: Self.alice))], cursor: "next"),
      QueryPage(items: [ProfileView.basic(makeBasicProfile(did: "did:plc:bob"))], cursor: nil),
    ])
    await store.setQueryData(existing, for: key)

    let transport = ScriptedTransport(script: [ScriptedTransport.json([:])])
    let shadows = ProfileShadowStore()
    await shadows.update(
      did: Self.alice,
      with: ProfileShadow(followingUri: .set("at://did:plc:me/app.bsky.graph.follow/1")))
    let (queue, _, _) = makeQueue(transport: transport, store: store, shadows: shadows)
    _ = try await queue.unfollow()

    let removed = try await waitFor { @Sendable in
      guard let data = try? await store.payload(key, as: InfiniteQueryData<ProfileView>.self)
      else { return false }
      return data.items.count == 1
    }
    #expect(removed)
    let data = try #require(try await store.payload(key, as: InfiniteQueryData<ProfileView>.self))
    #expect(data.items.first?.did == "did:plc:bob")
  }

  /// A malformed follow URI is rejected before any request.
  @Test func aMalformedFollowUriIsRejected() async throws {
    let transport = ScriptedTransport(script: [])
    let shadows = ProfileShadowStore()
    await shadows.update(did: Self.alice, with: ProfileShadow(followingUri: .set("not-a-uri")))
    let (queue, _, _) = makeQueue(transport: transport, shadows: shadows)
    await #expect(throws: ProfileWriteError.malformedRecordURI("not-a-uri")) {
      try await queue.unfollow()
    }
    #expect(transport.requestCount == 0, "the request is rejected before it is sent")
  }
}

/// The record-key split, exercised directly.
@Suite("Record keys") struct RecordKeyTests {
  /// A well-formed URI yields its rkey.
  @Test func splitsAWellFormedUri() {
    #expect(
      ProfileClient.recordKey(from: "at://did:plc:me/app.bsky.graph.follow/3kabc")
        == "3kabc")
  }

  /// A trailing slash still yields the rkey.
  @Test func toleratesATrailingSlash() {
    #expect(ProfileClient.recordKey(from: "at://did:plc:me/app.bsky.graph.follow/3kabc/") == "3kabc")
  }

  /// A URI without an rkey is rejected.
  @Test func rejectsAURiWithoutAnRkey() {
    #expect(ProfileClient.recordKey(from: "at://did:plc:me/app.bsky.graph.follow") == nil)
    #expect(ProfileClient.recordKey(from: "not-a-uri") == nil)
    #expect(ProfileClient.recordKey(from: "at://") == nil)
  }

  /// A record written by the follow path carries the ISO-8601 `createdAt` the
  /// lexicon requires.
  @Test func createdAtIsIso8601() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let text = ProfileClient.iso8601(date)
    #expect(text.hasPrefix("2023-11-14T"))
    #expect(text.hasSuffix("Z"))
  }
}

/// The author-feed reply filter.
@Suite("Author feed filter") struct AuthorFeedFilterTests {

  private func item(
    uri: String, author: String, parent: String? = nil, parentAuthor: String? = nil,
    reason: App.Bsky.FeedDefs_FeedViewPost_Reason? = nil
  ) -> App.Bsky.FeedDefs_FeedViewPost {
    App.Bsky.FeedDefs_FeedViewPost(
      post: App.Bsky.FeedDefs_PostView(
        author: App.Bsky.ActorDefs_ProfileViewBasic(
          did: FormatString<DID>(rawValue: author),
          handle: FormatString<Handle>(rawValue: "\(author).example.com")),
        cid: FormatString<LexLink>(rawValue: "bafy"),
        indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
        record: .any(EmptyRecord()),
        uri: FormatString<ATURI>(rawValue: uri)),
      reason: reason,
      reply: parent.map { parentUri in
        App.Bsky.FeedDefs_ReplyRef(
          parent: .feedDefsPostView(
            App.Bsky.FeedDefs_PostView(
              author: App.Bsky.ActorDefs_ProfileViewBasic(
                did: FormatString<DID>(rawValue: parentAuthor ?? author),
                handle: FormatString<Handle>(rawValue: "x.example.com")),
              cid: FormatString<LexLink>(rawValue: "bafy"),
              indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
              record: .any(EmptyRecord()),
              uri: FormatString<ATURI>(rawValue: parentUri))),
          root: .feedDefsPostView(
            App.Bsky.FeedDefs_PostView(
              author: App.Bsky.ActorDefs_ProfileViewBasic(
                did: FormatString<DID>(rawValue: author),
                handle: FormatString<Handle>(rawValue: "x.example.com")),
              cid: FormatString<LexLink>(rawValue: "bafy"),
              indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
              record: .any(EmptyRecord()),
              uri: FormatString<ATURI>(rawValue: parentUri))))
      })
  }

  /// Only the posts tab filters; the others pass the page through untouched.
  @Test func onlyThePostsTabFilters() {
    let replyToOther = item(
      uri: "at://a/1", author: "did:plc:alice", parent: "at://b/2", parentAuthor: "did:plc:bob")
    let feed = [replyToOther]
    for tab in [ProfileTab.replies, .media, .videos, .likes] {
      #expect(
        ProfileClient.filterAuthorFeed(feed, actor: "did:plc:alice", tab: tab).count == 1,
        "\(tab.rawValue) must not filter")
    }
    #expect(
      ProfileClient.filterAuthorFeed(feed, actor: "did:plc:alice", tab: .posts).isEmpty,
      "the posts tab drops a reply to someone else")
  }

  /// A non-reply is always kept.
  @Test func aTopLevelPostIsKept() {
    let feed = [item(uri: "at://a/1", author: "did:plc:alice")]
    #expect(ProfileClient.filterAuthorFeed(feed, actor: "did:plc:alice", tab: .posts).count == 1)
  }

  /// A repost is kept even when it is a reply.
  @Test func aRepostIsKept() {
    let feed = [
      item(
        uri: "at://a/1", author: "did:plc:alice", parent: "at://b/2", parentAuthor: "did:plc:bob",
        reason: .feedDefsReasonRepost(App.Bsky.FeedDefs_ReasonRepost(
          by: App.Bsky.ActorDefs_ProfileViewBasic(
            did: FormatString<DID>(rawValue: "did:plc:alice"),
            handle: FormatString<Handle>(rawValue: "alice.example.com")),
          indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"))))
    ]
    #expect(ProfileClient.filterAuthorFeed(feed, actor: "did:plc:alice", tab: .posts).count == 1)
  }

  /// A pin is kept.
  @Test func aPinIsKept() {
    let feed = [
      item(uri: "at://a/1", author: "did:plc:alice", reason: .feedDefsReasonPin(App.Bsky.FeedDefs_ReasonPin()))
    ]
    #expect(ProfileClient.filterAuthorFeed(feed, actor: "did:plc:alice", tab: .posts).count == 1)
  }

  /// A reply in the author's own thread, whose parent is on the page and also
  /// the author's, is kept.
  @Test func anAuthorThreadReplyIsKept() {
    let parent = item(uri: "at://a/1", author: "did:plc:alice")
    let reply = item(
      uri: "at://a/2", author: "did:plc:alice", parent: "at://a/1", parentAuthor: "did:plc:alice")
    let feed = [parent, reply]
    #expect(ProfileClient.filterAuthorFeed(feed, actor: "did:plc:alice", tab: .posts).count == 2)
  }

  /// A reply whose parent is absent from the page is kept, matching RN's
  /// "either we haven't fetched the parent, or the only record we have is on
  /// feedItem.reply.parent" comment.
  @Test func aReplyWithAMissingParentIsKept() {
    let reply = item(
      uri: "at://a/2", author: "did:plc:alice", parent: "at://a/1", parentAuthor: "did:plc:alice")
    #expect(ProfileClient.filterAuthorFeed([reply], actor: "did:plc:alice", tab: .posts).count == 1)
  }

  /// A three-deep author thread is kept by walking up two levels.
  @Test func aDeepAuthorThreadIsKept() {
    let root = item(uri: "at://a/1", author: "did:plc:alice")
    let middle = item(
      uri: "at://a/2", author: "did:plc:alice", parent: "at://a/1", parentAuthor: "did:plc:alice")
    let leaf = item(
      uri: "at://a/3", author: "did:plc:alice", parent: "at://a/2", parentAuthor: "did:plc:alice")
    #expect(
      ProfileClient.filterAuthorFeed([root, middle, leaf], actor: "did:plc:alice", tab: .posts).count
        == 3)
  }
}

/// A record body for fixtures that need one but whose contents do not matter.
struct EmptyRecord: Codable, Hashable, Sendable {}

/// Polls `condition` until it holds, or a short budget expires.
///
/// The mutation queues finalise their shadow writes and cache splices in a
/// detached `Task`, so a test that asserts on those must wait for the task
/// rather than assume it has run by the time `toggle` returns. This is
/// deliberately a poll rather than a sleep, so a green run is fast.
func waitFor(
  attempts: Int = 200,
  interval: Duration = .milliseconds(5),
  _ condition: @Sendable () async -> Bool
) async throws -> Bool {
  for _ in 0..<attempts {
    if await condition() { return true }
    try await Task.sleep(for: interval)
  }
  return false
}

/// Waits until the shadow for `did` satisfies `predicate`.
func waitForShadow(
  _ store: ProfileShadowStore, did: String, attempts: Int = 200,
  _ predicate: @Sendable (ProfileShadow) -> Bool
) async throws -> Bool {
  try await waitFor(attempts: attempts) { @Sendable in
    guard let shadow = await store.shadow(for: did) else { return false }
    return predicate(shadow)
  }
}
