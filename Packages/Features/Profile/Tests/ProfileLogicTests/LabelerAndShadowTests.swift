import Foundation
import Lexicons
import Moderation
import QueryStore
import SwiftAtproto
import Testing

@testable import ProfileLogic

/// The labeler profile variant: the service view plus the viewer's state.
@Suite("Labeler profile") struct LabelerProfileTests {

  private static let labelerDid = "did:plc:labeler"
  private static let viewerDid = "did:plc:me"

  private func makeLabeler(
    did: String = LabelerProfileTests.labelerDid,
    creatorHandle: String = "labeler.example.com",
    likeCount: Int? = 7,
    like: String? = nil,
    creatorBlocking: String? = nil,
    associated: Bool? = nil
  ) -> App.Bsky.LabelerDefs_LabelerViewDetailed {
    App.Bsky.LabelerDefs_LabelerViewDetailed(
      cid: FormatString<LexLink>(rawValue: "bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
      creator: App.Bsky.ActorDefs_ProfileView(
        associated: associated.map { App.Bsky.ActorDefs_ProfileAssociated(labeler: $0) },
        did: FormatString<DID>(rawValue: did),
        handle: FormatString<Handle>(rawValue: creatorHandle),
        viewer: App.Bsky.ActorDefs_ViewerState(
          blocking: creatorBlocking.map { FormatString<ATURI>(rawValue: $0) })),
      indexedAt: FormatString<Date>(rawValue: "2026-01-01T00:00:00.000Z"),
      likeCount: likeCount,
      policies: App.Bsky.LabelerDefs_LabelerPolicies(labelValues: []),
      uri: FormatString<ATURI>(rawValue: "at://\(did)/app.bsky.labeler.service/self"),
      viewer: like.map { App.Bsky.LabelerDefs_LabelerViewerState(
        like: FormatString<ATURI>(rawValue: $0)) })
  }

  /// A missing service view yields no data, so the screen falls back to the
  /// standard header - which is what `enabled: !!profile.associated?.labeler`
  /// plus a loading state achieves in RN.
  @Test func noLabelerServiceYieldsNoData() {
    let data = LabelerProfileViewData(
      labeler: nil, subscribedLabelerDIDs: [], viewerDid: Self.viewerDid, hasSession: true)
    #expect(data == nil)
  }

  /// The like and count come from the service view.
  @Test func likeStateComesFromTheServiceView() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(likeCount: 12, like: "at://did:plc:me/app.bsky.feed.like/1"),
      subscribedLabelerDIDs: [], viewerDid: Self.viewerDid, hasSession: true))
    #expect(data.likeURI == "at://did:plc:me/app.bsky.feed.like/1")
    #expect(data.likeCount == 12)
  }

  /// A null like count reads as zero, matching RN's `labeler.likeCount || 0`.
  @Test func nullLikeCountReadsAsZero() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(likeCount: nil), subscribedLabelerDIDs: [],
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(data.likeCount == 0)
    #expect(data.likeURI == nil)
  }

  /// The subscribed state comes from the preferences' labeler list.
  @Test func subscribedStateComesFromPreferences() throws {
    let subscribed = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), subscribedLabelerDIDs: [Self.labelerDid],
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(subscribed.isSubscribed)

    let notSubscribed = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), subscribedLabelerDIDs: [],
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(!notSubscribed.isSubscribed)

    let noneGiven = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), subscribedLabelerDIDs: [], viewerDid: Self.viewerDid, hasSession: true))
    #expect(!noneGiven.isSubscribed)
  }

  /// The app labeler is recognised by DID, and the subscribe button hides.
  @Test func appLabelerHidesTheSubscribeButton() throws {
    let app = try #require(LabelerProfileViewData(
      labeler: makeLabeler(did: LabelerSubscription.appModerationLabelerDID),
      subscribedLabelerDIDs: [LabelerSubscription.appModerationLabelerDID],
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(app.isAppLabeler)
    #expect(!app.showsSubscribeButton)
    #expect(!app.showsLikeButton, "RN hides the like block for app labelers")

    let thirdParty = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), subscribedLabelerDIDs: [], viewerDid: Self.viewerDid, hasSession: true))
    #expect(!thirdParty.isAppLabeler)
    #expect(thirdParty.showsSubscribeButton)
    #expect(thirdParty.showsLikeButton)
  }

  /// The viewer's own profile shows edit, not subscribe.
  @Test func ownProfileShowsEditNotSubscribe() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(did: Self.viewerDid), subscribedLabelerDIDs: [],
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(data.isMe)
    #expect(data.showsEditProfileButton)
    #expect(!data.showsSubscribeButton)
    #expect(!data.showsMessageButton)
  }

  /// The message button needs a session, a non-self profile, and no block.
  @Test func messageButtonRules() throws {
    let normal = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), subscribedLabelerDIDs: [], viewerDid: Self.viewerDid, hasSession: true))
    #expect(normal.showsMessageButton)

    let signedOut = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), subscribedLabelerDIDs: [], viewerDid: nil, hasSession: false))
    #expect(!signedOut.showsMessageButton)

    let blocked = try #require(LabelerProfileViewData(
      labeler: makeLabeler(creatorBlocking: "at://did:plc:me/app.bsky.graph.block/1"),
      subscribedLabelerDIDs: [], viewerDid: Self.viewerDid, hasSession: true))
    #expect(blocked.isBlocked)
    #expect(!blocked.showsMessageButton)
    #expect(blocked.showsSubscribeButton, "RN only hides the message button on a block")
  }

  /// The like button needs a session.
  @Test func likeButtonNeedsASession() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), subscribedLabelerDIDs: [], viewerDid: nil, hasSession: false))
    #expect(data.showsLikeButton)
    #expect(!data.canLike)
  }

  /// The creator identifier prefers the handle and falls back to the DID.
  @Test func creatorIdentifierPrefersTheHandle() throws {
    let handled = try #require(LabelerProfileViewData(
      labeler: makeLabeler(creatorHandle: "labeler.example.com"),
      subscribedLabelerDIDs: [], viewerDid: Self.viewerDid, hasSession: true))
    #expect(handled.creatorIdentifier == "labeler.example.com")

    let handleless = try #require(LabelerProfileViewData(
      labeler: makeLabeler(creatorHandle: ""), subscribedLabelerDIDs: [],
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(handleless.creatorIdentifier == Self.labelerDid)
  }
}

/// Labeler subscription validation: pruning, counting and the limit.
@Suite("Labeler subscription planning") struct LabelerSubscriptionPlanningTests {

  private func profiles(_ entries: [(did: String, isLabeler: Bool?)]) -> [App.Bsky.ActorDefs_ProfileViewDetailed] {
    entries.map { did, isLabeler in
      App.Bsky.ActorDefs_ProfileViewDetailed(
        associated: isLabeler.map { App.Bsky.ActorDefs_ProfileAssociated(labeler: $0) },
        did: FormatString<DID>(rawValue: did),
        handle: FormatString<Handle>(rawValue: "\(did).example.com"))
    }
  }

  /// A subscribed DID with no profile is unreachable.
  @Test func aMissingProfileIsInvalid() {
    let invalid = LabelerSubscriptionPlanner.invalidLabelers(
      subscribed: ["did:plc:gone"], profiles: [])
    #expect(invalid == [InvalidLabeler(did: "did:plc:gone", reason: .unreachable)])
  }

  /// A profile that is not a labeler service is invalid.
  @Test func aNonLabelerProfileIsInvalid() {
    let invalid = LabelerSubscriptionPlanner.invalidLabelers(
      subscribed: ["did:plc:x"], profiles: profiles([("did:plc:x", false)]))
    #expect(invalid == [InvalidLabeler(did: "did:plc:x", reason: .notALabeler)])
  }

  /// A profile with no associated block at all is not a labeler either - RN
  /// tests `exists.associated && !exists.associated.labeler`.
  @Test func aProfileWithoutAssociationIsInvalid() {
    let invalid = LabelerSubscriptionPlanner.invalidLabelers(
      subscribed: ["did:plc:x"], profiles: profiles([("did:plc:x", nil)]))
    #expect(invalid == [InvalidLabeler(did: "did:plc:x", reason: .notALabeler)])
  }

  /// A valid labeler is kept.
  @Test func aValidLabelerIsKept() {
    let invalid = LabelerSubscriptionPlanner.invalidLabelers(
      subscribed: ["did:plc:x"], profiles: profiles([("did:plc:x", true)]))
    #expect(invalid.isEmpty)
  }

  /// The app labeler is never pruned, even when the server omits it - RN's list
  /// polls the user's configured labelers, and the app labeler is implicit.
  @Test func theAppLabelerIsNeverInvalid() {
    let invalid = LabelerSubscriptionPlanner.invalidLabelers(
      subscribed: [LabelerSubscription.appModerationLabelerDID], profiles: [])
    #expect(invalid.isEmpty)
  }

  /// The effective count is the list less the ones about to be removed, which is
  /// what RN checks against `MAX_LABELERS` *after* pruning.
  @Test func effectiveCountSubtractsInvalidLabelers() {
    let invalid = [
      InvalidLabeler(did: "did:plc:a", reason: .unreachable),
      InvalidLabeler(did: "did:plc:b", reason: .notALabeler),
    ]
    let count = LabelerSubscriptionPlanner.effectiveCount(
      subscribed: ["did:plc:app", "did:plc:a", "did:plc:b", "did:plc:c"], invalid: invalid)
    #expect(count == 2)
  }

  /// Adding is allowed below the limit.
  @Test func addingIsAllowedBelowTheLimit() throws {
    try LabelerSubscriptionPlanner.validateAdd(
      did: "did:plc:new",
      subscribed: Array(0..<19).map { "did:plc:\($0)" },
      invalid: [],
      limit: 20)
  }

  /// Adding is refused at the limit, and the error carries the counts.
  @Test func addingIsRefusedAtTheLimit() {
    #expect(throws: LabelerSubscriptionError.tooManyLabelers(count: 20, limit: 20)) {
      try LabelerSubscriptionPlanner.validateAdd(
        did: "did:plc:new",
        subscribed: Array(0..<20).map { "did:plc:\($0)" },
        invalid: [],
        limit: 20)
    }
  }

  /// Pruning makes room: a full list with one dead labeler accepts a new one,
  /// which is exactly the ordering RN implements.
  @Test func pruningMakesRoomAtTheLimit() throws {
    let subscribed = Array(0..<20).map { "did:plc:\($0)" }
    let invalid = [InvalidLabeler(did: "did:plc:0", reason: .unreachable)]
    try LabelerSubscriptionPlanner.validateAdd(
      did: "did:plc:new", subscribed: subscribed, invalid: invalid, limit: 20)
  }

  /// A DID already in the list is a no-op, so it is never refused.
  @Test func reAddingAnExistingLabelerIsAllowed() throws {
    try LabelerSubscriptionPlanner.validateAdd(
      did: "did:plc:0",
      subscribed: Array(0..<20).map { "did:plc:\($0)" },
      invalid: [],
      limit: 20)
  }

  /// The default limit is `MAX_LABELERS`.
  @Test func theDefaultLimitIsTwenty() {
    #expect(maxLabelers == 20)
  }
}

/// The shadow store: subscription, merge and clear semantics.
@Suite("Profile shadow store") struct ProfileShadowStoreTests {

  private static let did = "did:plc:alice"

  /// An update merges field by field.
  @Test func updatesMerge() async {
    let store = ProfileShadowStore()
    await store.update(did: Self.did, with: ProfileShadow(followingUri: .set("at://f/1")))
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))
    let shadow = await store.shadow(for: Self.did)
    #expect(shadow?.followingUri?.value == "at://f/1")
    #expect(shadow?.muted?.value == true)
  }

  /// A per-DID subscriber is called immediately with the current value, then on
  /// each update.
  @Test func subscribersSeeTheCurrentValueThenUpdates() async throws {
    let store = ProfileShadowStore()
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))

    final class Box: @unchecked Sendable { var values: [Bool?] = [] }
    let box = Box()
    let subscription = await store.subscribe(did: Self.did) { shadow in
      box.values.append(shadow.muted?.value)
    }
    #expect(box.values == [true], "the current value is delivered on subscribe")

    await store.update(did: Self.did, with: ProfileShadow(muted: .set(false)))
    #expect(box.values == [true, false])

    await subscription.cancel()
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))
    #expect(box.values == [true, false], "a cancelled subscription stops receiving")
  }

  /// A subscriber for another DID is not called.
  @Test func subscribersAreScopedToTheirDid() async throws {
    let store = ProfileShadowStore()
    final class Box: @unchecked Sendable { var calls: [Bool] = [] }
    let box = Box()
    let subscription = await store.subscribe(did: "did:plc:other") { shadow in
      box.calls.append(shadow.muted?.value ?? false)
    }
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))
    #expect(box.calls.isEmpty, "a subscriber for another DID is not called")
    await subscription.cancel()
  }

  /// The global listener sees every DID.
  @Test func globalListenersSeeEveryDid() async throws {
    let store = ProfileShadowStore()
    final class Box: @unchecked Sendable { var seen: [String] = [] }
    let box = Box()
    let subscription = await store.listen { did, _ in box.seen.append(did) }
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))
    await store.update(did: "did:plc:bob", with: ProfileShadow(muted: .set(true)))
    #expect(box.seen == [Self.did, "did:plc:bob"])
    await subscription.cancel()
  }

  /// Clearing one DID leaves the others.
  @Test func clearingOneDidLeavesOthers() async {
    let store = ProfileShadowStore()
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))
    await store.update(did: "did:plc:bob", with: ProfileShadow(muted: .set(true)))
    await store.clear(did: Self.did)
    #expect(await store.shadow(for: Self.did) == nil)
    #expect(await store.shadow(for: "did:plc:bob") != nil)
  }

  /// `clearAll` empties the store - the sign-out path.
  @Test func clearAllEmptiesTheStore() async {
    let store = ProfileShadowStore()
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))
    await store.update(did: "did:plc:bob", with: ProfileShadow(muted: .set(true)))
    await store.clearAll()
    #expect(await store.shadow(for: Self.did) == nil)
    #expect(await store.shadow(for: "did:plc:bob") == nil)
  }

  /// The mutate form applies to the existing shadow.
  @Test func mutatingFormAppliesToTheExistingShadow() async {
    let store = ProfileShadowStore()
    await store.update(did: Self.did, with: ProfileShadow(followingUri: .set("at://f/1")))
    await store.update(did: Self.did) { $0.muted = .set(true) }
    let shadow = await store.shadow(for: Self.did)
    #expect(shadow?.followingUri?.value == "at://f/1")
    #expect(shadow?.muted?.value == true)
  }

  /// Subscriber bookkeeping is observable, which the tests above rely on.
  @Test func subscriberCountsAreTracked() async throws {
    let store = ProfileShadowStore()
    let a = await store.subscribe(did: Self.did) { _ in }
    let b = await store.subscribe(did: Self.did) { _ in }
    let global = await store.listen { _, _ in }
    #expect(await store.subscriberCount(for: Self.did) == 2)
    #expect(await store.observerCount == 1)
    await a.cancel()
    await b.cancel()
    await global.cancel()
    #expect(await store.subscriberCount(for: Self.did) == 0)
    #expect(await store.observerCount == 0)
  }

  /// A cleared field survives a merge with an unrelated update.
  @Test func clearedFieldsSurviveMerging() {
    let cleared = ProfileShadow(followingUri: .cleared)
    let merged = cleared.merging(ProfileShadow(muted: .set(true)))
    #expect(merged.followingUri == .cleared)
    #expect(merged.muted?.value == true)
  }
}

/// The toggle queue's ordering and coalescing rules.
@Suite("Toggle mutation queue") struct ToggleMutationQueueTests {

  /// Two opposing toggles in flight run in order, feeding state forward.
  @Test func opposingTogglesRunInOrder() async throws {
    final class Log: @unchecked Sendable { var entries: [(Bool, Bool)] = [] }
    let log = Log()
    let queue = ToggleMutationQueue<Bool>(
      currentState: { false },
      runMutation: { previous, next in
        log.entries.append((previous, next))
        try await Task.sleep(for: .milliseconds(10))
        return next
      },
      onSuccess: { _ in })

    let on = Task { try await queue.toggle(true) }
    _ = try await waitFor { await queue.isBusy }
    let off = Task { try await queue.toggle(false) }
    let onState = try await on.value
    let offState = try await off.value

    #expect(onState == true)
    #expect(offState == false)
    #expect(log.entries.count == 2)
    #expect(log.entries[0] == (false, true), "the first mutation sees the initial state")
    #expect(log.entries[1] == (true, false), "the second sees the first's result")
    #expect(await queue.isBusy == false, "the queue drains")
  }

  /// A toggle matching the running target is coalesced rather than re-sent.
  @Test func aMatchingToggleIsCoalesced() async throws {
    final class Counter: @unchecked Sendable { var count = 0 }
    let counter = Counter()
    let queue = ToggleMutationQueue<Bool>(
      currentState: { false },
      runMutation: { _, next in
        counter.count += 1
        try await Task.sleep(for: .milliseconds(20))
        return next
      },
      onSuccess: { _ in })

    let first = Task { try await queue.toggle(true) }
    _ = try await waitFor { await queue.isBusy }
    let second = Task { try await queue.toggle(true) }
    _ = try await first.value
    let secondState = try? await second.value

    #expect(counter.count == 1, "the duplicate toggle sends nothing")
    #expect(secondState == true, "it resolves with the confirmed state")
  }

  /// A queued toggle that is superseded throws an abort to its caller.
  ///
  /// The replacement is queued while the first mutation is deliberately slow, so
  /// the ordering is observed rather than raced: `toggle` records the pending
  /// task synchronously, and the slow first mutation keeps the drain open long
  /// enough for the third call to replace the second.
  @Test func aSupersededToggleThrows() async throws {
    let started = AsyncStream<Void>.makeStream()
    let queue = ToggleMutationQueue<Bool>(
      currentState: { false },
      runMutation: { _, next in
        started.continuation.yield()
        try await Task.sleep(for: .milliseconds(80))
        return next
      },
      onSuccess: { _ in })

    let first = Task { try await queue.toggle(true) }
    // Wait until the first mutation is genuinely running before queueing more.
    var iterator = started.stream.makeAsyncIterator()
    _ = await iterator.next()

    let superseded = Task { try await queue.toggle(false) }
    let winner = Task { try await queue.toggle(true) }

    _ = try await first.value
    let winnerState = try await winner.value
    #expect(winnerState == true, "the later toggle is the one that runs")

    var threw = false
    do { _ = try await superseded.value } catch is ToggleAbortError { threw = true }
    #expect(threw, "the replaced toggle is aborted")
  }

  /// The finaliser runs once per drain, with that drain's confirmed state.
  ///
  /// A drain is created per toggle that arrives while the queue is idle, so two
  /// awaits produce two drains and two finalises - which is what RN's
  /// `finally { onSuccess(confirmedState) }` does, since the early-return guard
  /// only suppresses a *concurrent* second drain.
  @Test func onSuccessRunsOncePerDrain() async throws {
    final class Box: @unchecked Sendable { var calls: [Bool] = [] }
    let box = Box()
    let queue = ToggleMutationQueue<Bool>(
      currentState: { false },
      runMutation: { _, next in
        // A real mutation takes time; without it the queue would go idle between
        // the two toggles and they would drain separately, which is correct but
        // not what this test is pinning.
        try await Task.sleep(for: .milliseconds(20))
        return next
      },
      onSuccess: { state in box.calls.append(state) })

    // Two toggles overlap, so they join one drain and it finalises once.
    let first = Task { try await queue.toggle(true) }
    _ = try await waitFor { await queue.isBusy }
    let second = Task { try await queue.toggle(false) }
    _ = try await first.value
    _ = try await second.value
    // The finalise runs from the drain's `defer`, which is reached after the
    // awaiting task resumes, so poll rather than assert immediately.
    _ = try await waitFor { box.calls == [false] }
    #expect(box.calls == [false], "one drain, one finalise, with its last state")

    // A later, non-overlapping toggle drains again and finalises with its own
    // state (the queue is idle by now, so this is a fresh drain).
    _ = try await queue.toggle(true)
    _ = try await waitFor { box.calls.count == 2 }
    #expect(box.calls == [false, true], "two drains, two finalises")
  }

  /// A failing mutation does not stop the queue.
  @Test func aFailureDoesNotStrandTheQueue() async throws {
    let queue = ToggleMutationQueue<Bool>(
      currentState: { false },
      runMutation: { _, next in
        if next { throw ToggleAbortError() }
        return next
      },
      onSuccess: { _ in })

    await #expect(throws: ToggleAbortError.self) { try await queue.toggle(true) }
    #expect(await queue.isBusy == false, "the drain closed")
    #expect(try await queue.toggle(false) == false, "the queue is reusable")
  }
}
