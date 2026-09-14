import Foundation
import Lexicons
import QueryStore

/// Applies chat log events to the conversation-list and unread-count caches.
///
/// Port of the `messagesBus.on(...)` handler in
/// `src/state/queries/messages/list-conversations.tsx`. The RN handler reaches
/// into every matching TanStack cache through prefix keys
/// (`setQueriesData({queryKey: [RQKEY_ROOT]})`); QueryStore has no prefix write,
/// so the Swift port enumerates the keys it holds with the same root and writes
/// each one explicitly. That is the one structural difference.
///
/// ## Rev guard
///
/// Every application is guarded on `rev`: a convo whose cached `rev` is already
/// at or past the event's rev is left alone. This is what makes a re-delivered
/// event (or a fetch that raced the log) idempotent, and it is why a log batch
/// can be replayed safely.
///
/// ## Unread arithmetic
///
/// A `createMessage` from someone else on a convo that is not currently open
/// increments `unreadCount`; the same message on the open convo leaves it at
/// zero. `logReadConvo` / `logReadMessage` reset it to zero. Request convos that
/// are accepted move out of the request list into the accepted one.
///
/// ## Deferred refetch
///
/// When an event references a convo the cache does not hold, RN schedules a
/// throttled refetch instead of synthesizing a row (it cannot invent the member
/// profiles). The Swift port records that need in ``needsRefetch`` for the
/// caller to act on, rather than reaching for a timer.
public struct InboxReducer: Sendable {
  /// The store to write.
  public let store: QueryStore
  /// The signed-in account's DID, which decides whether a new message is unread.
  public let currentAccountDid: String?
  /// The conversation currently open, whose messages never count as unread.
  public let currentConvoId: String?

  /// True when an event referenced a convo the cache did not hold. Read (and
  /// cleared) by the caller to schedule a refetch.
  private let refetchFlag: RefetchFlag

  public init(
    store: QueryStore, currentAccountDid: String? = nil, currentConvoId: String? = nil,
    refetchFlag: RefetchFlag = RefetchFlag()
  ) {
    self.store = store
    self.currentAccountDid = currentAccountDid
    self.currentConvoId = currentConvoId
    self.refetchFlag = refetchFlag
  }

  /// Applies a batch of log events.
  ///
  /// - Returns: true when a refetch is warranted (an unknown convo was seen).
  @discardableResult
  public func apply(_ events: [ChatLogEvent]) async -> Bool {
    for event in events {
      await apply(event)
    }
    return await needsRefetch()
  }

  /// True when an event referenced an unknown convo since the last read.
  public func needsRefetch() async -> Bool {
    await refetchFlag.value
  }

  /// Clears the refetch flag.
  public func clearRefetch() async {
    await refetchFlag.clear()
  }

  /// Applies one event.
  private func apply(_ event: ChatLogEvent) async {
    switch event {
    case .createMessage(let rev, let convoId, let message, let relatedProfiles):
      await applyCreateMessage(
        rev: rev, convoId: convoId, message: message, relatedProfiles: relatedProfiles)

    case .deleteMessage(let rev, let convoId, let message):
      // A delete only rewrites `lastMessage` when the deleted message *is* the
      // last message; otherwise the row is untouched.
      await updateConvoInAllLists(convoId: convoId) { convo in
        guard rev > convo.rev else { return convo }
        guard let last = convo.lastMessage, Self.lastMessageId(last) == message.id else {
          return convo
        }
        var copy = convo
        copy.rev = rev
        copy.lastMessage = Self.asLastMessage(message)
        return copy
      }

    case .readConvo(let rev, let convoId, _), .readMessage(let rev, let convoId, _):
      await advance(convoId: convoId, rev: rev) { $0.unreadCount = 0 }

    case .acceptConvo(let e):
      await applyAcceptConvo(e)

    case .muteConvo(let e):
      await advance(convoId: e.convoId, rev: e.rev) { $0.muted = true }

    case .unmuteConvo(let e):
      await advance(convoId: e.convoId, rev: e.rev) { $0.muted = false }

    case .addReaction(let rev, let convoId, _, _),
      .removeReaction(let rev, let convoId, _, _):
      // A reaction updates the message list, not the inbox row's ordering. The
      // row's rev still advances so a later stale event cannot rewind it.
      await advance(convoId: convoId, rev: rev) { _ in }

    case .leaveConvo(let e):
      await removeConvoFromAllLists(convoId: e.convoId)
      await store.remove(MessagesKeys.convo(e.convoId))

    case .beginConvo, .groupEvent, .other:
      // Nothing in the 1:1 inbox reacts to these.
      break
    }
  }

  /// Applies `logCreateMessage`: bump the row to the top of the first page with
  /// the new last message, merge related profiles into the member list, and
  /// increment the unread count when the message is from someone else and the
  /// convo is not open.
  private func applyCreateMessage(
    rev: String, convoId: String, message: ConvoMessage,
    relatedProfiles: [Chat.Bsky.ActorDefs_ProfileViewBasic]
  ) async {
    let existing = await findConvo(convoId)
    guard let existing else {
      // RN cannot synthesize the row (it has no member profiles), so it refetches.
      await refetchFlag.set()
      return
    }
    guard rev > existing.rev else { return }

    var updated = existing
    updated.rev = rev
    updated.lastMessage = Self.asLastMessage(message)

    let known = Set(updated.members.map { $0.did.rawValue })
    let additions = relatedProfiles.filter { !known.contains($0.did.rawValue) }
    updated.members.append(contentsOf: additions)

    let isOtherSendersMessage =
      message.senderDid != nil && message.senderDid != currentAccountDid
    let isCounted = message.messageView != nil || message.isDeleted
    if convoId != currentConvoId, isOtherSendersMessage, isCounted {
      updated.unreadCount += 1
    } else if convoId == currentConvoId {
      updated.unreadCount = 0
    }

    let finalized = updated
    await updateConvoInAllLists(convoId: convoId) { _ in finalized }
  }

  /// Applies `logAcceptConvo`: flip the row to accepted and move it out of every
  /// request list. Port of the `logAcceptConvo` arm.
  private func applyAcceptConvo(_ event: ChatRevEvent) async {
    guard let existing = await findConvo(event.convoId), event.rev > existing.rev else {
      await refetchFlag.set()
      return
    }

    var accepted: Chat.Bsky.ConvoDefs_ConvoView = existing
    accepted.status = .accepted
    accepted.rev = event.rev
    let finalized = accepted

    await updateConvoInAllLists(convoId: event.convoId) { _ in finalized }

    // Request lists drop the convo entirely; the accepted list gains it at the
    // head of page one.
    for key in await store.keys(root: MessagesKeys.convoListRoot)
    where Self.status(of: key) == ConvoStatusFilter.request.rawValue {
      await store.updateQueryData(
        key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self
      ) { data in
        Self.removing(event.convoId, from: data)
      }
    }

    for key in await store.keys(root: MessagesKeys.convoListRoot) {
      let cached = try? await store.payload(
        key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self)
      let alreadyHeld = cached?.items.contains { $0.id == event.convoId } ?? false
      guard alreadyHeld || Self.matches(finalized, key: key) else { continue }
      await store.updateQueryData(
        key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self
      ) { data in
        Self.prepending(finalized, to: data)
      }
    }
  }

  /// Bumps a held convo's rev and applies `change`, guarded on the rev.
  ///
  /// The rev guard is spelled once here: an event at or below the cached rev is
  /// ignored, which is what makes a re-delivered batch idempotent.
  private func advance(
    convoId: String, rev: String,
    _ change: @Sendable (inout Chat.Bsky.ConvoDefs_ConvoView) -> Void
  ) async {
    await updateConvoInAllLists(convoId: convoId) { convo in
      guard rev > convo.rev else { return convo }
      var copy = convo
      copy.rev = rev
      change(&copy)
      return copy
    }
  }

  // MARK: - Store helpers

  /// The status encoded in a convo-list key.
  private static func status(of key: QueryKey) -> String {
    guard key.keyRoot == MessagesKeys.convoListRoot else { return "all" }
    return key.argsText.contains("status: \"") ? parseStatus(key.argsText) : "all"
  }

  /// Extracts the `status:` value from a rendered args description.
  private static func parseStatus(_ argsText: String) -> String {
    guard let range = argsText.range(of: "status: \"") else { return "all" }
    let rest = argsText[range.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return "all" }
    return String(rest[rest.startIndex..<end])
  }

  /// True when a convo satisfies the filters a key encodes. Port of
  /// `convoMatchesQueryKey`, for the 1:1 subset.
  ///
  /// `lockStatus` and the group `kind` filter have no 1:1 meaning: a direct convo
  /// satisfies a nil or `unlocked` lockStatus and never satisfies `group`.
  static func matches(_ convo: Chat.Bsky.ConvoDefs_ConvoView, key: QueryKey) -> Bool {
    let status = Self.status(of: key)
    if status != "all", status != convo.status?.rawValue { return false }
    if key.argsText.contains("readState: \"unread\""), convo.unreadCount == 0 { return false }
    if key.argsText.contains("kind: \"group\"") { return false }
    if key.argsText.contains("kind: \"direct\""), !isDirect(convo) { return false }
    if key.argsText.contains("lockStatus: \"locked"), !isDirect(convo) { return false }
    return true
  }

  /// True for a convo the 1:1 scope keeps. Mirrors `InboxQuery.isDirectConvo`.
  static func isDirect(_ convo: Chat.Bsky.ConvoDefs_ConvoView) -> Bool {
    InboxQuery.isDirectConvo(convo)
  }

  /// The id of a last-message union member.
  static func lastMessageId(_ lastMessage: Chat.Bsky.ConvoDefs_ConvoView_LastMessage) -> String? {
    switch lastMessage {
    case .convoDefsMessageView(let view): view.id
    case .convoDefsDeletedMessageView(let view): view.id
    case .convoDefsSystemMessageView(let view): view.id
    case ._other: nil
    }
  }

  /// Projects a message into the `lastMessage` union position.
  static func asLastMessage(
    _ message: ConvoMessage
  ) -> Chat.Bsky.ConvoDefs_ConvoView_LastMessage? {
    switch message {
    case .message(let view): .convoDefsMessageView(view)
    case .deleted(let view): .convoDefsDeletedMessageView(view)
    case .system(let view): .convoDefsSystemMessageView(view)
    case .other: nil
    }
  }

  /// The first convo with `convoId` held in any list, or the single-convo entry.
  private func findConvo(_ convoId: String) async -> Chat.Bsky.ConvoDefs_ConvoView? {
    let single = try? await store.payload(
      MessagesKeys.convo(convoId), as: Chat.Bsky.ConvoDefs_ConvoView.self)
    if let single {
      return single
    }
    for key in await store.keys(root: MessagesKeys.convoListRoot) {
      guard
        let data = try? await store.payload(
          key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self)
      else { continue }
      if let hit = data.items.first(where: { $0.id == convoId }) { return hit }
    }
    return nil
  }

  /// Rewrites a convo in place everywhere it is held, including the
  /// single-convo entry. Port of `updateConvoInAllLists` / `mutateConvoView`.
  ///
  /// The transform runs once against the first copy found, so every cache gets
  /// the same updated view. An empty result means the convo is not held.
  private func updateConvoInAllLists(
    convoId: String,
    _ transform: @Sendable (Chat.Bsky.ConvoDefs_ConvoView) -> Chat.Bsky.ConvoDefs_ConvoView?
  ) async {
    await store.updateQueryData(
      MessagesKeys.convo(convoId), as: Chat.Bsky.ConvoDefs_ConvoView.self
    ) { convo in
      transform(convo)
    }

    for key in await store.keys(root: MessagesKeys.convoListRoot) {
      await store.updateQueryData(
        key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self
      ) { data in
        var changed = false
        let pages = data.pages.map { page in
          let convos = page.items.map { convo -> Chat.Bsky.ConvoDefs_ConvoView in
            guard convo.id == convoId else { return convo }
            guard let next = transform(convo) else { return convo }
            changed = true
            return next
          }
          return QueryPage(
            items: convos, cursor: page.cursor, requestCursor: page.requestCursor)
        }
        // Return the data unchanged rather than nil when nothing matched:
        // `QueryStore.updateQueryData` treats a nil result as "clear the entry",
        // which would evict a list this event does not concern.
        return changed ? InfiniteQueryData(pages: pages) : data
      }
    }
  }

  /// Removes a convo from every list.
  private func removeConvoFromAllLists(convoId: String) async {
    for key in await store.keys(root: MessagesKeys.convoListRoot) {
      await store.updateQueryData(
        key, as: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>.self
      ) { data in
        Self.removing(convoId, from: data)
      }
    }
  }

  /// `data` with `convoId` dropped from every page, or nil when it was absent.
  static func removing(
    _ convoId: String, from data: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>
  ) -> InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>? {
    guard data.items.contains(where: { $0.id == convoId }) else { return nil }
    let pages = data.pages.map { page in
      QueryPage(
        items: page.items.filter { $0.id != convoId }, cursor: page.cursor,
        requestCursor: page.requestCursor)
    }
    return InfiniteQueryData(pages: pages)
  }

  /// `data` with `convo` at the head of page one and removed elsewhere.
  static func prepending(
    _ convo: Chat.Bsky.ConvoDefs_ConvoView,
    to data: InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView>
  ) -> InfiniteQueryData<Chat.Bsky.ConvoDefs_ConvoView> {
    guard !data.pages.isEmpty else {
      return InfiniteQueryData(pages: [QueryPage(items: [convo], cursor: nil)])
    }
    var pages: [QueryPage<Chat.Bsky.ConvoDefs_ConvoView>] = []
    for (index, page) in data.pages.enumerated() {
      if index == 0 {
        let rest = page.items.filter { $0.id != convo.id }
        pages.append(
          QueryPage(items: [convo] + rest, cursor: page.cursor, requestCursor: page.requestCursor))
      } else {
        pages.append(
          QueryPage(
            items: page.items.filter { $0.id != convo.id }, cursor: page.cursor,
            requestCursor: page.requestCursor))
      }
    }
    return InfiniteQueryData(pages: pages)
  }
}

/// A shared flag recording that an event referenced an unknown convo.
///
/// The reducer is a `Sendable` value and the flag must outlive one call, so it
/// is an actor rather than a field.
public actor RefetchFlag {
  private var flagged = false

  public init() {}

  /// True when set.
  public var value: Bool { flagged }

  /// Sets the flag.
  func set() { flagged = true }

  /// Clears the flag.
  func clear() { flagged = false }
}
