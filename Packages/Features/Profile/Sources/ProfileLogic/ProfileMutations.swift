import Foundation
import Lexicons
import QueryStore
import SwiftAtproto

/// Thrown when a queued toggle is superseded before it runs, or when a toggle
/// repeats the state the previous task already targeted.
///
/// Port of the `AbortError` `useToggleMutationQueue` creates. RN identifies it by
/// `e.name === 'AbortError'`; Swift uses a distinct type so callers can catch it
/// without string matching.
public struct ToggleAbortError: Error, Sendable, Equatable {
  public init() {}
}

/// Serialises repeated on/off toggles against a single server resource.
///
/// Port of `useToggleMutationQueue` in `src/lib/hooks/useToggleMutationQueue.ts`.
/// The behaviours that matter, all preserved:
///
/// - Only one mutation is in flight at a time; a toggle arriving during one is
///   held and run afterwards.
/// - A second toggle arriving while one is queued replaces it, and the replaced
///   caller's `toggle` throws ``ToggleAbortError``. (A toggle is idempotent, so
///   the newer intent wins.)
/// - A queued toggle whose target equals the running task's target is skipped and
///   its caller throws ``ToggleAbortError``.
/// - The server's returned state feeds forward into the next mutation, which is
///   what lets a follow that has not been confirmed yet still be unfollowed.
/// - `onSuccess` runs once when the queue drains, with the last confirmed state.
///
/// Deviation: RN captures `initialState` from the render that created the queue,
/// which can be stale. This port reads the current state through a closure at the
/// start of each drain, so a queue that drains, sits idle, and is used again
/// starts from fresh server state.
public actor ToggleMutationQueue<ServerState: Sendable> {
  private struct Pending {
    let isOn: Bool
    let continuation: CheckedContinuation<ServerState, any Error>
  }

  private let currentState: @Sendable () async -> ServerState
  private let runMutation: @Sendable (ServerState, Bool) async throws -> ServerState
  private let onSuccess: @Sendable (ServerState) -> Void

  private var active: Pending?
  private var queued: Pending?
  private var draining = false

  /// - Parameters:
  ///   - currentState: reads the last confirmed server state.
  ///   - runMutation: performs the change, returning the new confirmed state.
  ///   - onSuccess: called once per drain with the final confirmed state.
  public init(
    currentState: @escaping @Sendable () async -> ServerState,
    runMutation: @escaping @Sendable (ServerState, Bool) async throws -> ServerState,
    onSuccess: @escaping @Sendable (ServerState) -> Void
  ) {
    self.currentState = currentState
    self.runMutation = runMutation
    self.onSuccess = onSuccess
  }

  /// Queues a toggle to `isOn`.
  ///
  /// - Returns: the confirmed state once this toggle's mutation has run.
  /// - Throws: ``ToggleAbortError`` when superseded; otherwise the mutation's
  ///   error.
  public func toggle(_ isOn: Bool) async throws -> ServerState {
    // The first toggle of a drain becomes the active task *synchronously*, which
    // is what lets a toggle arriving a moment later be queued behind it rather
    // than replacing it. RN gets the same ordering because `processQueue()` runs
    // synchronously up to its first `await`.
    if draining {
      if let replaced = queued {
        queued = nil
        replaced.continuation.resume(throwing: ToggleAbortError())
      }
    } else {
      draining = true
    }
    return try await withCheckedThrowingContinuation { continuation in
      if active == nil {
        active = Pending(isOn: isOn, continuation: continuation)
        Task { await self.drain() }
      } else {
        queued = Pending(isOn: isOn, continuation: continuation)
      }
    }
  }

  /// True while a mutation is running or queued. Used by tests.
  public var isBusy: Bool { active != nil || queued != nil }

  private func drain() async {
    var confirmed = await currentState()
    var lastTarget: Bool?
    defer {
      onSuccess(confirmed)
      active = nil
      queued = nil
      draining = false
    }
    while let next = active ?? queued {
      if active == nil { queued = nil }
      active = next
      if lastTarget == next.isOn {
        // The requested state is already the confirmed state, so there is
        // nothing to do. RN rejects the caller here; resolving is the same
        // outcome for an idempotent toggle without a spurious error, so this is
        // a deliberate deviation (documented in tests-ported.md).
        next.continuation.resume(returning: confirmed)
        lastTarget = next.isOn
        active = nil
        continue
      }
      do {
        confirmed = try await runMutation(confirmed, next.isOn)
        lastTarget = next.isOn
        next.continuation.resume(returning: confirmed)
      } catch {
        next.continuation.resume(throwing: error)
      }
      active = nil
    }
  }
}

/// The follow/unfollow queue for one profile.
///
/// Port of `useProfileFollowMutationQueue`. Optimistically writes `pending` into
/// the shadow before queueing, and finalises the shadow with the confirmed URI
/// (or absence) when the queue drains.
public actor ProfileFollowQueue {
  private let client: ProfileClient
  private let store: QueryStore
  private let shadows: ProfileShadowStore
  private let did: String
  private let viewerDid: String?
  private let now: @Sendable () -> Date
  private let queue: ToggleMutationQueue<String?>

  /// RN's `initialFollowingUri`, captured once before the first optimistic write.
  ///
  /// The double optional distinguishes "not yet captured" (`nil`) from "captured,
  /// and there is no follow" (`.some(nil)`). It has to be captured *before*
  /// `unfollow()` clears the shadow, because a later re-read would find the
  /// cleared value and skip the delete it was supposed to perform.
  private let initialFollowingUri = InitialFollowBox()

  /// - Parameters:
  ///   - did: the profile being followed.
  ///   - viewerDid: the signed-in account, whose repo receives the follow record.
  ///   - now: clock for `createdAt`, injectable for deterministic tests.
  public init(
    client: ProfileClient,
    store: QueryStore,
    shadows: ProfileShadowStore,
    did: String,
    viewerDid: String?,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.client = client
    self.store = store
    self.shadows = shadows
    self.did = did
    self.viewerDid = viewerDid
    self.now = now
    let client = client
    let shadows = shadows
    let did = did
    let viewerDid = viewerDid
    let now = now
    let store = store
    let initialFollowingUri = self.initialFollowingUri
    self.queue = ToggleMutationQueue(
      currentState: { initialFollowingUri.value },
      runMutation: { previousUri, shouldFollow in
        if shouldFollow {
          guard let viewerDid else { throw ProfileWriteError.notSignedIn }
          let result = try await client.follow(
            subject: did, repo: viewerDid, createdAt: now())
          return result.uri
        }
        // Only a confirmed (or previously confirmed) follow can be deleted.
        guard let previousUri else { return nil }
        guard let viewerDid else { throw ProfileWriteError.notSignedIn }
        try await client.unfollow(repo: viewerDid, followUri: previousUri)
        return nil
      },
      onSuccess: { finalUri in
        Task {
          await shadows.update(did: did, with: Self.shadowValue(for: finalUri))
          await Self.spliceViewerFollowsCache(
            store: store, viewerDid: viewerDid, did: did, followingUri: finalUri)
        }
      })
  }

  /// Captures the follow URI the queue starts from, once.
  ///
  /// The cache's viewer state is the primary source (that is what RN's
  /// `profile.viewer?.following` reads); a shadow value is preferred over it when
  /// present, because a shadow reflects a mutation the server has already
  /// confirmed this session.
  func captureInitialFollowingUri() async {
    guard initialFollowingUri.value == nil else { return }
    let viewer = await Self.rawViewer(store: store, did: did, scope: viewerDid)
    initialFollowingUri.value = await Self.currentFollowingUri(
      shadows: shadows, did: did, viewer: viewer)
  }

  /// Reads the confirmed follow URI: the shadow's value if it is a real URI, else
  /// the raw follow state.
  ///
  /// A *pending* sentinel reads as "no confirmed URI" - but a shadow that
  /// optimistically cleared the field (`.cleared`) also reads as none, and both
  /// cases must be distinguished from a shadow that was never written. The
  /// distinction only matters for the queued-unfollow path, which needs a real
  /// URI to delete; an `unset` or missing shadow falls back to the server state,
  /// exactly as RN's `initialFollowingUri` does.
  private static func currentFollowingUri(
    shadows: ProfileShadowStore, did: String, viewer: App.Bsky.ActorDefs_ViewerState?
  ) async -> String? {
    guard let shadow = await shadows.shadow(for: did) else {
      return viewer?.following?.rawValue
    }
    guard case .set(let uri) = shadow.followingUri else { return nil }
    return uri == FollowState.pendingSentinel ? nil : uri
  }

  /// The raw viewer state for `did` from the profile cache, if it is held.
  ///
  /// This is the Swift form of RN's `profile.viewer?.following` read at queue
  /// construction: the queue needs to know about a follow the server already
  /// reported, not only one this session made.
  static func rawViewer(
    store: QueryStore, did: String, scope: String?
  ) async -> App.Bsky.ActorDefs_ViewerState? {
    let key = ProfileQueryKeys.profile(did: did, scope: scope)
    guard let payload = try? await store.payload(key, as: ProfileView.self) else { return nil }
    return payload.viewer
  }

  /// The shadow field a finalise write should carry.
  static func shadowValue(for uri: String?) -> ProfileShadow {
    ProfileShadow(followingUri: uri.map { .set($0) } ?? .cleared)
  }

  /// Optimistically marks the profile followed, then queues the follow.
  public func follow() async throws -> String? {
    await captureInitialFollowingUri()
    await shadows.update(did: did, with: ProfileShadow(followingUri: .set(FollowState.pendingSentinel)))
    return try await queue.toggle(true)
  }

  /// Optimistically marks the profile unfollowed, then queues the unfollow.
  public func unfollow() async throws -> String? {
    // Capture before clearing: the delete needs the URI the shadow is about to
    // lose.
    await captureInitialFollowingUri()
    await shadows.update(did: did, with: ProfileShadow(followingUri: .cleared))
    return try await queue.toggle(false)
  }

  /// True while a toggle is in flight or queued.
  public var isBusy: Bool { get async { await queue.isBusy } }

  /// Adds or removes the profile in the viewer's own follows list cache.
  ///
  /// Port of the `queryClient.setQueryData(PROFILE_FOLLOWS_RQKEY(currentAccount.did))`
  /// block in `useProfileFollowMutationQueue`: a confirmed follow is prepended to
  /// page one unless it is already there, and an unfollow is filtered out of every
  /// page. The RN app reaches for the *viewer's* follows list because the profile
  /// screen shows the viewer's follow lists for avatar displays.
  static func spliceViewerFollowsCache(
    store: QueryStore, viewerDid: String?, did: String, followingUri: String?
  ) async {
    guard let viewerDid else { return }
    let key = ProfileQueryKeys.follows(actor: viewerDid, scope: viewerDid)
    guard let current = try? await store.payload(key, as: InfiniteQueryData<ProfileView>.self) else {
      return
    }
    if followingUri != nil {
      let alreadyPresent = current.items.contains { $0.did == did }
      guard !alreadyPresent else { return }
      guard let firstPage = current.pages.first else { return }
      let placeholder = ProfileView.basic(
        App.Bsky.ActorDefs_ProfileView(
          did: FormatString<DID>(rawValue: did),
          handle: FormatString<Handle>(rawValue: did),
          viewer: App.Bsky.ActorDefs_ViewerState(
            following: FormatString<ATURI>(rawValue: followingUri ?? ""))))
      let updated = InfiniteQueryData(
        pages: [
          QueryPage(
            items: [placeholder] + firstPage.items,
            cursor: firstPage.cursor,
            requestCursor: firstPage.requestCursor)
        ] + current.pages.dropFirst())
      await store.setQueryData(updated, for: key)
    } else {
      let filtered = InfiniteQueryData(
        pages: current.pages.map { page in
          QueryPage(
            items: page.items.filter { $0.did != did },
            cursor: page.cursor,
            requestCursor: page.requestCursor)
        })
      await store.setQueryData(filtered, for: key)
    }
  }
}

/// A mutable box shared between a mutation queue and its state closure.
///
/// The closure is built in `init`, before the actor's stored properties are all
/// initialised, so it cannot close over `self`. This box gives it a place to read
/// the captured initial state from instead.
final class InitialFollowBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: String??

  var value: String? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return stored ?? nil
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      stored = .some(newValue)
    }
  }
}

/// The mute queue for one profile, including the reposts-only variant.
///
/// Port of `useProfileMuteMutationQueue` and
/// `useProfileMuteRepostsMutationQueue`. The two share an unmute: turning a
/// reposts-only mute back off removes the mute entirely, which is why the
/// reposts queue's off-branch calls the same `unmuteActor` request.
public actor ProfileMuteQueue {
  private let client: ProfileClient
  private let shadows: ProfileShadowStore
  private let did: String
  private let queue: ToggleMutationQueue<Bool>

  public init(
    client: ProfileClient,
    shadows: ProfileShadowStore,
    did: String
  ) {
    self.client = client
    self.shadows = shadows
    self.did = did
    let client = client
    let did = did
    let shadows = shadows
    self.queue = ToggleMutationQueue(
      currentState: { false },
      runMutation: { _, shouldMute in
        try await client.setMuted(did: did, muted: shouldMute)
        return shouldMute
      },
      onSuccess: { muted in
        Task { await shadows.update(did: did, with: ProfileShadow(muted: .set(muted))) }
      })
  }

  /// Full mute. RN clears any repost-only scope at the same time, because a full
  /// mute replaces it server-side.
  public func mute() async throws {
    await shadows.update(
      did: did, with: ProfileShadow(muted: .set(true), mutedOnlyReposts: .set(false)))
    _ = try await queue.toggle(true)
  }

  /// Full unmute.
  public func unmute() async throws {
    await shadows.update(
      did: did, with: ProfileShadow(muted: .set(false), mutedOnlyReposts: .set(false)))
    _ = try await queue.toggle(false)
  }
}

/// The reposts-only mute queue for one profile.
///
/// Port of `useProfileMuteRepostsMutationQueue`. Not applicable when the account
/// is fully muted: the UI gates that, not this type.
public actor ProfileMuteRepostsQueue {
  private let client: ProfileClient
  private let shadows: ProfileShadowStore
  private let did: String
  private let queue: ToggleMutationQueue<Bool>

  public init(
    client: ProfileClient,
    shadows: ProfileShadowStore,
    did: String
  ) {
    self.client = client
    self.shadows = shadows
    self.did = did
    let client = client
    let did = did
    let shadows = shadows
    self.queue = ToggleMutationQueue(
      currentState: { false },
      runMutation: { _, shouldMute in
        // Muting reposts asks for the scoped mute; unmuting removes the mute.
        try await client.setMutedOnlyReposts(did: did, muted: shouldMute)
        return shouldMute
      },
      onSuccess: { mutedOnlyReposts in
        Task {
          await shadows.update(
            did: did, with: ProfileShadow(mutedOnlyReposts: .set(mutedOnlyReposts)))
        }
      })
  }

  public func muteReposts() async throws {
    await shadows.update(did: did, with: ProfileShadow(mutedOnlyReposts: .set(true)))
    _ = try await queue.toggle(true)
  }

  public func unmuteReposts() async throws {
    await shadows.update(did: did, with: ProfileShadow(mutedOnlyReposts: .set(false)))
    _ = try await queue.toggle(false)
  }
}

/// The block/unblock queue for one profile.
///
/// Port of `useProfileBlockMutationQueue`. Blocks are records in the viewer's
/// repo, so the unblock deletes the URI the block returned; that is exactly why
/// the queue feeds server state forward.
public actor ProfileBlockQueue {
  private let client: ProfileClient
  private let shadows: ProfileShadowStore
  private let did: String
  private let viewerDid: String?
  private let now: @Sendable () -> Date
  private let onFinalize: @Sendable (String, String?) async -> Void
  private let queue: ToggleMutationQueue<String?>

  /// - Parameter onFinalize: called with the DID and its final blocking URI.
  ///   RN uses this hook point to invalidate the conversation list, because a
  ///   block emits no chat log event and would otherwise leave that data stale.
  public init(
    client: ProfileClient,
    shadows: ProfileShadowStore,
    did: String,
    viewerDid: String?,
    now: @escaping @Sendable () -> Date = { Date() },
    onFinalize: @escaping @Sendable (String, String?) async -> Void = { _, _ in }
  ) {
    self.client = client
    self.shadows = shadows
    self.did = did
    self.viewerDid = viewerDid
    self.now = now
    self.onFinalize = onFinalize
    let client = client
    let did = did
    let viewerDid = viewerDid
    let now = now
    let shadows = shadows
    self.queue = ToggleMutationQueue(
      currentState: { nil },
      runMutation: { previousUri, shouldBlock in
        guard let viewerDid else { throw ProfileWriteError.notSignedIn }
        if shouldBlock {
          let result = try await client.block(
            subject: did, repo: viewerDid, createdAt: now())
          return result.uri
        }
        guard let previousUri else { return nil }
        try await client.unblock(repo: viewerDid, blockUri: previousUri)
        return nil
      },
      onSuccess: { finalUri in
        Task {
          await shadows.update(
            did: did,
            with: ProfileShadow(blockingUri: finalUri.map { .set($0) } ?? .cleared))
          await onFinalize(did, finalUri)
        }
      })
  }

  /// Optimistically marks the profile blocked, then queues the block.
  public func block() async throws -> String? {
    await shadows.update(
      did: did, with: ProfileShadow(blockingUri: .set(FollowState.pendingSentinel)))
    return try await queue.toggle(true)
  }

  /// Optimistically marks the profile unblocked, then queues the unblock.
  public func unblock() async throws -> String? {
    await shadows.update(did: did, with: ProfileShadow(blockingUri: .cleared))
    return try await queue.toggle(false)
  }
}
