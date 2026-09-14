import Foundation

import Lexicons
import SwiftAtproto

/// The `com.atproto.moderation.createReport` body, built locally.
///
/// RN builds a plain object and hands it to the lex client, which serializes
/// it. The Swift port builds a `ReportJSON` so the exact wire bytes — including
/// the open-union subject `$type` — are assertable in tests without going
/// through the generated union, which would reject the chat subject refs the
/// lexicon leaves open (see `toOpenSubject` in RN's `action.ts`).
public struct ReportSubmission: Sendable, Equatable {
  public var reasonType: String
  public var reason: String?
  public var subject: [String: ReportJSON]
  public var modTool: [String: ReportJSON]?

  public init(
    reasonType: String, reason: String?, subject: [String: ReportJSON],
    modTool: [String: ReportJSON]? = nil
  ) {
    self.reasonType = reasonType
    self.reason = reason
    self.subject = subject
    self.modTool = modTool
  }

  /// The request body as an object.
  public var body: [String: ReportJSON] {
    var out: [String: ReportJSON] = [
      "reasonType": ReportJSON(reasonType),
      "subject": .object(subject),
    ]
    if let reason { out["reason"] = ReportJSON(reason) }
    if let modTool { out["modTool"] = .object(modTool) }
    return out
  }
}

/// A minimal JSON value, so report bodies can be built and compared without
/// pulling in the Preferences package's variant.
public enum ReportJSON: Sendable, Equatable {
  case string(String)
  case int(Int)
  case bool(Bool)
  case null
  case object([String: ReportJSON])
  case array([ReportJSON])

  /// Wraps a Swift value the way RN's object literals carry them.
  public init(_ value: String) { self = .string(value) }
  public init(_ value: Int) { self = .int(value) }
  public init(_ value: Bool) { self = .bool(value) }

  /// The string payload, when this is a string.
  public var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  /// The object payload, when this is an object.
  public var objectValue: [String: ReportJSON]? {
    if case .object(let value) = self { return value }
    return nil
  }

  /// The integer payload, when this is an int.
  public var intValue: Int? {
    if case .int(let value) = self { return value }
    return nil
  }

  /// Encodes to JSON, sorting object keys so bodies compare stably.
  public func encoded() -> Any {
    switch self {
    case .string(let value): return value
    case .int(let value): return value
    case .bool(let value): return value
    case .null: return NSNull()
    case .object(let value): return value.mapValues { $0.encoded() }
    case .array(let value): return value.map { $0.encoded() }
    }
  }

  /// Canonical JSON text with object keys sorted, for exact body comparisons.
  public var canonicalJSON: String {
    switch self {
    case .string(let value): return ReportJSON.quoted(value)
    case .int(let value): return String(value)
    case .bool(let value): return value ? "true" : "false"
    case .null: return "null"
    case .object(let members):
      let inner = members.keys.sorted().map { key in
        ReportJSON.quoted(key) + ":" + members[key]!.canonicalJSON
      }
      return "{" + inner.joined(separator: ",") + "}"
    case .array(let values):
      return "[" + values.map(\.canonicalJSON).joined(separator: ",") + "]"
    }
  }

  /// Canonical JSON text for a whole object.
  public static func canonicalJSON(_ object: [String: ReportJSON]) -> String {
    ReportJSON.object(object).canonicalJSON
  }

  private static func quoted(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
    return out
  }
}

/// The name this client reports under (`REPORT_MOD_TOOL_NAME`).
///
/// RN branches on the platform: `bsky-app/ios/<bundle>`, `bsky-app/android/
/// <bundle>`, `bsky-web/<host>`. The Swift port keeps the same shape and takes
/// the platform + identifier, so the Views layer supplies its own.
public enum ReportModTool {
  /// The name sent for a native iOS build.
  public static func ios(bundleIdentifier: String) -> String {
    "bsky-app/ios/\(bundleIdentifier)"
  }

  /// The name sent for a native Android build.
  public static func android(bundleIdentifier: String) -> String {
    "bsky-app/android/\(bundleIdentifier)"
  }

  /// The name sent for a web build.
  public static func web(hostname: String) -> String {
    "bsky-web/\(hostname)"
  }
}

/// Builds and submits a report to a labeler.
///
/// Port of the `useReportMutation` body in
/// `src/components/moderation/ReportDialog/action.ts`, split so the pure
/// decisions (reason-type fallback, subject shape, labeler eligibility) are
/// testable without a network.
public enum ReportFlow {

  /// Thrown when the dialog's state does not yet name a reason or a labeler.
  public enum ValidationError: Error, Sendable, Equatable {
    /// No reason selected.
    case noReason
    /// No moderation service selected.
    case noLabeler
  }

  /// Resolves the reason type to send to `labeler`.
  ///
  /// Port of the backwards-compatibility block in `action.ts`: when the
  /// labeler declares the OLD (atproto) reason type but not the new Ozone one,
  /// the old value is sent. A labeler that declares no reason types at all
  /// accepts the new value, because `reasonTypes` undefined means "all".
  public static func resolveReasonType(
    selected: String, labelerReasonTypes: [String]?
  ) -> String {
    guard let labelerReasonTypes else { return selected }
    let backwardsCompatible = newToOldReasonsMap[selected]
    let supportsNew = labelerReasonTypes.contains(selected)
    let supportsOld = backwardsCompatible.map(labelerReasonTypes.contains) ?? false
    if supportsOld && !supportsNew, let backwardsCompatible {
      return backwardsCompatible
    }
    return selected
  }

  /// The strongRef subject shape shared by every record-backed subject.
  public static func strongRefSubject(uri: String, cid: String) -> [String: ReportJSON] {
    [
      "$type": ReportJSON("com.atproto.repo.strongRef"),
      "uri": ReportJSON(uri),
      "cid": ReportJSON(cid),
    ]
  }

  /// The repoRef subject shape used for accounts.
  public static func repoRefSubject(did: String) -> [String: ReportJSON] {
    [
      "$type": ReportJSON("com.atproto.admin.defs#repoRef"),
      "did": ReportJSON(did),
    ]
  }

  /// The chat message reference subject.
  public static func messageRefSubject(
    messageId: String, convoId: String, did: String
  ) -> [String: ReportJSON] {
    [
      "$type": ReportJSON("chat.bsky.convo.defs#messageRef"),
      "messageId": ReportJSON(messageId),
      "convoId": ReportJSON(convoId),
      "did": ReportJSON(did),
    ]
  }

  /// The chat conversation reference subject.
  public static func convoRefSubject(convoId: String, did: String) -> [String: ReportJSON] {
    [
      "$type": ReportJSON("chat.bsky.convo.defs#convoRef"),
      "convoId": ReportJSON(convoId),
      "did": ReportJSON(did),
    ]
  }

  /// Maps a parsed subject onto `createReport`'s subject union.
  ///
  /// The record-backed cases collapse to a strongRef, exactly as RN's switch
  /// does (`status`, `post`, `list`, `feed`, `starterPack` share one arm).
  public static func subjectBody(_ subject: ParsedReportSubject) -> [String: ReportJSON] {
    switch subject {
    case .account(let did, _):
      return repoRefSubject(did: did)
    case .status(let uri, let cid, _), .list(let uri, let cid, _),
      .feed(let uri, let cid, _), .starterPack(let uri, let cid, _, _),
      .post(let uri, let cid, _, _):
      return strongRefSubject(uri: uri, cid: cid)
    case .convoMessage(let convoId, let message):
      return messageRefSubject(
        messageId: message.messageId, convoId: convoId, did: message.senderDid)
    case .convo(let convoId, let did):
      return convoRefSubject(convoId: convoId, did: did)
    }
  }

  /// True when `reason` names a category whose details field should be offered.
  public static func reasonAllowsDetails(_ reason: String) -> Bool {
    otherReportReasons.contains(reason)
  }

  /// Whether `labelerDid` is the only service allowed to review this report.
  ///
  /// Port of the `isBskyOnlyReason` / `isBskyOnlySubject` conditions: some
  /// reasons and some subject types are Bluesky-only regardless of what other
  /// labelers declare.
  ///
  /// - Note: the subject check reads RN's `ParsedReportSubject['type']
  ///   discriminant ("post", "status", "convo", ...), NOT the labeler-
  ///   eligibility ``subjectKind(_:)`` ("account"/"chat"/"record"). The two are
  ///   different vocabularies and `BSKY_LABELER_ONLY_SUBJECT_TYPES` is written
  ///   in the former.
  public static func isBlueskyOnly(reason: String?, subject: ParsedReportSubject) -> Bool {
    if let reason, bskyLabelerOnlyReportReasons.contains(reason) { return true }
    return bskyLabelerOnlySubjectTypes.contains(subjectTypeName(subject))
  }

  /// The RN `ParsedReportSubject['type']` discriminant for a subject.
  public static func subjectTypeName(_ subject: ParsedReportSubject) -> String {
    switch subject {
    case .account: return "account"
    case .status: return "status"
    case .list: return "list"
    case .feed: return "feed"
    case .starterPack: return "starterPack"
    case .post: return "post"
    case .convoMessage: return "convoMessage"
    case .convo: return "convo"
    }
  }

  /// The labeler-eligibility key for a subject: `account`, `chat`, or `record`.
  public static func subjectKind(_ subject: ParsedReportSubject) -> String {
    switch subject {
    case .account: return "account"
    case .convoMessage, .convo: return "chat"
    default: return "record"
    }
  }

  /// A labeler's declared capabilities, reduced to what eligibility reads.
  public struct LabelerCapabilities: Sendable, Hashable {
    public var did: String
    /// Undeclared means "all".
    public var reasonTypes: [String]?
    /// Undeclared means "any record type".
    public var subjectCollections: [String]?
    /// Undeclared means "any subject type".
    public var subjectTypes: [String]?

    public init(
      did: String, reasonTypes: [String]? = nil, subjectCollections: [String]? = nil,
      subjectTypes: [String]? = nil
    ) {
      self.did = did
      self.reasonTypes = reasonTypes
      self.subjectCollections = subjectCollections
      self.subjectTypes = subjectTypes
    }
  }

  /// Whether `labeler` can review `subject` with `reason`.
  ///
  /// Port of the three `.filter(...)` passes over `allLabelers` in
  /// `ReportDialog/index.tsx`. The passes run in RN's order, which matters:
  /// the subject-type and collection filters run BEFORE the Bluesky-only short
  /// circuit, so a Bluesky labeler that does not declare the subject type is
  /// still filtered out.
  public static func labelerSupports(
    _ labeler: LabelerCapabilities, subject: ParsedReportSubject, reason: String
  ) -> Bool {
    let kind = subjectKind(subject)

    // Pass 1: subject type.
    if let subjectTypes = labeler.subjectTypes {
      if !subjectTypes.contains(kind) { return false }
    }

    // Pass 2: declared collections. Chat collections are all accepted, since
    // only Bluesky handles chats.
    if let collections = labeler.subjectCollections, kind != "chat" {
      guard let nsid = subject.nsid, collections.contains(nsid) else { return false }
    }

    // Pass 3: Bluesky-only short circuit, then reason types.
    if isBlueskyOnly(reason: reason, subject: subject) {
      return labeler.did == bskyModerationDid
    }

    if let reasonTypes = labeler.reasonTypes {
      let backwardsCompatible = newToOldReasonsMap[reason]
      let supported =
        reasonTypes.contains(reason)
        || (backwardsCompatible.map(reasonTypes.contains) ?? false)
      if !supported { return false }
    }

    return true
  }

  /// The labelers that can review `subject` with `reason`, in input order.
  public static func supportedLabelers(
    _ labelers: [LabelerCapabilities], subject: ParsedReportSubject, reason: String
  ) -> [LabelerCapabilities] {
    labelers.filter { labelerSupports($0, subject: subject, reason: reason) }
  }

  /// Builds the submission body.
  ///
  /// - Parameters:
  ///   - state: the dialog state, which must carry a reason and a labeler did.
  ///   - subject: the parsed subject.
  ///   - labelerReasonTypes: the selected labeler's declared reason types.
  ///   - modToolName: the client identifier, sent only for a video post whose
  ///     timestamp the reporter opted into.
  ///   - videoTimestampSeconds: the watch position, when opted in.
  ///   - apiModerationDid: the app's own moderation did, used to decide whether
  ///     the video-timestamp tool metadata applies.
  public static func submission(
    state: ReportState,
    subject: ParsedReportSubject,
    labelerReasonTypes: [String]? = nil,
    modToolName: String? = nil,
    videoTimestampSeconds: Int? = nil,
    apiModerationDid: String = bskyModerationDid
  ) throws -> ReportSubmission {
    guard let reason = state.selectedReason else {
      throw ValidationError.noReason
    }
    guard let labelerDid = state.selectedLabelerDid else {
      throw ValidationError.noLabeler
    }

    let reasonType = resolveReasonType(
      selected: reason.reason, labelerReasonTypes: labelerReasonTypes)

    var modTool: [String: ReportJSON]?
    if state.includeVideoTimestamp, let videoTimestampSeconds, modToolName != nil,
      isPost(subject), labelerDid == apiModerationDid {
      modTool = [
        "name": ReportJSON(modToolName ?? ""),
        "meta": .object(["videoTimestampSeconds": ReportJSON(videoTimestampSeconds)]),
      ]
    }

    return ReportSubmission(
      reasonType: reasonType, reason: state.details, subject: subjectBody(subject),
      modTool: modTool)
  }

  static func isPost(_ subject: ParsedReportSubject) -> Bool {
    if case .post = subject { return true }
    return false
  }
}

/// The labeler the app is reporting to, as the report dialog needs it.
public struct ReportLabeler: Sendable, Hashable {
  public var did: String
  public var displayName: String?
  public var handle: String
  public var reasonTypes: [String]?
  public var subjectCollections: [String]?
  public var subjectTypes: [String]?

  public init(
    did: String, displayName: String? = nil, handle: String, reasonTypes: [String]? = nil,
    subjectCollections: [String]? = nil, subjectTypes: [String]? = nil
  ) {
    self.did = did
    self.displayName = displayName
    self.handle = handle
    self.reasonTypes = reasonTypes
    self.subjectCollections = subjectCollections
    self.subjectTypes = subjectTypes
  }

  /// The reduced capability view used for eligibility.
  public var capabilities: ReportFlow.LabelerCapabilities {
    ReportFlow.LabelerCapabilities(
      did: did, reasonTypes: reasonTypes, subjectCollections: subjectCollections,
      subjectTypes: subjectTypes)
  }

  /// The display title, preferring the display name (port of
  /// `getLabelingServiceTitle`).
  public var title: String {
    if let displayName, !displayName.isEmpty { return displayName }
    return handle.hasPrefix("@") ? handle : "@\(handle)"
  }
}
