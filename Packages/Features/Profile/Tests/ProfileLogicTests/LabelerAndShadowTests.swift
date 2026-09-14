import Foundation
import Lexicons
import Moderation
import Preferences
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

  private func prefs(labelers: [String]) -> ModerationPreferences {
    ModerationPreferences(
      adultContentEnabled: true,
      labels: [:],
      labelers: labelers.map { Preferences.LabelerPreference(did: $0) },
      mutedWords: [],
      hiddenPosts: [])
  }

  /// A missing service view yields no data, so the screen falls back to the
  /// standard header - which is what `enabled: !!profile.associated?.labeler`
  /// plus a loading state achieves in RN.
  @Test func noLabelerServiceYieldsNoData() {
    let data = LabelerProfileViewData(
      labeler: nil, preferences: nil, viewerDid: Self.viewerDid, hasSession: true)
    #expect(data == nil)
  }

  /// The like and count come from the service view.
  @Test func likeStateComesFromTheServiceView() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(like: "at://did:plc:me/app.bsky.feed.like/1", likeCount: 12),
      preferences: nil, viewerDid: Self.viewerDid, hasSession: true))
    #expect(data.likeURI == "at://did:plc:me/app.bsky.feed.like/1")
    #expect(data.likeCount == 12)
  }

  /// A null like count reads as zero, matching RN's `labeler.likeCount || 0`.
  @Test func nullLikeCountReadsAsZero() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(likeCount: nil), preferences: nil,
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(data.likeCount == 0)
    #expect(data.likeURI == nil)
  }

  /// The subscribed state comes from the preferences' labeler list.
  @Test func subscribedStateComesFromPreferences() throws {
    let subscribed = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), preferences: prefs(labelers: [Self.labelerDid]),
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(subscribed.isSubscribed)

    let notSubscribed = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), preferences: prefs(labelers: []),
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(!notSubscribed.isSubscribed)

    let noPreferences = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), preferences: nil, viewerDid: Self.viewerDid, hasSession: true))
    #expect(!noPreferences.isSubscribed)
  }

  /// The app labeler is recognised by DID, and the subscribe button hides.
  @Test func appLabelerHidesTheSubscribeButton() throws {
    let app = try #require(LabelerProfileViewData(
      labeler: makeLabeler(did: BlueskyModerationLabeler.did),
      preferences: prefs(labelers: [BlueskyModerationLabeler.did]),
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(app.isAppLabeler)
    #expect(!app.showsSubscribeButton)
    #expect(!app.showsLikeButton, "RN hides the like block for app labelers")

    let thirdParty = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), preferences: nil, viewerDid: Self.viewerDid, hasSession: true))
    #expect(!thirdParty.isAppLabeler)
    #expect(thirdParty.showsSubscribeButton)
    #expect(thirdParty.showsLikeButton)
  }

  /// The viewer's own profile shows edit, not subscribe.
  @Test func ownProfileShowsEditNotSubscribe() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(did: Self.viewerDid), preferences: nil,
      viewerDid: Self.viewerDid, hasSession: true))
    #expect(data.isMe)
    #expect(data.showsEditProfileButton)
    #expect(!data.showsSubscribeButton)
    #expect(!data.showsMessageButton)
  }

  /// The message button needs a session, a non-self profile, and no block.
  @Test func messageButtonRules() throws {
    let normal = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), preferences: nil, viewerDid: Self.viewerDid, hasSession: true))
    #expect(normal.showsMessageButton)

    let signedOut = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), preferences: nil, viewerDid: nil, hasSession: false))
    #expect(!signedOut.showsMessageButton)

    let blocked = try #require(LabelerProfileViewData(
      labeler: makeLabeler(creatorBlocking: "at://did:plc:me/app.bsky.graph.block/1"),
      preferences: nil, viewerDid: Self.viewerDid, hasSession: true))
    #expect(blocked.isBlocked)
    #expect(!blocked.showsMessageButton)
    #expect(blocked.showsSubscribeButton, "RN only hides the message button on a block")
  }

  /// The like button needs a session.
  @Test func likeButtonNeedsASession() throws {
    let data = try #require(LabelerProfileViewData(
      labeler: makeLabeler(), preferences: nil, viewerDid: nil, hasSession: false))
    #expect(data.showsLikeButton)
    #expect(!data.canLike)
  }

  /// The creator identifier prefers the handle and falls back to the DID.
  @Test func creatorIdentifierPrefersTheHandle() throws {
    let handled = try #require(LabelerProfileViewData(
      labeler: makeLabeler(creatorHandle: "labeler.example.com"),
      preferences: nil, viewerDid: Self.viewerDid, hasSession: true))
    #expect(handled.creatorIdentifier == "labeler.example.com")

    let handleless = try #require(LabelerProfileViewData(
      labeler: makeLabeler(creatorHandle: ""), preferences: nil,
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
      subscribed: [BlueskyModerationLabeler.did], profiles: [])
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
    final class Box: @unchecked Sendable { var count = 0 }
    let box = Box()
    let subscription = await store.subscribe(did: "did:plc:other") { _ in box.count += 1 }
    await store.update(did: Self.did, with: ProfileShadow(muted: .set(true)))
    #expect(box.count == 0)
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
  @Test func aSupersededToggleThrows() async throws {
    let queue = ToggleMutationQueue<Bool>(
      currentState: { false },
      runMutation: { _, next in
        try await Task.sleep(for: .milliseconds(30))
        return next
      },
      onSuccess: { _ in })

    let first = Task { try await queue.toggle(true) }
    _ = try await waitFor { await queue.isBusy }
    let superseded = Task { try await queue.toggle(false) }
    _ = try await waitFor { await queue.isBusy }
    let winner = Task { try await queue.toggle(true) }

    _ = try await first.value
    #expect(try await winner.value == true)

    var threw = false
    do { _ = try await superseded.value } catch is ToggleAbortError { threw = true }
    #expect(threw, "the replaced toggle is aborted")
  }

  /// The finaliser runs once per drain, with the last confirmed state.
  @Test func onSuccessRunsOncePerDrain() async throws {
    final class Box: @unchecked Sendable { var calls: [Bool] = [] }
    let box = Box()
    let queue = ToggleMutationQueue<Bool>(
      currentState: { false },
      runMutation: { _, next in next },
      onSuccess: { state in box.calls.append(state) })

    _ = try await queue.toggle(true)
    _ = try await queue.toggle(false)
    #expect(box.calls == [true], "one drain, one finalise, with the first state")

    // A second drain finalises again with its own state.
    _ = try await queue.toggle(true)
    #expect(box.calls == [true, false])
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
