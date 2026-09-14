import Foundation

/// The clock and sleeper the video poller uses, so tests can drive time.
///
/// The RN poller calls `setTimeout` directly, which is why its timing is only
/// observable through fake timers. Injecting the sleep keeps the retry and
/// timeout policy testable without waiting.
public protocol VideoPollClock: Sendable {
  /// The current instant.
  func now() -> Date
  /// Suspends for `seconds`.
  func sleep(seconds: Double) async throws
}

/// The real clock: `Task.sleep`, driven by the system monotonic clock.
public struct SystemVideoPollClock: VideoPollClock {
  public init() {}

  public func now() -> Date { Date() }

  public func sleep(seconds: Double) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
  }
}
