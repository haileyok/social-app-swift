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
/// decoding, which a protocol-level fake would bypass. The per-procedure
/// handlers live in `FakeChatServer+Routes.swift`.
///
/// ## State
///
/// The server holds convos, each with an ordered message log keyed by `rev`.
/// `rev`s are monotonically increasing fixed-width numeric strings, so the
/// string `>` comparison `LogSync` uses behaves the way the real service's does.
/// The log cursor is the newest rev in the whole store, matching `getLog`'s
/// contract.
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

  let lock = NSLock()

  private var _requests: [Request] = []
  private var _failures: [String: Failure] = [:]

  /// Convos by id.
  var convos: [String: Chat.Bsky.ConvoDefs_ConvoView] = [:]
  /// Convo ids in insertion order, so listing is stable.
  var convoOrder: [String] = []
  /// Messages by convo id, oldest first.
  var messages: [String: [Chat.Bsky.ConvoDefs_MessageView]] = [:]
  /// Deleted message ids by convo id.
  var deleted: [String: Set<String>] = [:]
  /// The full log, oldest first, as raw JSON objects keyed by rev.
  var log: [(rev: String, json: [String: Any])] = []
  /// Unread counts the server reports.
  var unread = (accepted: 0, request: 0)
  /// When set, `getMessages` returns this cursor regardless of the page walk.
  var forcedMessageCursor: String?
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

  /// The failure programmed for `procedure`, if any.
  func failure(for procedure: String) -> Failure? {
    lock.withLock { _failures[procedure] }
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
      view.kind =
        group ? .convoDefsGroupConvo(Self.groupConvo()) : .convoDefsDirectConvo(.init())
      convos[id] = view
      if !convoOrder.contains(id) { convoOrder.append(id) }
      return view
    }
  }

  /// The convo view currently held for `id`.
  func convo(_ id: String) -> Chat.Bsky.ConvoDefs_ConvoView? {
    lock.withLock { convos[id] }
  }

  /// Sets the server-reported unread counts.
  func setUnreadCounts(accepted: Int, request: Int) {
    lock.withLock { unread = (accepted, request) }
  }

  /// Forces `getMessages` to return `cursor` after any page, to model the server
  /// stripping deleted rows from a full page.
  func setForcedMessageCursor(_ cursor: String?) {
    lock.withLock { forcedMessageCursor = cursor }
  }

  /// Appends a message from `sender` to a convo, emits a `logCreateMessage` and
  /// bumps the convo's last-message/rev. Returns the created message.
  @discardableResult
  func addMessage(
    convoId: String, text: String, sender: String,
    sentAt: String = "2026-08-31T00:00:00.000Z"
  ) -> Chat.Bsky.ConvoDefs_MessageView {
    lock.withLock {
      appendMessageLocked(convoId: convoId, text: text, sender: sender, sentAt: sentAt)
    }
  }

  /// Appends a message from the convo's first member. Used by the send routes.
  func appendMessage(convoId: String, text: String) -> Chat.Bsky.ConvoDefs_MessageView {
    lock.withLock {
      let sender = convos[convoId]?.members.first?.did.rawValue ?? ""
      return appendMessageLocked(convoId: convoId, text: text, sender: sender)
    }
  }

  /// The locked body shared by both append entry points.
  private func appendMessageLocked(
    convoId: String, text: String, sender: String,
    sentAt: String = "2026-08-31T00:00:00.000Z"
  ) -> Chat.Bsky.ConvoDefs_MessageView {
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

    if let failure = failure(for: procedure) {
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

  // MARK: - Encoding

  func json(_ object: [String: Any]) -> HTTPResponse {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"], body: data)
  }

  func errorResponse(status: Int, error code: String, message: String) -> HTTPResponse {
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
  /// The generated `MessageView` does not carry `$type` on its own (it is a
  /// plain ref), but it appears inside `$type`-discriminated unions on the wire
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

  static func jsonObject(_ body: Data?) -> [String: Any]? {
    guard let body else { return nil }
    return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
  }

  /// True when a convo's kind satisfies a list `kind` filter.
  static func matchesKind(_ convo: Chat.Bsky.ConvoDefs_ConvoView, kind: String) -> Bool {
    let isGroup =
      convo.kind.map { if case .convoDefsGroupConvo = $0 { return true } else { return false } }
      ?? false
    if kind == "direct" { return !isGroup }
    if kind == "group" { return isGroup }
    return true
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
  func nextRev() -> String {
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
