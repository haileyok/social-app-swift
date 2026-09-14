import Foundation

public protocol NotificationClock: Sendable {
  /// The current instant.
  func now() -> Date
}

/// The real clock.
public struct SystemNotificationClock: NotificationClock {
  public init() {}

  public func now() -> Date { Date() }
}

/// A clock tests move by hand.
public final class ManualNotificationClock: NotificationClock, @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date

  public init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
    self.current = start
  }

  public func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  /// Moves the clock forward by `seconds`.
  public func advance(by seconds: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    current = current.addingTimeInterval(seconds)
  }

  /// Moves the clock to an absolute instant.
  public func set(_ date: Date) {
    lock.lock()
    defer { lock.unlock() }
    current = date
  }
}

/// A handle to a scheduled poll, so a caller can stop it on sign-out.
public struct NotificationPollToken: Sendable {
  private let cancelAction: @Sendable () -> Void

  public init(cancel: @escaping @Sendable () -> Void) {
    self.cancelAction = cancel
  }

  /// Cancels the poll.
  public func cancel() { cancelAction() }

  /// A token that cancels nothing.
  public static let none = NotificationPollToken {}
}

/// Schedules the unread-count poll.
///
/// The unread coordinator fires once on start, then asks the scheduler for a
/// repeating tick. Abstracting the scheduler is what makes the poll cadence
/// testable without sleeping: a fake can invoke the tick any number of times
/// synchronously.
public protocol NotificationPollScheduler: Sendable {
  /// Schedules `tick` every `interval` seconds.
  ///
  /// The tick is called with the number of the poll since start, so a caller
  /// can distinguish the on-init fetch from later polls.
  @discardableResult
  func schedule(
    every interval: TimeInterval,
    _ tick: @escaping @Sendable (Int) async -> Void
  ) -> NotificationPollToken
}

/// The real scheduler, backed by `Task.sleep`.
public struct SystemNotificationPollScheduler: NotificationPollScheduler {
  public init() {}

  public func schedule(
    every interval: TimeInterval,
    _ tick: @escaping @Sendable (Int) async -> Void
  ) -> NotificationPollToken {
    let task = Task {
      var count = 0
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        count += 1
        await tick(count)
      }
    }
    return NotificationPollToken { task.cancel() }
  }
}

/// A scheduler tests drive by hand.
///
/// `fire(_:)` runs the registered tick the requested number of times, awaiting
/// each, which is what lets a test assert a sequence of unread transitions
/// against a fixed clock.
public final class ManualNotificationPollScheduler: NotificationPollScheduler, @unchecked Sendable {
  private let lock = NSLock()
  private var tick: (@Sendable (Int) async -> Void)?
  private var fires = 0
  /// The interval the coordinator asked for, for assertion.
  public private(set) var requestedInterval: TimeInterval?

  public init() {}

  public func schedule(
    every interval: TimeInterval,
    _ tick: @escaping @Sendable (Int) async -> Void
  ) -> NotificationPollToken {
    lock.lock()
    self.tick = tick
    self.requestedInterval = interval
    lock.unlock()
    return NotificationPollToken { [weak self] in
      self?.lock.lock()
      self?.tick = nil
      self?.lock.unlock()
    }
  }

  /// True once the coordinator has registered a tick.
  public var isScheduled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return tick != nil
  }

  /// Runs `body` in a synchronous critical section.
  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// Runs the scheduled tick `count` times, in order.
  ///
  /// Each iteration takes and releases the lock before awaiting, so the
  /// awaited tick never runs with the lock held.
  @discardableResult
  public func fire(_ count: Int = 1) async -> Int {
    var ran = 0
    for _ in 0..<count {
      let taken = withLock { () -> (@Sendable (Int) async -> Void, Int)? in
        guard let current = tick else { return nil }
        fires += 1
        return (current, fires)
      }
      guard let (current, index) = taken else { break }
      await current(index)
      ran += 1
    }
    return ran
  }
}
