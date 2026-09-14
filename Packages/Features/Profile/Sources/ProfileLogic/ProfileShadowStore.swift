import Foundation
import Lexicons

/// A detachable handle to a shadow subscription.
///
/// ``QueryStore/QuerySubscription`` cannot be constructed outside its package,
/// so this is the local equivalent: a closure the producer supplies, with an
/// idempotent `cancel`.
public struct ShadowSubscription: Sendable {
  private let cancelAction: @Sendable () async -> Void

  public init(cancelAction: @escaping @Sendable () async -> Void) {
    self.cancelAction = cancelAction
  }

  /// Detaches the subscription. Safe to call more than once.
  public func cancel() async { await cancelAction() }

  /// A subscription that does nothing.
  public static let inactive = ShadowSubscription(cancelAction: {})
}

/// The store of profile shadows plus the closure subscribers that watch them.
///
/// Port of `src/state/cache/profile-shadow.ts`. The RN implementation is a
/// module-level `WeakMap` keyed by profile object identity, plus an
/// `eventemitter3` emitter keyed by DID. Swift keeps one actor keyed by DID:
/// that is the identity the emitter actually used
/// (`emitter.emit(did, value)`), it survives a refetch that yields a new object,
/// and it makes concurrent updates safe.
///
/// ```swift
/// let shadows = ProfileShadowStore()
/// await shadows.update(did: alice) { $0.followingUri = .set("pending") }
/// let data = ProfileHeaderViewData(
///   profile: profile, shadow: await shadows.shadow(for: alice), ...)
/// ```
public actor ProfileShadowStore {
  private var shadows: [String: ProfileShadow] = [:]
  private var subscribers: [String: [UUID: @Sendable (ProfileShadow) -> Void]] = [:]
  private var globalSubscribers: [UUID: @Sendable (String, ProfileShadow) -> Void] = [:]

  public init() {}

  /// The shadow for `did`, or `nil` when none has been written.
  public func shadow(for did: String) -> ProfileShadow? { shadows[did] }

  /// Merges `value` into the shadow for `did` and notifies subscribers.
  ///
  /// Port of `updateProfileShadow`: `{...existing, ...value}`, then an emit on
  /// both the per-DID channel and the all-DIDs channel.
  public func update(did: String, with value: ProfileShadow) {
    let merged = (shadows[did] ?? ProfileShadow()).merging(value)
    shadows[did] = merged
    for subscriber in subscribers[did]?.values ?? [:].values {
      subscriber(merged)
    }
    for observer in globalSubscribers.values {
      observer(did, merged)
    }
  }

  /// Applies `mutate` to the current shadow for `did`, if any, and stores it.
  public func update(did: String, _ mutate: @Sendable (inout ProfileShadow) -> Void) {
    var shadow = shadows[did] ?? ProfileShadow()
    mutate(&shadow)
    update(did: did, with: shadow)
  }

  /// Removes the shadow for `did`, so the next render reads the server state.
  public func clear(did: String) {
    shadows[did] = nil
  }

  /// Removes every shadow. Call on account change or sign-out.
  public func clearAll() {
    shadows.removeAll()
  }

  /// Subscribes to updates for one DID. Returns a handle that detaches it.
  @discardableResult
  public func subscribe(
    did: String, onChange: @escaping @Sendable (ProfileShadow) -> Void
  ) -> ShadowSubscription {
    let id = UUID()
    subscribers[did, default: [:]][id] = onChange
    if let current = shadows[did] { onChange(current) }
    return ShadowSubscription { [weak self] in
      await self?.removeSubscriber(did: did, id: id)
    }
  }

  /// Subscribes to updates for every DID.
  ///
  /// Port of `listenProfileShadowUpdate`, which the non-React consumers (the
  /// chat agent) use.
  @discardableResult
  public func listen(
    _ onChange: @escaping @Sendable (String, ProfileShadow) -> Void
  ) -> ShadowSubscription {
    let id = UUID()
    globalSubscribers[id] = onChange
    return ShadowSubscription { [weak self] in
      await self?.removeObserver(id: id)
    }
  }

  /// Subscriber count for one DID. Used by tests.
  public func subscriberCount(for did: String) -> Int { subscribers[did]?.count ?? 0 }

  /// Global subscriber count. Used by tests.
  public var observerCount: Int { globalSubscribers.count }

  private func removeSubscriber(did: String, id: UUID) {
    subscribers[did]?[id] = nil
  }

  private func removeObserver(id: UUID) {
    globalSubscribers[id] = nil
  }
}
