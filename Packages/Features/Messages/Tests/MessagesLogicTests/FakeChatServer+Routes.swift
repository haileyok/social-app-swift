import ATProtoClient
import Foundation
import Lexicons
import MessagesLogic
import SwiftAtproto

/// The fake chat server's request handlers.
///
/// Split from ``FakeChatServer`` so neither file exceeds the repo's file/type
/// length budgets; the handler state stays on the main type, and these
/// extensions mutate it through the same lock.
extension FakeChatServer {

  /// A service-level failure raised by a handler.
  struct ServiceError: Error {
    let status: Int
    let error: String
    let message: String
  }

  func handle(
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

  private func route(
    procedure: String, params: [String: [String]], body: Data?
  ) throws -> HTTPResponse {
    switch procedure {
    case Chat.Bsky.ConvoListConvos.id:
      return json(listConvos(params))
    case Chat.Bsky.ConvoGetConvo.id:
      return json(getConvo(params))
    case Chat.Bsky.ConvoGetConvoAvailability.id:
      return json(getConvoAvailability(params))
    case Chat.Bsky.ConvoGetConvoForMembers.id:
      return json(getConvoForMembers(params))
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
    case Chat.Bsky.ConvoAcceptConvo.id:
      return json(["rev": "accepted-1"])
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

  // MARK: - Query handlers

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
      if let kind, !Self.matchesKind(convo, kind: kind) { continue }
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

  private func getConvoAvailability(_ params: [String: [String]]) -> [String: Any] {
    let members = Set(params["members"] ?? [])
    var output: [String: Any] = ["canChat": !members.isEmpty]
    if let convo = directConvo(containing: members) {
      output["convo"] = Self.encode(convo)
    }
    return output
  }

  private func getConvoForMembers(_ params: [String: [String]]) -> [String: Any] {
    let members = Set(params["members"] ?? [])
    if let convo = directConvo(containing: members) {
      return ["convo": Self.encode(convo)]
    }
    let id = "convo-created-\(lock.withLock { convoOrder.count + 1 })"
    let convo = addConvo(id: id, members: [Fixtures.selfDid] + members.sorted())
    return ["convo": Self.encode(convo)]
  }

  private func directConvo(
    containing members: Set<String>
  ) -> Chat.Bsky.ConvoDefs_ConvoView? {
    lock.withLock {
      convos.values.first { convo in
        Self.matchesKind(convo, kind: "direct")
          && members.isSubset(of: Set(convo.members.map { $0.did.rawValue }))
      }
    }
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
    let (logs, head) = lock.withLock { (self.log, self.log.last?.rev) }
    let filtered =
      since == nil
      ? logs.map(\.json)
      : logs.filter { $0.rev > since! }.map(\.json)
    var out: [String: Any] = ["logs": filtered]
    if let head { out["cursor"] = head }
    return out
  }

  private func getUnreadCounts() -> [String: Any] {
    let counts = lock.withLock { unread }
    return [
      "unreadAcceptedConvos": counts.accepted,
      "unreadRequestConvos": counts.request,
    ]
  }

  // MARK: - Procedure handlers

  private func sendMessage(_ body: Data?) throws -> [String: Any] {
    guard let json = Self.jsonObject(body),
      let convoId = json["convoId"] as? String,
      let message = json["message"] as? [String: Any]
    else {
      throw ServiceError(status: 400, error: "InvalidRequest", message: "bad sendMessage input")
    }
    let text = message["text"] as? String ?? ""
    return Self.encodeUnion(appendMessage(convoId: convoId, text: text))
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
      views.append(Self.encodeUnion(appendMessage(convoId: convoId, text: text)))
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
    return Self.encodeUnion(ConvoMessage.tombstone(view))
  }
}
