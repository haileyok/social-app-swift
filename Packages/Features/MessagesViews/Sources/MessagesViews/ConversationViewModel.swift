import Foundation
import Lexicons
import MessagesLogic
import Observation

/// The SwiftUI-facing adapter over ``ConversationModel``.
///
/// `ConversationModel` is an actor holding the history, the outbox, reactions and
/// read state. This type is the bridge to SwiftUI: it owns the rendered rows and
/// the composer's draft text, and republishes the model's snapshot after every
/// awaited call. Every decision - the item order, the pending echo, the send
/// classification, the reaction rules - still belongs to the model; the view
/// model re-derives none of it.
@MainActor
@Observable
public final class ConversationViewModel {
  /// The rendered rows, with date separators.
  public private(set) var rows: [ConversationRow] = []
  /// The conversation view, once loaded (drives the title and mute state).
  public private(set) var convo: Chat.Bsky.ConvoDefs_ConvoView?
  /// True while an older page is in flight.
  public private(set) var isFetchingHistory = false
  /// True when every older page has been read.
  public private(set) var hasAllHistory = false
  /// The send failure, if the outbox is stuck.
  public private(set) var sendFailure: SendFailure?
  /// True when history fetching failed and a retry row is showing.
  public private(set) var historyFailed = false
  /// The composer draft. The view owns the text; the model never sees it until
  /// send.
  public var draft = ""

  /// The model this adapter renders.
  public let model: ConversationModel
  /// The signed-in DID, so a bubble can tell "mine" from "theirs".
  public let currentAccountDid: String

  private var hasLoaded = false

  /// Creates an adapter over a conversation model.
  public init(model: ConversationModel, currentAccountDid: String) {
    self.model = model
    self.currentAccountDid = currentAccountDid
  }

  /// The conversation's title: the partner's name, or a fallback.
  public var title: String {
    guard let convo else { return MessagesCopy.conversationFallbackTitle }
    let partner =
      convo.members.first { $0.did.rawValue != currentAccountDid } ?? convo.members.first
    guard let partner else { return MessagesCopy.conversationFallbackTitle }
    let name = partner.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return name?.isEmpty == false ? name! : partner.handle.rawValue
  }

  /// The conversation partner's avatar URL, for the header.
  public var partnerAvatarURL: String? {
    let partner =
      convo?.members.first { $0.did.rawValue != currentAccountDid } ?? convo?.members.first
    return partner?.avatar?.rawValue
  }

  /// The direct conversation partner's DID, used by profile navigation.
  public var partnerDid: String? {
    convo?.members.first { $0.did.rawValue != currentAccountDid }?.did.rawValue
  }

  /// Whether the conversation is muted.
  public var isMuted: Bool { convo?.muted ?? false }

  /// True when a message send is available (matches the composer's enable rule:
  /// non-empty text).
  public var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: - Loading

  /// Loads the conversation view and the first page of history.
  public func loadIfNeeded() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    // The convo view is seeded by the caller (from the inbox row's precache);
    // the model already holds it, so the first refresh renders the header before
    // the history page resolves.
    await refresh()
    await loadHistory(reset: true)
  }

  /// Re-reads the model's snapshot into the rendered rows.
  public func refresh() async {
    let state = await model.state()
    convo = state.convo
    sendFailure = state.pendingMessageFailure
    historyFailed = state.historyFailed
    isFetchingHistory = state.isFetchingHistory
    hasAllHistory = state.hasAllHistory
    rows = ConversationRow.build(state.items)
  }

  /// Fetches the newest page of history (or older pages).
  ///
  /// - Parameter reset: discard held history and start from the newest page.
  public func loadHistory(reset: Bool = false) async {
    do {
      try await model.fetchMessageHistory(reset: reset)
    } catch {
      // The model records `historyFailed`; the row renders from `refresh()`.
    }
    await refresh()
  }

  // MARK: - Sending

  /// Queues the draft and starts the outbox drain.
  public func send() async {
    let text = draft
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    draft = ""
    let tempId = await model.sendMessage(Chat.Bsky.ConvoDefs_MessageInput(text: text))
    if tempId != nil {
      // `sendMessage` queues and starts the drain itself; awaiting the drain
      // again is a no-op when it is already in flight, and guarantees the
      // optimistic echo is reconciled before the rows are republished.
      await model.processPendingMessages()
    }
    await refresh()
  }

  /// Sends explicit text, bypassing the composer's draft.
  ///
  /// The composer calls ``send()``; this is the programmatic entry, used by the
  /// fixture surfaces to script a conversation and by a caller that already has
  /// the text. It is the same path either way.
  public func send(_ text: String) async {
    draft = text
    await send()
  }

  /// Retries a failed outbox as one batch.
  public func retrySend() async {
    await model.batchRetryPendingMessages()
    await refresh()
  }

  // MARK: - Reactions

  /// Adds an emoji reaction to a message.
  public func addReaction(messageId: String, emoji: String) async {
    try? await model.addReaction(messageId: messageId, emoji: emoji)
    await refresh()
  }

  /// Removes an emoji reaction from a message.
  public func removeReaction(messageId: String, emoji: String) async {
    try? await model.removeReaction(messageId: messageId, emoji: emoji)
    await refresh()
  }

  /// Toggles one emoji reaction by the signed-in account on a message.
  public func toggleReaction(messageId: String, emoji: String, mine: Bool) async {
    if mine {
      await removeReaction(messageId: messageId, emoji: emoji)
    } else {
      await addReaction(messageId: messageId, emoji: emoji)
    }
  }

  // MARK: - Read state and mute

  /// Marks the conversation read.
  public func markRead() async {
    _ = try? await model.updateRead()
    await refresh()
  }

  /// Mutes or unmutes the conversation.
  public func setMuted(_ muted: Bool) async {
    _ = try? await model.setMuted(muted)
    await refresh()
  }

  /// Leaves the conversation, returning whether the server confirmed removal.
  public func leaveConversation() async -> Bool {
    do {
      _ = try await model.leaveConvo()
      await refresh()
      return true
    } catch {
      await refresh()
      return false
    }
  }

  // MARK: - Log ingest

  /// Applies a batch of log events, then republishes.
  public func ingest(_ events: [ChatLogEvent]) async {
    if await model.ingest(events) {
      await refresh()
    }
  }
}
