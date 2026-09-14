import Foundation
import Synchronization

/// Wall-clock source used by the store for staleness decisions.
///
/// Everything time-dependent goes through this protocol so tests can inject a
/// deterministic clock instead of sleeping.
public protocol QueryClock: Sendable {
  /// Current time in microseconds since the epoch.
  func nowMicroseconds() -> Int64
}

/// The real clock.
public struct SystemQueryClock: QueryClock {
  public init() {}

  public func nowMicroseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000_000)
  }
}

/// A clock tests advance by hand.
///
/// ```swift
/// let clock = ManualQueryClock()
/// clock.advance(by: STALE.SECONDS.THIRTY)
/// ```
public final class ManualQueryClock: QueryClock, @unchecked Sendable {
  private let storage: Mutex<Int64>

  /// Creates a clock at `startMicroseconds` (0 by default).
  public init(startMicroseconds: Int64 = 0) {
    self.storage = Mutex(startMicroseconds)
  }

  public func nowMicroseconds() -> Int64 { storage.withLock { $0 } }

  /// Moves the clock forward by `seconds`.
  public func advance(by seconds: TimeInterval) {
    storage.withLock { $0 += Int64((seconds * 1_000_000).rounded()) }
  }

  /// Moves the clock forward by `milliseconds`.
  public func advance(milliseconds: Int64) {
    storage.withLock { $0 += milliseconds * 1_000 }
  }

  /// Moves the clock to an absolute microsecond timestamp.
  public func set(microseconds: Int64) {
    storage.withLock { $0 = microseconds }
  }
}
