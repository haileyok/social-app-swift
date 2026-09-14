import ATProtoClient
import Foundation
import Lexicons
import SwiftAtproto

/// One item in a conversation's rendered list.
///
/// Port of the `ConvoItem` union in `src/state/messages/convo/types.ts`. The
/// order the list is built in is RN's: past history (oldest first), then
/// messages received or sent after history was loaded, then the pending local
/// echo, then error rows.
public enum ConvoItem: Sendable, Hashable {
  /// A user-originated message.
  case message(Chat.Bsky.ConvoDefs_MessageView)
  /// A deleted-message tombstone.
  case deletedMessage(Chat.Bsky.ConvoDefs_DeletedMessageView)
  /// A system message.
  case systemMessage(Chat.Bsky.ConvoDefs_SystemMessageView)
  /// A locally echoed message awaiting a server id.
  case pendingMessage(PendingMessage)
  /// A retryable error row.
  case error(code: ConvoItemErrorCode)

  /// The list key. RN's `key`.
  public var key: String {
    switch self {
    case .message(let m): m.id
    case .deletedMessage(let m): m.id
    case .systemMessage(let m): m.id
    case .pendingMessage(let m): m.id
    case .error(let code): code.rawValue
    }
  }

  /// The message identity, for the deleted-set filter. Non-message rows are nil.
  public var messageId: String? {
    switch self {
    case .message(let m): m.id
    case .deletedMessage(let m): m.id
    case .systemMessage(let m): m.id
    case .pendingMessage(let m): m.id
    case .error: nil
    }
  }
}

/// Error rows a conversation can render.
public enum ConvoItemErrorCode: String, Sendable, Hashable {
  /// History fetching failed. RN: `ConvoItemError.HistoryFailed`.
  case historyFailed = "error-history-failed"
  /// The log firehose failed. RN: `ConvoItemError.FirehoseFailed`.
  case firehoseFailed = "error-firehose-failed"
}

/// A locally echoed message awaiting reconciliation.
///
/// RN keeps `{id: tempId, message: MessageInput}` in `pendingMessages` and
/// synthesizes a `messageView` at render time (`getItems`). This port keeps the
/// same split: the pending entry carries the input and the synthesized
/// placeholder carries the shape the list renders.
public struct PendingMessage: Sendable, Hashable {
  /// The temporary id, unique within the conversation.
  public var id: String
  /// The input the caller asked to send.
  public var message: Chat.Bsky.ConvoDefs_MessageInput
  /// Whether the whole pending queue is in a failed state.
  public var failed: Bool

  public init(id: String, message: Chat.Bsky.ConvoDefs_MessageInput, failed: Bool = false) {
    self.id = id
    self.message = message
    self.failed = failed
  }

  /// The placeholder message view the list renders for this pending entry.
  ///
  /// Port of the synthesized view in RN's `getItems`: a real-looking view whose
  /// rev is the sentinel `__fake__` so a log event carrying the real one
  /// replaces it cleanly.
  public func placeholderView(senderDid: String, sentAt: Date) -> Chat.Bsky.ConvoDefs_MessageView {
    ConvoMessage.optimisticMessageView(
      id: id, rev: ConvoMessage.fakeRev, senderDid: senderDid, sentAt: sentAt,
      text: message.text, facets: message.facets)
  }
}

extension ConvoMessage {
  /// The sentinel rev the RN agent stamps on a locally echoed message.
  public static let fakeRev = "__fake__"
}

/// How a send failure should be treated.
///
/// Port of `pendingMessageFailure` in `src/state/messages/convo/agent.ts`:
/// a 5xx-class failure is `recoverable` (the whole queue is retryable via
/// `sendMessageBatch`), anything else is `unrecoverable` and just renders as
/// failed.
public enum SendFailure: String, Sendable, Hashable {
  /// The server was unavailable; the queue can be retried as a batch.
  case recoverable
  /// The server rejected the message; retrying will not help.
  case unrecoverable
}

/// The state one conversation's model holds.
public struct ConversationState: Sendable, Equatable {
  /// The convo view, once loaded.
  public var convo: Chat.Bsky.ConvoDefs_ConvoView?
  /// The rendered items, in display order.
  public var items: [ConvoItem]
  /// True while an older history page is in flight.
  public var isFetchingHistory: Bool
  /// True when every older page has been read (RN's `oldestRev === null`).
  public var hasAllHistory: Bool
  /// The current send failure, if any.
  public var pendingMessageFailure: SendFailure?
  /// True when history fetching failed and a retry row is showing.
  public var historyFailed: Bool

  public init(
    convo: Chat.Bsky.ConvoDefs_ConvoView? = nil, items: [ConvoItem] = [],
    isFetchingHistory: Bool = false, hasAllHistory: Bool = false,
    pendingMessageFailure: SendFailure? = nil, historyFailed: Bool = false
  ) {
    self.convo = convo
    self.items = items
    self.isFetchingHistory = isFetchingHistory
    self.hasAllHistory = hasAllHistory
    self.pendingMessageFailure = pendingMessageFailure
    self.historyFailed = historyFailed
  }
}

/// The local conversation model: history, the pending outbox, reactions and
/// read state for one conversation.
///
/// Port of `Convo` in `src/state/messages/convo/agent.ts`, minus the React
/// subscription plumbing. The state machine is the same:
///
/// - `pastMessages` hold history, oldest first.
/// - `newMessages` hold messages seen after history was loaded (from the log or
///   from a send response), in arrival order.
/// - `pendingMessages` hold the optimistic outbox, in send order.
/// - `deletedMessages` hold ids that must never render even if a stale view
///   arrives.
/// - `items` is `past + new + pending`, filtered through `deletedMessages`, plus
///   error rows.
///
/// ## Concurrency
///
/// This is an `actor`: a conversation's state is mutated from the send path, the
/// reaction path, the history fetch and the log-sync ingest, all of which can
/// interleave. Serializing them is what keeps a log event from racing a send
/// reconciliation.
public actor ConversationModel {
  /// The conversation id.
  public let convoId: String
  /// The signed-in account's DID, used for the optimistic echo's sender.
  public let senderDid: String
  private let client: any ChatXrpc
  private let clock: @Sendable () -> Date

  /// History, oldest first.
  private var pastMessages: [String: ConvoMessage] = [:]
  /// History order, so `params`-less rendering is stable.
  private var pastOrder: [String] = []
  /// Messages seen after history, in arrival order.
  private var newMessages: [String: ConvoMessage] = [:]
  private var newOrder: [String] = []
  /// The optimistic outbox, in send order.
  private var pendingMessages: [PendingMessage] = []
  /// Ids that must not render, even from a stale view.
  private var deletedMessages: Set<String> = []
  /// The pagination position for history, mirroring RN's `oldestRev` tri-state.
  ///
  /// RN uses `undefined` (not yet fetched), a string (more pages), and `null`
  /// (history complete). An explicit enum keeps the three apart, which a
  /// `String??` does not do legibly.
  enum HistoryCursor: Sendable, Equatable {
    /// No page has been fetched yet; the first fetch reads the newest page.
    case unstarted
    /// Fetch from this cursor for the next older page.
    case at(String)
    /// Every page has been read.
    case complete
  }

  /// The history pagination position. RN's `oldestRev`, made explicit.
  private var history: HistoryCursor = .unstarted

  /// The outbox id counter. RN uses `nanoid`; a monotonic counter is
  /// deterministic, which is what tests want.
  private var pendingCounter = 0

  private var isFetchingHistory = false
  private var historyFailed = false
  private var pendingFailure: SendFailure?
  private var isProcessingPending = false

  private var convo: Chat.Bsky.ConvoDefs_ConvoView?

  /// Creates a conversation model.
  ///
  /// - Parameters:
  ///   - convoId: the conversation.
  ///   - client: the chat transport.
  ///   - senderDid: the signed-in DID.
  ///   - convo: optional placeholder convo, so the header can render before the
  ///     first fetch resolves.
  ///   - clock: injectable time source, for deterministic echo timestamps.
  public init(
    convoId: String, client: any ChatXrpc, senderDid: String,
    convo: Chat.Bsky.ConvoDefs_ConvoView? = nil,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.convoId = convoId
    self.client = client
    self.senderDid = senderDid
    self.convo = convo
    self.clock = clock
  }

  // MARK: - Reading

  /// The current state snapshot.
  public func state() -> ConversationState {
    ConversationState(
      convo: convo,
      items: buildItems(),
      isFetchingHistory: isFetchingHistory,
      hasAllHistory: history == .complete,
      pendingMessageFailure: pendingFailure,
      historyFailed: historyFailed)
  }

  /// The rendered items.
  public func items() -> [ConvoItem] { buildItems() }

  /// The current convo view.
  public func convoView() -> Chat.Bsky.ConvoDefs_ConvoView? { convo }

  /// Sets the convo view, e.g. after a metadata mutation or a fetch.
  public func setConvoView(_ view: Chat.Bsky.ConvoDefs_ConvoView) {
    convo = view
  }

  /// Applies a mutation to the convo view, when one is held.
  public func updateConvoView(
    _ transform: @Sendable (Chat.Bsky.ConvoDefs_ConvoView) -> Chat.Bsky.ConvoDefs_ConvoView
  ) {
    guard let convo else { return }
    self.convo = transform(convo)
  }

  /// The number of pending messages in the outbox.
  public var pendingCount: Int { pendingMessages.count }

  /// True when the pending queue is in a failed state.
  public var hasPendingFailure: Bool { pendingFailure != nil }

  /// True when `messageId` is in the deleted set.
  public func isDeleted(_ messageId: String) -> Bool { deletedMessages.contains(messageId) }

  // MARK: - History

  /// Fetches one page of older history.
  ///
  /// Port of `fetchMessageHistory`. The cursor is trusted for pagination: a
  /// short page does not mean the end, because the server pages raw rows but
  /// strips deleted messages from the response.
  ///
  /// - Parameters:
  ///   - limit: page size.
  ///   - reset: discard held history and start from the newest page.
  @discardableResult
  public func fetchMessageHistory(
    limit: Int = MessagesConstants.messageHistoryLimit, reset: Bool = false
  ) async throws -> [ConvoItem] {
    if reset {
      pastMessages.removeAll()
      pastOrder.removeAll()
      history = .unstarted
      historyFailed = false
    }
    guard history != .complete, !isFetchingHistory, !historyFailed else {
      return buildItems()
    }

    isFetchingHistory = true
    defer { isFetchingHistory = false }

    let cursor: String?
    if case .at(let value) = history { cursor = value } else { cursor = nil }
    do {
      let page = try await client.getMessages(
        convoId: convoId, limit: limit, cursor: cursor)
      history = page.cursor.map { HistoryCursor.at($0) } ?? .complete

      for message in page.messages where !message.isUnknown {
        guard let id = message.id else { continue }
        // A message already in `newMessages` was admitted by log ingest; the
        // server wins on ordering, so overwrite and re-home it in the history.
        if newMessages.removeValue(forKey: id) != nil {
          newOrder.removeAll { $0 == id }
        }
        if pastMessages[id] == nil { pastOrder.insert(id, at: 0) }
        pastMessages[id] = message
      }
      historyFailed = false
    } catch {
      historyFailed = true
      throw error
    }
    return buildItems()
  }

  // MARK: - Sending

  /// Queues a message for sending and starts the outbox drain.
  ///
  /// Port of `sendMessage`. An empty message with no embed is ignored. A send
  /// into a `request` convo optimistically flips it to `accepted`, matching RN.
  ///
  /// - Parameter message: the message input.
  /// - Returns: the pending entry's id, or `nil` when the message was ignored.
  @discardableResult
  public func sendMessage(_ message: Chat.Bsky.ConvoDefs_MessageInput) -> String? {
    if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      message.embed == nil
    {
      return nil
    }

    pendingCounter += 1
    let tempId = "pending-\(pendingCounter)"
    pendingFailure = nil
    pendingMessages.append(
      PendingMessage(id: tempId, message: message))

    if convo?.status == .request {
      updateConvoView { view in
        var copy = view
        copy.status = .accepted
        return copy
      }
    }

    if !isProcessingPending {
      Task { await self.processPendingMessages() }
    }
    return tempId
  }

  /// Drains the outbox in order, one `sendMessage` per pending entry.
  ///
  /// Port of `processPendingMessages`: the first success appends the returned
  /// message view to `newMessages` and keeps draining; the first failure marks
  /// the whole queue failed and stops.
  public func processPendingMessages() async {
    if isProcessingPending { return }
    isProcessingPending = true
    defer { isProcessingPending = false }

    while let next = pendingMessages.first {
      if pendingFailure != nil { return }
      do {
        let response = try await client.sendMessage(
          convoId: convoId, message: next.message)
        pendingMessages.removeFirst()
        // Admit as soon as a real id exists, so the later log event replaces it
        // in situ rather than appending a duplicate.
        admitNew(.message(response))
      } catch {
        handleSendFailure(error)
        return
      }
    }
  }

  /// Retries a failed outbox as one batch.
  ///
  /// Port of `batchRetryPendingMessages`, which the RN agent runs when the
  /// firehose reconnects. Only a `recoverable` failure is retried.
  @discardableResult
  public func batchRetryPendingMessages() async -> Bool {
    guard pendingFailure == .recoverable, !pendingMessages.isEmpty else { return false }

    pendingFailure = nil
    do {
      let items = try await client.sendMessageBatch(
        items: pendingMessages.map { (convoId: convoId, message: $0.message) })
      for view in items {
        admitNew(.message(view))
      }
      pendingMessages.removeAll()
      return true
    } catch {
      handleSendFailure(error)
      return false
    }
  }

  /// Classifies a send failure and, for a recoverable one, keeps the queue.
  ///
  /// Port of `handleSendMessageFailure`. `NETWORK_FAILURE_STATUSES` are
  /// recoverable; everything else marks the queue unrecoverable.
  private func handleSendFailure(_ error: any Error) {
    if let xrpc = error as? XrpcErrorLike {
      pendingFailure =
        MessagesConstants.networkFailureStatuses.contains(xrpc.status)
        ? .recoverable : .unrecoverable
    } else {
      pendingFailure = .unrecoverable
    }
  }

  // MARK: - Reactions

  /// Adds an emoji reaction, optimistically.
  ///
  /// Port of `addReaction`. The reaction must be exactly one grapheme, the
  /// sender may hold at most five distinct reactions on a message, and adding a
  /// duplicate is a no-op.
  ///
  /// - Throws: ``ConvoReactionError`` when the input is invalid or the server
  ///   rejects the call. The optimistic update is rolled back on failure.
  public func addReaction(messageId: String, emoji: String) async throws {
    guard MessagesReaction.isValid(emoji) else {
      throw ConvoReactionError.invalidEmoji(emoji)
    }

    let snapshot = reactionTarget(messageId)
    if let target = snapshot, target.messageView != nil {
      let mine = target.reactions.filter { $0.sender.did.rawValue == senderDid }
      if mine.contains(where: { $0.value == emoji }) {
        return
      }
      if mine.count >= MessagesConstants.maxReactionsPerSender {
        throw ConvoReactionError.tooManyReactions
      }
      writeMessage(
        id: messageId,
        with: appendReaction(
          target, value: emoji, senderDid: senderDid, at: clock()))
    }

    do {
      let updated = try await client.addReaction(
        convoId: convoId, messageId: messageId, value: emoji)
      writeMessage(id: messageId, with: .message(updated))
    } catch {
      if let snapshot { writeMessage(id: messageId, with: snapshot) }
      throw error
    }
  }

  /// Removes an emoji reaction, optimistically.
  ///
  /// Port of `removeReaction`. The optimistic update is rolled back on failure.
  public func removeReaction(messageId: String, emoji: String) async throws {
    let snapshot = reactionTarget(messageId)
    if let target = snapshot, target.messageView != nil {
      writeMessage(
        id: messageId,
        with: removeReaction(target, value: emoji, senderDid: senderDid))
    }

    do {
      let updated = try await client.removeReaction(
        convoId: convoId, messageId: messageId, value: emoji)
      writeMessage(id: messageId, with: .message(updated))
    } catch {
      if let snapshot { writeMessage(id: messageId, with: snapshot) }
      throw error
    }
  }

  /// The current view of a message that can carry reactions.
  private func reactionTarget(_ messageId: String) -> ConvoMessage? {
    if let past = pastMessages[messageId] { return past }
    return newMessages[messageId]
  }

  /// Writes a message view back into whichever collection holds it.
  private func writeMessage(id: String, with message: ConvoMessage) {
    if pastMessages[id] != nil {
      pastMessages[id] = message
    } else if newMessages[id] != nil {
      newMessages[id] = message
    }
  }

  private func appendReaction(
    _ message: ConvoMessage, value: String, senderDid: String, at date: Date
  ) -> ConvoMessage {
    guard case .message(let view) = message else { return message }
    var copy = view
    let reaction = Chat.Bsky.ConvoDefs_ReactionView(
      createdAt: FormatString<Date>(
        rawValue: MessagesDate.datetimeString(date)),
      sender: Chat.Bsky.ConvoDefs_ReactionViewSender(
        did: FormatString<SwiftAtproto.DID>(rawValue: senderDid)),
      value: value)
    copy.reactions = (view.reactions ?? []) + [reaction]
    return .message(copy)
  }

  private func removeReaction(
    _ message: ConvoMessage, value: String, senderDid: String
  ) -> ConvoMessage {
    guard case .message(let view) = message else { return message }
    var copy = view
    copy.reactions = (view.reactions ?? []).filter {
      !($0.value == value && $0.sender.did.rawValue == senderDid)
    }
    return .message(copy)
  }

  // MARK: - Read state, mute, delete

  /// Marks the conversation read up to `messageId`.
  ///
  /// Port of `useMarkAsReadMutation`'s call plus the convo-row reset: the
  /// returned convo view is stored and the local unread count is zeroed.
  @discardableResult
  public func updateRead(
    messageId: String? = nil
  ) async throws
    -> Chat.Bsky.ConvoDefs_ConvoView
  {
    let view = try await client.updateRead(convoId: convoId, messageId: messageId)
    convo = view
    return view
  }

  /// Mutes or unmutes the conversation.
  ///
  /// Port of `useMuteConvo`: the local view flips first and rolls back on error.
  @discardableResult
  public func setMuted(_ muted: Bool) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
    let previous = convo
    updateConvoView { view in
      var copy = view
      copy.muted = muted
      return copy
    }
    do {
      let view =
        muted
        ? try await client.muteConvo(convoId: convoId)
        : try await client.unmuteConvo(convoId: convoId)
      convo = view
      return view
    } catch {
      convo = previous
      throw error
    }
  }

  /// Leaves the conversation.
  ///
  /// The local convo is dropped optimistically; a failure restores it.
  @discardableResult
  public func leaveConvo() async throws -> ConvoLeaveResult {
    let previous = convo
    convo = nil
    do {
      return try await client.leaveConvo(convoId: convoId)
    } catch {
      convo = previous
      throw error
    }
  }

  /// Deletes a message for this account, optimistically.
  ///
  /// Port of `deleteMessage`. The id goes into the deleted set *before* the
  /// request, so the row disappears immediately and stays gone even if a stale
  /// view arrives; the set is the source of truth, so no rollback is needed.
  public func deleteMessage(_ messageId: String) async throws {
    deletedMessages.insert(messageId)
    _ = try await client.deleteMessageForSelf(convoId: convoId, messageId: messageId)
  }

  // MARK: - Log ingest

  /// Applies a batch of log events for this conversation.
  ///
  /// Port of `ingestFirehose`. Events are applied in order and the newest `rev`
  /// is recorded on the convo view. Tolerated events (group, unknown) are
  /// skipped.
  ///
  /// - Parameter events: the batch, oldest first.
  /// - Returns: true when anything rendered changed.
  @discardableResult
  public func ingest(_ events: [ChatLogEvent]) -> Bool {
    var changed = false
    for event in events where !event.isTolerated {
      // RN subscribes per convo (`events.on(..., {convoId})`), so an event for
      // another convo never reaches this model. Filtering here keeps the model
      // correct when a caller hands it an unfiltered batch.
      if let eventConvo = event.convoId, eventConvo != convoId { continue }
      changed = apply(event) || changed
    }
    return changed
  }

  /// Applies one event to the model.
  private func apply(_ event: ChatLogEvent) -> Bool {
    switch event {
    case .createMessage(let rev, _, let message, let relatedProfiles):
      _ = relatedProfiles
      guard let id = message.id else { return false }
      if newMessages[id] != nil {
        // Already admitted by our own send; replace and re-insert so the order
        // follows the log rather than client arrival.
        newMessages.removeValue(forKey: id)
        newOrder.removeAll { $0 == id }
      }
      newMessages[id] = message
      newOrder.append(id)
      bumpRev(rev)
      return true

    case .deleteMessage(let rev, _, let message):
      guard let id = message.id else { return false }
      pastMessages.removeValue(forKey: id)
      pastOrder.removeAll { $0 == id }
      newMessages.removeValue(forKey: id)
      newOrder.removeAll { $0 == id }
      deletedMessages.insert(id)
      bumpRev(rev)
      return true

    case .addReaction(let rev, _, let message, _),
      .removeReaction(let rev, _, let message, _):
      guard let id = message.id, message.messageView != nil else { return false }
      // Only touch messages we already hold; an unseen message's reaction is
      // carried by its own create event.
      if pastMessages[id] != nil || newMessages[id] != nil {
        writeMessage(id: id, with: message)
        bumpRev(rev)
        return true
      }
      return false

    case .readConvo(let rev, _, _), .readMessage(let rev, _, _):
      bumpRev(rev)
      updateConvoView { view in
        var copy = view
        copy.unreadCount = 0
        copy.rev = rev
        return copy
      }
      return true

    case .acceptConvo(let e):
      bumpRev(e.rev)
      updateConvoView { view in
        var copy = view
        copy.status = .accepted
        copy.rev = e.rev
        return copy
      }
      return true

    case .muteConvo(let e):
      bumpRev(e.rev)
      updateConvoView { view in
        var copy = view
        copy.muted = true
        copy.rev = e.rev
        return copy
      }
      return true

    case .unmuteConvo(let e):
      bumpRev(e.rev)
      updateConvoView { view in
        var copy = view
        copy.muted = false
        copy.rev = e.rev
        return copy
      }
      return true

    case .beginConvo(let e), .leaveConvo(let e):
      bumpRev(e.rev)
      return false

    case .groupEvent, .other:
      return false
    }
  }

  /// Records the newest rev seen, when it is newer than the held one.
  private func bumpRev(_ rev: String) {
    guard var view = convo else { return }
    if rev > view.rev {
      view.rev = rev
      convo = view
    }
  }

  /// Admits a message into `newMessages`. Port of the send-side insert.
  private func admitNew(_ message: ConvoMessage) {
    guard let id = message.id else { return }
    newMessages[id] = message
    newOrder.append(id)
  }

  // MARK: - Item assembly

  /// Builds the rendered list: past, then new, then pending, then errors,
  /// filtered through the deleted set. Port of `getItems`.
  private func buildItems() -> [ConvoItem] {
    var items: [ConvoItem] = []

    for id in pastOrder {
      guard let message = pastMessages[id] else { continue }
      items.append(item(for: message, fromHistory: true))
    }

    if historyFailed {
      items.append(.error(code: .historyFailed))
    }

    for id in newOrder {
      guard let message = newMessages[id] else { continue }
      items.append(item(for: message, fromHistory: false))
    }

    for pending in pendingMessages {
      items.append(
        .pendingMessage(
          PendingMessage(
            id: pending.id, message: pending.message,
            failed: pendingFailure != nil)))
    }

    if pendingFailure != nil {
      items.append(.error(code: .firehoseFailed))
    }

    return items.filter { item in
      guard let id = item.messageId else { return true }
      return !deletedMessages.contains(id)
    }
  }

  private func item(for message: ConvoMessage, fromHistory: Bool) -> ConvoItem {
    switch message {
    case .message(let view):
      // A message that quotes the deleted one keeps rendering a tombstone.
      if case .convoDefsMessageView(let replyTo) = view.replyTo,
        deletedMessages.contains(replyTo.id)
      {
        var copy = view
        copy.replyTo = .convoDefsDeletedMessageView(ConvoMessage.tombstone(replyTo))
        return .message(copy)
      }
      return .message(view)
    case .deleted(let view): return .deletedMessage(view)
    case .system(let view): return .systemMessage(view)
    case .other: return .error(code: fromHistory ? .historyFailed : .firehoseFailed)
    }
  }
}

/// Reaction-input validation.
public enum MessagesReaction {
  /// The maximum wire length of a reaction value, from the lexicon
  /// (`maxLength: 64`).
  public static let maxLength = 64

  /// True when `value` is a single grapheme cluster, the lexicon's
  /// `minGraphemes: 1, maxGraphemes: 1` rule.
  ///
  /// Unicode grapheme segmentation is what makes a multi-scalar emoji (a flag,
  /// a skin-toned hand, a ZWJ family) count as one.
  public static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maxLength else { return false }
    return value.count == 1
  }
}

/// Errors the reaction flow surfaces.
public enum ConvoReactionError: Error, Sendable, Hashable {
  /// The value was not a single grapheme.
  case invalidEmoji(String)
  /// The sender already holds ``MessagesConstants/maxReactionsPerSender``
  /// reactions on this message.
  case tooManyReactions
}

/// The status-carrying slice of an XRPC error, so the send path can classify a
/// failure without depending on the concrete error type.
public protocol XrpcErrorLike: Error {
  /// The HTTP status, or a negative value for a transport-level failure.
  var status: Int { get }
}

extension XrpcError: XrpcErrorLike {}
