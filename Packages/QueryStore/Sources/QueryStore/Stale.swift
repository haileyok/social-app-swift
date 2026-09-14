import Foundation

/// Staleness budgets, ported 1:1 from `src/state/queries/index.ts`.
///
/// The RN module builds millisecond constants from `1e3` and uses `Infinity` for
/// entries that should never go stale on their own. This port keeps the same
/// names and semantics, expressed in seconds so that `INFINITY` can be a real
/// non-finite value (`Duration` cannot represent infinity without overflowing
/// when it is added to a timestamp).
///
/// ```ts
/// export const STALE = {
///   SECONDS: {FIFTEEN: 15 * SECOND, THIRTY: 30 * SECOND},
///   MINUTES: {ONE: MINUTE, THREE: 3 * MINUTE, FIVE: 5 * MINUTE,
///             FIFTEEN: 15 * MINUTE, THIRTY: 30 * MINUTE},
///   HOURS: {ONE: HOUR},
///   INFINITY: Infinity,
/// }
/// ```
public enum STALE {
  public enum SECONDS {
    public static let FIFTEEN: TimeInterval = 15
    public static let THIRTY: TimeInterval = 30
  }

  public enum MINUTES {
    public static let ONE: TimeInterval = 60
    public static let THREE: TimeInterval = 180
    public static let FIVE: TimeInterval = 300
    public static let FIFTEEN: TimeInterval = 900
    public static let THIRTY: TimeInterval = 1800
  }

  public enum HOURS {
    public static let ONE: TimeInterval = 3600
  }

  /// Never stale. Stands in for `Infinity`, for queries that are persisted and
  /// refreshed by explicit invalidation rather than by time.
  public static let INFINITY: TimeInterval = .infinity
}

/// Garbage-collection budgets, ported 1:1 from `src/state/queries/index.ts`.
///
/// `GCTIME.INFINITY` is the value the RN app pairs with `persistedVersion`: a
/// query that is evicted immediately after being persisted would never survive a
/// restart.
public enum GCTIME {
  public static let INFINITY: TimeInterval = .infinity
}
