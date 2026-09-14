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
  let client: any ChatXrpc
  let now: @Sendable () -> Date

  /// History, oldest first.
  var pastMessages: [String: ConvoMessage] = [:]
  /// History order, so `params`-less rendering is stable.
  var pastOrder: [String] = []
  /// Messages seen after history, in arrival order.
  var newMessages: [String: ConvoMessage] = [:]
  var newOrder: [String] = []
  /// The optimistic outbox, in send order.
  var pendingMessages: [PendingMessage] = []
  /// Ids that must not render, even from a stale view.
  var deletedMessages: Set<String> = []
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
  var history: HistoryCursor = .unstarted

  /// The outbox id counter. RN uses `nanoid`; a monotonic counter is
  /// deterministic, which is what tests want.
  var pendingCounter = 0

  var isFetchingHistory = false
  var historyFailed = false
  var pendingFailure: SendFailure?
  var isProcessingPending = false

  var convo: Chat.Bsky.ConvoDefs_ConvoView?

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
    self.now = clock
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
    let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty, message.embed == nil {
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

  // MARK: - Read state, mute, delete

  /// Marks the conversation read up to `messageId`.
  ///
  /// Port of `useMarkAsReadMutation`'s call plus the convo-row reset: the
  /// returned convo view is stored and the local unread count is zeroed.
  @discardableResult
  public func updateRead(
    messageId: String? = nil
  ) async throws -> Chat.Bsky.ConvoDefs_ConvoView {
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
      applyConvoChange(rev: rev) { $0.unreadCount = 0 }
      return true

    case .acceptConvo(let e):
      applyConvoChange(rev: e.rev) { $0.status = .accepted }
      return true

    case .muteConvo(let e):
      applyConvoChange(rev: e.rev) { $0.muted = true }
      return true

    case .unmuteConvo(let e):
      applyConvoChange(rev: e.rev) { $0.muted = false }
      return true

    case .beginConvo(let e), .leaveConvo(let e):
      bumpRev(e.rev)
      return false

    case .groupEvent, .other:
      return false
    }
  }

  /// Bumps the convo view's rev and applies `change` to it.
  private func applyConvoChange(
    rev: String, _ change: @Sendable (inout Chat.Bsky.ConvoDefs_ConvoView) -> Void
  ) {
    bumpRev(rev)
    updateConvoView { view in
      var copy = view
      copy.rev = rev
      change(&copy)
      return copy
    }
  }

  /// Records the newest rev seen, when it is newer than the held one.
  func bumpRev(_ rev: String) {
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
}

/// Reaction-input validation.
extension XrpcError: XrpcErrorLike {}
