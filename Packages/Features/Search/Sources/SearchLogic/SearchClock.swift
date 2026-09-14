import Foundation
import Synchronization

/// Schedules the delayed work the search debounce needs.
///
/// The debounce is the one piece of the search pipeline that is genuinely
/// time-dependent, so it is expressed as a protocol here rather than as a
/// `Task.sleep` buried in the state machine. Production uses
/// ``SystemSearchClock``; tests drive ``ManualSearchClock`` by hand, which makes
/// "did the debounce fire?" and "was the in-flight request cancelled?"
/// deterministic instead of racy.
///
/// This is deliberately a *scheduling* seam, not a wall-clock seam: the state
/// machine never reads the time to make a decision, it only asks to be woken
/// after a delay and cancels that request when the query changes.
public protocol SearchClock: Sendable {
  /// Runs `work` after `nanoseconds`, and returns a handle that cancels it.
  ///
  /// Cancelling must prevent `work` from running if it has not yet started; if
  /// it has already started, cancellation is a no-op. Implementations must be
  /// safe to cancel more than once.
  func schedule(afterNanoseconds nanoseconds: UInt64, _ work: @escaping @Sendable () -> Void)
    -> SearchClockCancellation
}

/// A cancellable scheduled item.
public protocol SearchClockCancellation: Sendable {
  /// Prevents the scheduled work from running, if it has not already.
  func cancel()
}

/// The production clock, backed by `DispatchQueue.asyncAfter`.
public struct SystemSearchClock: SearchClock {
  public init() {}

  public func schedule(
    afterNanoseconds nanoseconds: UInt64, _ work: @escaping @Sendable () -> Void
  ) -> SearchClockCancellation {
    let item = DispatchWorkItem(block: work)
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .nanoseconds(Int(nanoseconds)), execute: item)
    return DispatchCancellation(item: item)
  }

  private struct DispatchCancellation: SearchClockCancellation, @unchecked Sendable {
    // `DispatchWorkItem` is not `Sendable`, but `cancel()` is documented as
    // thread-safe, so the unchecked conformance carries an honest invariant.
    let item: DispatchWorkItem
    func cancel() { item.cancel() }
  }
}

/// A clock tests advance by hand.
///
/// Scheduled work is queued with its due time; ``advance(nanoseconds:)`` runs
/// everything that has come due, in order. Cancelled items are dropped when the
/// clock reaches them, so cancellation is observable at the point the debounce
/// would have fired.
public final class ManualSearchClock: SearchClock, @unchecked Sendable {
  private struct Item {
    let id: UInt64
    let dueAt: UInt64
    let work: @Sendable () -> Void
  }

  private struct State {
    var now: UInt64 = 0
    var nextId: UInt64 = 0
    var items: [Item] = []
    var cancelled: Set<UInt64> = []
    /// Every delay passed to ``schedule(afterNanoseconds:_:)``, in order.
    var scheduledDelays: [UInt64] = []
  }

  private let state = Mutex(State())

  public init() {}

  public func schedule(
    afterNanoseconds nanoseconds: UInt64, _ work: @escaping @Sendable () -> Void
  ) -> SearchClockCancellation {
    let id = state.withLock { state -> UInt64 in
      let id = state.nextId
      state.nextId += 1
      state.items.append(Item(id: id, dueAt: state.now + nanoseconds, work: work))
      state.scheduledDelays.append(nanoseconds)
      return id
    }
    return ManualCancellation(clock: self, id: id)
  }

  fileprivate func cancel(_ id: UInt64) {
    state.withLock { $0.cancelled.insert(id) }
  }

  /// Moves time forward, running every due item in schedule order.
  public func advance(nanoseconds: UInt64) {
    let due: [Item] = state.withLock { state in
      state.now += nanoseconds
      let ready = state.items.filter { $0.dueAt <= state.now }.sorted { $0.dueAt < $1.dueAt }
      state.items.removeAll { $0.dueAt <= state.now }
      return ready
    }
    for item in due {
      let wasCancelled = state.withLock { $0.cancelled.remove(item.id) != nil }
      if !wasCancelled { item.work() }
    }
  }

  /// Moves time forward by whole milliseconds.
  public func advance(milliseconds: UInt64) {
    advance(nanoseconds: milliseconds * 1_000_000)
  }

  /// The delays passed to ``schedule(afterNanoseconds:_:)`` so far.
  public var scheduledDelays: [UInt64] {
    state.withLock { $0.scheduledDelays }
  }

  /// The number of scheduled items that have neither run nor been cancelled.
  public var pendingCount: Int {
    state.withLock { $0.items.count }
  }

  private struct ManualCancellation: SearchClockCancellation {
    let clock: ManualSearchClock
    let id: UInt64
    func cancel() { clock.cancel(id) }
  }
}
