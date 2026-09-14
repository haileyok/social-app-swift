import ATProtoClient
import Foundation
import Lexicons
import MessagesLogic
import SwiftAtproto

/// A fake chat XRPC server.
///
/// The dev-env mock deliberately serves no chat service (`@atproto/dev-env`'s
/// `TestNetwork` has none), so a chat exercising the real `LiveChatXrpc` needs a
/// server. This is one: an ``HTTPTransport`` that routes `/xrpc/chat.bsky.convo.*`
/// to an in-memory chat state, encodes real lexicon JSON, and records every
/// request so a test can assert the exact method, params, body and headers -
/// including the `atproto-proxy: did:web:api.bsky.chat#bsky_chat` routing header
/// that distinguishes the chat client from the appview one.
///
/// It is deliberately *not* a mock object layered under `ChatXrpc`: the point is
/// to exercise `LiveChatXrpc`'s URL building, param encoding, proxy header and
/// decoding, which a protocol-level fake would bypass.
///
/// ## State
///
/// The server holds convos, each with an ordered message log keyed by `rev`.
/// `rev`s are monotonically increasing numeric strings, so the string `>`
/// comparison `LogSync` uses behaves the way the real service's does. The log
/// cursor is the newest rev in the whole store, matching `getLog`'s contract.
final class FakeChatServer: HTTPTransport, @unchecked Sendable {
  /// One recorded request.
  struct Request: Sendable {
    let method: String
    let procedure: String
    let params: [String: [String]]
    let headers: [String: String]
    let body: Data?

    /// The first value of a query parameter.
    func param(_ name: String) -> String? { params[name]?.first }

    /// The JSON body decoded as a dictionary, for asserting exact payloads.
    var json: [String: Any]? {
      guard let body else { return nil }
      return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
  }

  /// A service-level failure to return for one procedure.
  struct Failure: Sendable {
    let status: Int
    let error: String
    let message: String?
  }

  private let lock = NSLock()

  private var _requests: [Request] = []
  private var _failures: [String: Failure] = [:]

  /// Convos by id.
  private var convos: [String: Chat.Bsky.ConvoDefs_ConvoView] = [:]
  /// Convo ids in insertion order, so listing is stable.
  private var convoOrder: [String] = []
  /// Messages by convo id, oldest first.
  private var messages: [String: [Chat.Bsky.ConvoDefs_MessageView]] = [:]
  /// Deleted message ids by convo id.
  private var deleted: [String: Set<String>] = [:]
  /// The full log, oldest first, as raw JSON objects keyed by rev.
  private var log: [(rev: String, json: [String: Any])] = []
  /// Unread counts the server reports.
  private var unread = (accepted: 0, request: 0)
  /// When set, `getMessages` returns this cursor regardless of the page walk.
  /// Used to model the server stripping deleted rows from a full page.
  private var forcedMessageCursor: String?

  /// The rev counter.
  private var revCounter = 0
  /// Message id counter.
  private var messageCounter = 0

  /// Creates an empty server.
  init() {}

  // MARK: - Inspection

  /// Every request received, in order.
  var requests: [Request] { lock.withLock { _requests } }

  /// The requests for one procedure.
  func requests(for procedure: String) -> [Request] {
    requests.filter { $0.procedure == procedure }
  }

  /// The most recent request, if any.
  var lastRequest: Request? { requests.last }

  /// Makes `procedure` fail once per call with `failure`.
  func fail(_ procedure: String, status: Int, error: String, message: String? = nil) {
    lock.withLock {
      _failures[procedure] = Failure(status: status, error: error, message: message)
    }
  }

  /// Clears a programmed failure.
  func clearFailure(_ procedure: String) {
    lock.withLock { _failures.removeValue(forKey: procedure) }
  }

  // MARK: - Seeding

  /// Adds a convo. Returns it for convenience.
  @discardableResult
  func addConvo(
    id: String, members: [String], status: ConvoStatusFilter = .accepted,
    unreadCount: Int = 0, muted: Bool = false, group: Bool = false
  ) -> Chat.Bsky.ConvoDefs_ConvoView {
    lock.withLock {
      var view = Chat.Bsky.ConvoDefs_ConvoView(
        id: id,
        members: members.map(Self.profile),
        muted: muted,
        rev: nextRev(),
        status: status == .accepted
          ? Chat.Bsky.ConvoDefs_ConvoStatus.accepted
          : Chat.Bsky.ConvoDefs_ConvoStatus.request,
        unreadCount: unreadCount)
      view.kind = group ? .convoDefsGroupConvo(Self.groupConvo()) : .convoDefsDirectConvo(.init())
      convos[id] = view
      if !convoOrder.contains(id) { convoOrder.append(id) }
      return view
    }
  }

  /// The convo view currently held for `id`.
  func convo(_ id: String) -> Chat.Bsky.ConvoDefs_ConvoView? {
    lock.withLock { convos[id] }
  }

  /// Forces `getMessages` to return `cursor` after any page, to model the server
  /// stripping deleted rows from a full page.
  func setForcedMessageCursor(_ cursor: String?) {
    lock.withLock { forcedMessageCursor = cursor }
  }

  /// Sets the server-reported unread counts.
  func setUnreadCounts(accepted: Int, request: Int) {
    lock.withLock { unread = (accepted, request) }
  }

  /// Appends a message to a convo, emits a `logCreateMessage` and bumps the
  /// convo's last-message/rev. Returns the created message.
  @discardableResult
  func addMessage(
    convoId: String, text: String, sender: String,
    sentAt: String = "2026-08-31T00:00:00.000Z"
  ) -> Chat.Bsky.ConvoDefs_MessageView {
    lock.withLock {
      let view = Chat.Bsky.ConvoDefs_MessageView(
        id: "msg-\(nextMessageId())",
        rev: nextRev(),
        sender: Chat.Bsky.ConvoDefs_MessageViewSender(
          did: FormatString<SwiftAtproto.DID>(rawValue: sender)),
        sentAt: FormatString<Date>(rawValue: sentAt),
        text: text)
      messages[convoId, default: []].append(view)
      if var convo = convos[convoId] {
        convo.rev = view.rev
        convo.lastMessage = .convoDefsMessageView(view)
        convos[convoId] = convo
      }
      log.append(
        (
          rev: view.rev,
          json: [
            "$type": "chat.bsky.convo.defs#logCreateMessage",
            "rev": view.rev,
            "convoId": convoId,
            "message": Self.encodeUnion(view),
          ]
        ))
      return view
    }
  }

  /// Emits an arbitrary log event from raw JSON, for tolerance tests.
  @discardableResult
  func emitLog(_ json: [String: Any]) -> String {
    lock.withLock {
      let rev = json["rev"] as? String ?? nextRev()
      log.append((rev: rev, json: json))
      return rev
    }
  }

  /// The newest rev the server holds, which is what `getLog` returns as a cursor.
  var headRev: String? { lock.withLock { log.last?.rev } }

  // MARK: - HTTPTransport

  func send(
    method: String, url: String, headers: [String: String], body: Data?
  ) async throws -> HTTPResponse {
    let procedure = Self.procedure(from: url)
    let params = Self.queryParams(from: url)
    lock.withLock {
      _requests.append(
        Request(
          method: method, procedure: procedure, params: params,
          headers: headers, body: body))
    }

    if let failure = lock.withLock({ _failures[procedure] }) {
      let payload: [String: Any] = [
        "error": failure.error,
        "message": failure.message ?? failure.error,
      ]
      return HTTPResponse(
        status: failure.status, headers: ["Content-Type": "application/json"],
        body: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data())
    }

    return handle(procedure: procedure, params: params, body: body)
  }

  // MARK: - Routing

  private func handle(
    procedure: String, params: [String: [String]], body: Data?
  ) -> HTTPResponse {
    do {
      return try route(procedure: procedure, params: params, body: body)
    } catch let service as ServiceError {
      return errorResponse(
        status: service.status, error: service.error, message: service.message)
    } catch {
      return errorResponse(
        status: 500, error: "InternalServerError", message: "\(error)")
    }
  }

  /// A service-level failure raised by a handler.
  struct ServiceError: Error {
    let status: Int
    let error: String
    let message: String
  }

  private func route(
    procedure: String, params: [String: [String]], body: Data?
  ) throws -> HTTPResponse {
    switch procedure {
    case Chat.Bsky.ConvoListConvos.id:
      return json(listConvos(params))
    case Chat.Bsky.ConvoGetConvo.id:
      return json(getConvo(params))
    case Chat.Bsky.ConvoGetMessages.id:
      return json(getMessages(params))
    case Chat.Bsky.ConvoGetLog.id:
      return json(getLog(params))
    case Chat.Bsky.ConvoSendMessage.id:
      return json(try sendMessage(body))
    case Chat.Bsky.ConvoSendMessageBatch.id:
      return json(try sendMessageBatch(body))
    case Chat.Bsky.ConvoAddReaction.id:
      return json(try mutateReaction(body, add: true))
    case Chat.Bsky.ConvoRemoveReaction.id:
      return json(try mutateReaction(body, add: false))
    case Chat.Bsky.ConvoUpdateRead.id:
      return json(try updateRead(body))
    case Chat.Bsky.ConvoUpdateAllRead.id:
      return json(updateAllRead(body))
    case Chat.Bsky.ConvoGetUnreadCounts.id:
      return json(getUnreadCounts())
    case Chat.Bsky.ConvoMuteConvo.id:
      return json(try setMuted(body, muted: true))
    case Chat.Bsky.ConvoUnmuteConvo.id:
      return json(try setMuted(body, muted: false))
    case Chat.Bsky.ConvoLeaveConvo.id:
      return json(try leaveConvo(body))
    case Chat.Bsky.ConvoDeleteMessageForSelf.id:
      return json(try deleteMessageForSelf(body))
    default:
      return errorResponse(
        status: 404, error: "MethodNotImplemented",
        message: "no route for \(procedure)")
    }
  }

  // MARK: - Handlers

  private func listConvos(_ params: [String: [String]]) -> [String: Any] {
    let limit = Int(params["limit"]?.first ?? "50") ?? 50
    let status = params["status"]?.first
    let readState = params["readState"]?.first
    let kind = params["kind"]?.first

    var items: [[String: Any]] = []
    for id in lock.withLock({ convoOrder }) {
      guard let convo = lock.withLock({ convos[id] }) else { continue }
      if let status, (convo.status?.rawValue ?? "accepted") != status { continue }
      if readState == "unread", convo.unreadCount == 0 { continue }
      if let kind {
        let isGroup =
          convo.kind.map { if case .convoDefsGroupConvo = $0 { true } else { false } } ?? false
        if kind == "direct", isGroup { continue }
        if kind == "group", !isGroup { continue }
      }
      items.append(Self.encode(convo))
    }

    // The real service pages with a cursor. This fake pages by offset encoded in
    // the cursor so multi-page tests can drive the walk.
    let offset = Int(params["cursor"]?.first ?? "0") ?? 0
    let page = Array(items.dropFirst(offset).prefix(limit))
    var out: [String: Any] = ["convos": page]
    if offset + page.count < items.count {
      out["cursor"] = "\(offset + page.count)"
    }
    return out
  }

  private func getConvo(_ params: [String: [String]]) -> [String: Any] {
    guard let id = params["convoId"]?.first, let convo = lock.withLock({ convos[id] })
    else {
      return ["convo": NSNull()]
    }
    return ["convo": Self.encode(convo)]
  }

  private func getMessages(_ params: [String: [String]]) -> [String: Any] {
    let convoId = params["convoId"]?.first ?? ""
    let limit = Int(params["limit"]?.first ?? "50") ?? 50
    let all = lock.withLock { messages[convoId] ?? [] }
    let deletedIds = lock.withLock { deleted[convoId] ?? [] }

    // Newest-first walk, so the cursor semantics match the real service: the
    // returned cursor walks *backwards* through history.
    let offset = Int(params["cursor"]?.first ?? "0") ?? 0
    let reversed = Array(all.reversed())
    let page = Array(reversed.dropFirst(offset).prefix(limit))
    var out: [String: Any] = [
      "messages": page.map { view -> [String: Any] in
        if deletedIds.contains(view.id) {
          return Self.encodeUnion(ConvoMessage.tombstone(view))
        }
        return Self.encodeUnion(view)
      }
    ]
    if let forced = lock.withLock({ forcedMessageCursor }) {
      out["cursor"] = forced
    } else if offset + page.count < reversed.count {
      out["cursor"] = "\(offset + page.count)"
    }
    return out
  }

  private func getLog(_ params: [String: [String]]) -> [String: Any] {
    let since = params["cursor"]?.first
    let (logs, head) = lock.withLock {
      (self.log, self.log.last?.rev)
    }
    let filtered =
      since == nil
      ? logs.map(\.json)
      : logs.filter { $0.rev > since! }.map(\.json)
    var out: [String: Any] = ["logs": filtered]
    if let head { out["cursor"] = head }
    return out
  }

  private func sendMessage(_ body: Data?) throws -> [String: Any] {
    guard let json = Self.jsonObject(body),
      let convoId = json["convoId"] as? String,
      let message = json["message"] as? [String: Any]
    else {
      throw ServiceError(status: 400, error: "InvalidRequest", message: "bad sendMessage input")
    }
    let text = message["text"] as? String ?? ""
    let sender = lock.withLock { convos[convoId]?.members.first?.did.rawValue } ?? ""
    let view = addMessage(convoId: convoId, text: text, sender: sender)
    return Self.encodeUnion(view)
  }

  private func sendMessageBatch(_ body: Data?) throws -> [String: Any] {
    guard let json = Self.jsonObject(body), let items = json["items"] as? [[String: Any]]
    else {
      throw ServiceError(status: 400, error: "InvalidRequest", message: "bad batch input")
    }
    var views: [[String: Any]] = []
    for item in items {
      guard let convoId = item["convoId"] as? String,
        let message = item["message"] as? [String: Any]
      else { continue }
      let text = message["text"] as? String ?? ""
      let sender = lock.withLock { convos[convoId]?.members.first?.did.rawValue } ?? ""
      views.append(Self.encodeUnion(addMessage(convoId: convoId, text: text, sender: sender)))
    }
    return ["items": views]
  }

  private func mutateReaction(_ body: Data?, add: Bool) throws -> [String: Any] {
    guard let json = Self.jsonObject(body),
      let convoId = json["convoId"] as? String,
      let messageId = json["messageId"] as? String,
      let value = json["value"] as? String
    else {
      throw ServiceError(status: 400, error: "InvalidRequest", message: "bad reaction input")
    }
    guard var view = lock.withLock({ messages[convoId]?.first { $0.id == messageId } })
    else {
      throw ServiceError(status: 400, error: "InvalidRequest", message: "no such message")
    }
    let sender = lock.withLock { convos[convoId]?.members.first?.did.rawValue } ?? ""
    let reaction = Chat.Bsky.ConvoDefs_ReactionView(
      createdAt: FormatString<Date>(rawValue: "2026-08-31T00:00:00.000Z"),
      sender: Chat.Bsky.ConvoDefs_ReactionViewSender(
        did: FormatString<SwiftAtproto.DID>(rawValue: sender)),
      value: value)
    var reactions = view.reactions ?? []
    if add {
      reactions.append(reaction)
    } else {
      reactions.removeAll { $0.value == value }
    }
    view.reactions = reactions
    lock.withLock {
      if var list = messages[convoId], let index = list.firstIndex(where: { $0.id == messageId }) {
        list[index] = view
        messages[convoId] = list
      }
    }
    return ["message": Self.encodeUnion(view)]
  }

  private func updateRead(_ body: Data?) throws -> [String: Any] {
    guard let json = Self.jsonObject(body), let convoId = json["convoId"] as? String,
      var convo = lock.withLock({ convos[convoId] })
    else {
      throw ServiceError(status: 400, error: "InvalidConvo", message: "no such convo")
    }
    convo.unreadCount = 0
    convo.rev = lock.withLock { nextRev() }
    lock.withLock { convos[convoId] = convo }
    return ["convo": Self.encode(convo)]
  }

  private func updateAllRead(_ body: Data?) -> [String: Any] {
    let json = Self.jsonObject(body)
    let status = json?["status"] as? String
    var updated = 0
    lock.withLock {
      for id in convoOrder {
        guard var convo = convos[id] else { continue }
        if let status, (convo.status?.rawValue ?? "accepted") != status { continue }
        if convo.unreadCount > 0 {
          convo.unreadCount = 0
          convos[id] = convo
          updated += 1
        }
      }
      unread = (0, status == "request" ? 0 : unread.request)
    }
    return ["updatedCount": updated]
  }

  private func getUnreadCounts() -> [String: Any] {
    let counts = lock.withLock { unread }
    return [
      "unreadAcceptedConvos": counts.accepted,
      "unreadRequestConvos": counts.request,
    ]
  }

  private func setMuted(_ body: Data?, muted: Bool) throws -> [String: Any] {
    guard let json = Self.jsonObject(body), let convoId = json["convoId"] as? String,
      var convo = lock.withLock({ convos[convoId] })
    else {
      throw ServiceError(status: 400, error: "InvalidConvo", message: "no such convo")
    }
    convo.muted = muted
    lock.withLock { convos[convoId] = convo }
    return ["convo": Self.encode(convo)]
  }

  private func leaveConvo(_ body: Data?) throws -> [String: Any] {
    guard let json = Self.jsonObject(body), let convoId = json["convoId"] as? String
    else {
      throw ServiceError(status: 400, error: "InvalidConvo", message: "no such convo")
    }
    let rev: String = lock.withLock {
      convos.removeValue(forKey: convoId)
      convoOrder.removeAll { $0 == convoId }
      return nextRev()
    }
    return ["convoId": convoId, "rev": rev]
  }

  private func deleteMessageForSelf(_ body: Data?) throws -> [String: Any] {
    guard let json = Self.jsonObject(body), let convoId = json["convoId"] as? String,
      let messageId = json["messageId"] as? String,
      let view = lock.withLock({ messages[convoId]?.first { $0.id == messageId } })
    else {
      throw ServiceError(status: 400, error: "InvalidRequest", message: "no such message")
    }
    lock.withLock { deleted[convoId, default: []].insert(messageId) }
    return [
      "$type": "chat.bsky.convo.defs#deletedMessageView",
      "id": view.id,
      "rev": view.rev,
      "sender": Self.encode(view.sender),
      "sentAt": view.sentAt.rawValue,
    ]
  }

  // MARK: - Encoding

  private func json(_ object: [String: Any]) -> HTTPResponse {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"], body: data)
  }

  private func errorResponse(status: Int, error code: String, message: String) -> HTTPResponse {
    let data =
      (try? JSONSerialization.data(withJSONObject: ["error": code, "message": message]))
      ?? Data()
    return HTTPResponse(
      status: status, headers: ["Content-Type": "application/json"], body: data)
  }

  /// JSON-encodes a generated lexicon value.
  static func encode(_ value: some Encodable) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(value),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
  }

  /// Encodes a message view as a union element, stamping its `$type`.
  ///
  /// The generated `MessageView` does not carry `$type` on its own (it is a plain
  /// ref), but it appears inside `$type`-discriminated unions on the wire
  /// (`getMessages.messages`, `logCreateMessage.message`), so the fake must add
  /// it exactly as the service does.
  static func encodeUnion(_ view: Chat.Bsky.ConvoDefs_MessageView) -> [String: Any] {
    var object = encode(view)
    object["$type"] = "chat.bsky.convo.defs#messageView"
    return object
  }

  /// Encodes a deleted-message view as a union element.
  static func encodeUnion(_ view: Chat.Bsky.ConvoDefs_DeletedMessageView) -> [String: Any] {
    var object = encode(view)
    object["$type"] = "chat.bsky.convo.defs#deletedMessageView"
    return object
  }

  private static func jsonObject(_ body: Data?) -> [String: Any]? {
    guard let body else { return nil }
    return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
  }

  private static func profile(_ did: String) -> Chat.Bsky.ActorDefs_ProfileViewBasic {
    Chat.Bsky.ActorDefs_ProfileViewBasic(
      did: FormatString<SwiftAtproto.DID>(rawValue: did),
      handle: FormatString<SwiftAtproto.Handle>(rawValue: "\(did.suffix(6)).test"))
  }

  /// A minimal group-convo `kind` payload, for tolerance tests.
  static func groupConvo() -> Chat.Bsky.ConvoDefs_GroupConvo {
    Chat.Bsky.ConvoDefs_GroupConvo(
      createdAt: FormatString<Date>(rawValue: "2026-08-31T00:00:00.000Z"),
      lockStatus: .unlocked,
      lockStatusModerationOverride: false,
      memberCount: 3,
      memberLimit: 50,
      name: "group")
  }

  // MARK: - URL parsing

  /// The procedure id from an XRPC URL path.
  static func procedure(from url: String) -> String {
    guard let range = url.range(of: "/xrpc/") else { return "" }
    let rest = url[range.upperBound...]
    if let query = rest.firstIndex(of: "?") {
      return String(rest[rest.startIndex..<query])
    }
    return String(rest)
  }

  /// Decoded query parameters, preserving repeated names.
  static func queryParams(from url: String) -> [String: [String]] {
    guard let mark = url.firstIndex(of: "?"), mark < url.endIndex else { return [:] }
    let query = url[url.index(after: mark)...]
    var out: [String: [String]] = [:]
    for pair in query.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard let name = parts.first.map(String.init) else { continue }
      let raw = parts.count > 1 ? String(parts[1]) : ""
      let value =
        raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
      out[name, default: []].append(value)
    }
    return out
  }

  // MARK: - Internal counters

  /// The next rev, as a fixed-width string.
  ///
  /// Chat revs are fixed-width so a plain string `>` is also a numeric order -
  /// which is exactly what `LogSync` and the inbox rev guard rely on. Padding
  /// keeps the fake faithful past nine events.
  private func nextRev() -> String {
    revCounter += 1
    return String(format: "%010d", revCounter)
  }

  private func nextMessageId() -> Int {
    messageCounter += 1
    return messageCounter
  }
}

extension NSLock {
  /// A synchronous critical section, because `NSLock.lock()` is `noasync`.
  func withLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
