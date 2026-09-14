import Foundation

import SwiftAtproto

/// Sources TIDs for newly created preferences (saved feeds, muted words).
///
/// The SDK mints a fresh TID per created item; tests inject a deterministic
/// generator so patch output can be compared against fixed JSON.
public protocol TidGenerator: Sendable {
  func next() -> String
}

/// Production generator: the vendored runtime's monotonic TID.
public struct SystemTidGenerator: TidGenerator {
  public init() {}

  public func next() -> String {
    TID.next().rawValue
  }
}

/// Deterministic generator for tests: `prefix` + zero-padded counter.
public final class SequentialTidGenerator: TidGenerator, @unchecked Sendable {
  private let lock = NSLock()
  private var counter: Int
  private let prefix: String
  private let width: Int

  public init(prefix: String = "3", startingAt: Int = 0, width: Int = 13) {
    self.prefix = prefix
    self.counter = startingAt
    self.width = width
  }

  public func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    let value = counter
    counter += 1
    let digits = String(value)
    let pad = max(0, width - prefix.count - digits.count)
    return prefix + String(repeating: "0", count: pad) + digits
  }
}
