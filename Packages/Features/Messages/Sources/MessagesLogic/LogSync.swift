import Foundation

/// The outcome of one log-sync poll.
public struct LogSyncBatch: Sendable {
  /// The events to apply, oldest first.
  public var events: [ChatLogEvent]
  /// Whether anything new arrived.
  public var hasNewEvents: Bool
  /// The cursor the sync is now positioned at.
  public var cursor: String?

  public init(events: [ChatLogEvent] = [], hasNewEvents: Bool = false, cursor: String? = nil) {
    self.events = events
    self.hasNewEvents = hasNewEvents
    self.cursor = cursor
  }
}

/// Failure phase, so a caller can tell an unseeded bus from a mid-session drop.
public enum LogSyncFailurePhase: String, Sendable, Hashable {
  /// The very first `getLog` failed: there is no cursor to resume from.
  case initFailed
  /// A later poll failed: the cursor is still valid and can be resumed.
  case pollFailed
}

/// The error a failed sync reports.
public struct LogSyncError: Error, Sendable {
  /// Where the failure happened.
  public let phase: LogSyncFailurePhase
  /// The underlying error.
  public let underlying: any Error

  public init(phase: LogSyncFailurePhase, underlying: any Error) {
    self.phase = phase
    self.underlying = underlying
  }
}

/// The incremental log-sync engine: cursor management and rev de-duplication.
///
/// Port of `MessagesEventBus` in `src/state/messages/events/agent.ts`, reduced to
/// the part that has no timers or React: fetch the log, advance the cursor, and
/// hand back only the events newer than what has been seen.
///
/// ## Cursor protocol
///
/// `getLog` returns a `cursor` (the newest `rev` the service had at read time)
/// plus the `logs` since the requested cursor. The engine:
///
/// 1. On ``initialize()``, calls `getLog` with no cursor and adopts the returned
///    `cursor` as the position *without* emitting events. This is the RN `init`
///    behavior: the first call seeds the cursor, it does not replay history.
/// 2. On ``poll()``, calls `getLog(cursor: position)` and keeps only events whose
///    `rev` is strictly greater than the position, advancing the position to the
///    highest rev seen. RN's comparison is a plain string `>` on the rev, which
///    is what the service's cursor ordering relies on, so this port keeps it.
/// 3. Events without a `rev` (an unrecognized event, or one the decoder could not
///    attribute) are dropped and do *not* advance the cursor, matching RN's
///    `if ('rev' in ev && typeof ev.rev === 'string')` guard.
///
/// The engine is deliberately an actor *and* holds no timers: scheduling the
/// poll interval belongs to the caller (the app's foreground/background
/// lifecycle), which is also what makes the whole thing testable on Linux.
public actor LogSync {
  private let client: any ChatXrpc
  /// The current position: the newest `rev` that has been applied.
  private var position: String?

  /// Creates a log sync.
  ///
  /// - Parameter client: the chat transport.
  public init(client: any ChatXrpc) {
    self.client = client
  }

  /// The current cursor, or `nil` before the first successful call.
  public var cursor: String? { position }

  /// True once a cursor has been seeded.
  public var isInitialized: Bool { position != nil }

  /// Seeds the cursor. Does not emit events.
  ///
  /// Port of `init()`. A failed seed raises ``LogSyncError`` with phase
  /// ``LogSyncFailurePhase/initFailed``; the cursor stays `nil`, so a retry
  /// re-runs the seed.
  @discardableResult
  public func initialize() async throws -> String? {
    do {
      let page = try await client.getLog(cursor: nil)
      // RN takes the max of the existing rev and the server cursor, so a
      // re-initialize after a successful poll never rewinds.
      if let incoming = page.cursor, position == nil || incoming > position! {
        position = incoming
      }
      return position
    } catch {
      throw LogSyncError(phase: .initFailed, underlying: error)
    }
  }

  /// Polls for new events, advancing the cursor.
  ///
  /// Port of `poll()`. A failure raises ``LogSyncError`` with phase
  /// ``LogSyncFailurePhase/pollFailed`` and leaves the cursor untouched, so the
  /// next poll resumes from exactly where this one stopped: an event that
  /// arrived while the poll was failing is not skipped.
  ///
  /// - Returns: the events newer than the current cursor.
  @discardableResult
  public func poll() async throws -> LogSyncBatch {
    let requested = position
    do {
      let page = try await client.getLog(cursor: requested)

      var events: [ChatLogEvent] = []
      for event in page.logs {
        guard let rev = event.rev else { continue }
        // Only events strictly past the cursor are new. An unseeded sync admits
        // everything: RN never polls before `init` has seeded, so this is the
        // robust reading of "no cursor yet" rather than a silent drop.
        guard let current = position else {
          position = rev
          events.append(event)
          continue
        }
        guard rev > current else { continue }
        position = rev
        events.append(event)
      }

      // RN advances the cursor only from event revs during a poll; the response
      // cursor is used solely to seed. Keeping that makes a poll that returned
      // nothing a true no-op, so a retry re-reads the same window.
      return LogSyncBatch(
        events: events, hasNewEvents: !events.isEmpty, cursor: position)
    } catch {
      throw LogSyncError(phase: .pollFailed, underlying: error)
    }
  }

  /// Resumes after a failure by retrying the appropriate phase.
  ///
  /// Port of `recoverFromError`: an unseeded bus re-runs `initialize`, a seeded
  /// one polls from the held cursor. It never re-seeds a seeded cursor, because
  /// the seed takes the server's head and would skip the events that arrived
  /// while offline.
  @discardableResult
  public func recover() async throws -> LogSyncBatch {
    if position == nil {
      _ = try await initialize()
      return LogSyncBatch(events: [], hasNewEvents: false, cursor: position)
    }
    return try await poll()
  }

  /// Forces the cursor. Exposed for tests and for restoring a persisted
  /// position.
  public func setCursor(_ cursor: String?) {
    position = cursor
  }
}
