import Foundation
import Testing

@testable import ModerationUILogic

/// Port of the submit path in
/// `src/components/moderation/ReportDialog/action.ts`, i.e. the exact
/// `com.atproto.moderation.createReport` bodies each subject shape produces,
/// plus the reason-type fallback and the labeler-eligibility filters from
/// `ReportDialog/index.tsx`.
@Suite("Report submission")
struct ReportFlowTests {

  private func state(
    reason: String = ReportReasons.harassmentTroll,
    labelerDid: String = bskyModerationDid,
    details: String? = nil,
    includeVideoTimestamp: Bool = false
  ) -> ReportState {
    ReportState(
      selectedReason: ReportReason(reason: reason, title: "reason"),
      selectedLabelerDid: labelerDid,
      details: details,
      includeVideoTimestamp: includeVideoTimestamp)
  }

  /// Encodes a value to canonical JSON for exact comparison.
  private func json(_ value: ReportJSON) -> String { value.canonicalJSON }

  /// Encodes a whole body to canonical JSON.
  private func json(_ body: [String: ReportJSON]) -> String {
    ReportJSON.canonicalJSON(body)
  }

  // MARK: - Subject bodies

  @Test("an account report sends a repoRef subject")
  func accountSubject() throws {
    let subject = ParsedReportSubject.account(did: "did:plc:a", nsid: "app.bsky.actor.profile")
    let submission = try ReportFlow.submission(state: state(), subject: subject)
    #expect(
      json(submission.body)
        == #"{"reasonType":"tools.ozone.report.defs#reasonHarassmentTroll","subject":{"$type":"com.atproto.admin.defs#repoRef","did":"did:plc:a"}}"#)
  }

  @Test("a post report sends a strongRef subject")
  func postSubject() throws {
    let subject = ParsedReportSubject.post(
      uri: "at://did:plc:a/app.bsky.feed.post/1", cid: "bafypost",
      nsid: "app.bsky.feed.post", attributes: PostReportAttributes())
    let submission = try ReportFlow.submission(state: state(), subject: subject)
    #expect(
      json(submission.body)
        == #"{"reasonType":"tools.ozone.report.defs#reasonHarassmentTroll","subject":{"$type":"com.atproto.repo.strongRef","cid":"bafypost","uri":"at://did:plc:a/app.bsky.feed.post/1"}}"#)
  }

  @Test("a list report sends a strongRef subject")
  func listSubject() throws {
    let subject = ParsedReportSubject.list(
      uri: "at://did:plc:a/app.bsky.graph.list/1", cid: "bafylist", nsid: "app.bsky.graph.list")
    let submission = try ReportFlow.submission(state: state(), subject: subject)
    #expect(submission.subject["$type"]?.stringValue == "com.atproto.repo.strongRef")
    #expect(submission.subject["uri"]?.stringValue == "at://did:plc:a/app.bsky.graph.list/1")
  }

  @Test("a feed report sends a strongRef subject")
  func feedSubject() throws {
    let subject = ParsedReportSubject.feed(
      uri: "at://did:plc:a/app.bsky.feed.generator/1", cid: "bafygen",
      nsid: "app.bsky.feed.generator")
    let submission = try ReportFlow.submission(state: state(), subject: subject)
    #expect(submission.subject["$type"]?.stringValue == "com.atproto.repo.strongRef")
  }

  @Test("a starter pack report sends a strongRef subject")
  func starterPackSubject() throws {
    let subject = ParsedReportSubject.starterPack(
      uri: "at://did:plc:a/app.bsky.graph.starterpack/1", cid: "bafysp",
      nsid: ReportSubjectParser.starterPackNsid,
      sourceType: "app.bsky.graph.defs#starterPackView")
    let submission = try ReportFlow.submission(state: state(), subject: subject)
    #expect(submission.subject["$type"]?.stringValue == "com.atproto.repo.strongRef")
  }

  @Test("a status report sends a strongRef subject")
  func statusSubject() throws {
    let subject = ParsedReportSubject.status(
      uri: "at://did:plc:a/app.bsky.actor.status/self", cid: "bafystatus",
      nsid: "app.bsky.actor.status")
    let submission = try ReportFlow.submission(state: state(), subject: subject)
    #expect(submission.subject["$type"]?.stringValue == "com.atproto.repo.strongRef")
  }

  @Test("a convo message report sends a messageRef subject")
  func convoMessageSubject() throws {
    let subject = ParsedReportSubject.convoMessage(
      convoId: "c1",
      message: ParsedConvoMessage(messageId: "m1", convoId: "c1", senderDid: "did:plc:s"))
    let submission = try ReportFlow.submission(
      state: state(reason: ReportReasons.harassmentOther, labelerDid: bskyModerationDid),
      subject: subject)
    #expect(
      json(submission.subject)
        == #"{"$type":"chat.bsky.convo.defs#messageRef","convoId":"c1","did":"did:plc:s","messageId":"m1"}"#)
  }

  @Test("a convo report sends a convoRef subject")
  func convoSubject() throws {
    let subject = ParsedReportSubject.convo(convoId: "c1", did: "did:plc:s")
    let submission = try ReportFlow.submission(
      state: state(reason: ReportReasons.harassmentOther), subject: subject)
    #expect(
      json(submission.subject)
        == #"{"$type":"chat.bsky.convo.defs#convoRef","convoId":"c1","did":"did:plc:s"}"#)
  }

  // MARK: - Comment

  @Test("the comment is sent as reason")
  func commentAsReason() throws {
    let submission = try ReportFlow.submission(
      state: state(details: "because"), subject: .account(did: "did:plc:a", nsid: "x"))
    #expect(submission.body["reason"]?.stringValue == "because")
  }

  @Test("an empty comment omits the reason member")
  func noCommentOmitsReason() throws {
    let submission = try ReportFlow.submission(
      state: state(), subject: .account(did: "did:plc:a", nsid: "x"))
    #expect(submission.body["reason"] == nil)
  }

  // MARK: - Validation

  @Test("submitting with no reason throws")
  func noReasonThrows() {
    let state = ReportState(selectedLabelerDid: bskyModerationDid)
    #expect(throws: ReportFlow.ValidationError.noReason) {
      try ReportFlow.submission(
        state: state, subject: .account(did: "did:plc:a", nsid: "x"))
    }
  }

  @Test("submitting with no labeler throws")
  func noLabelerThrows() {
    let state = ReportState(
      selectedReason: ReportReason(reason: ReportReasons.harassmentTroll, title: "t"))
    #expect(throws: ReportFlow.ValidationError.noLabeler) {
      try ReportFlow.submission(
        state: state, subject: .account(did: "did:plc:a", nsid: "x"))
    }
  }

  // MARK: - Reason-type fallback

  @Test("a labeler declaring no reason types gets the new reason type")
  func undeclaredReasonTypesPassThrough() {
    #expect(
      ReportFlow.resolveReasonType(selected: ReportReasons.misleadingSpam, labelerReasonTypes: nil)
        == ReportReasons.misleadingSpam)
  }

  @Test("a labeler declaring the new reason type gets the new one")
  func newReasonTypePreferred() {
    #expect(
      ReportFlow.resolveReasonType(
        selected: ReportReasons.misleadingSpam,
        labelerReasonTypes: [ReportReasons.misleadingSpam])
        == ReportReasons.misleadingSpam)
  }

  @Test("a labeler declaring only the old reason type gets the old one")
  func oldReasonTypeFallback() {
    #expect(
      ReportFlow.resolveReasonType(
        selected: ReportReasons.misleadingSpam,
        labelerReasonTypes: ["com.atproto.moderation.defs#reasonSpam"])
        == "com.atproto.moderation.defs#reasonSpam")
  }

  @Test("a labeler declaring both prefers the new reason type")
  func bothDeclaredPrefersNew() {
    #expect(
      ReportFlow.resolveReasonType(
        selected: ReportReasons.misleadingSpam,
        labelerReasonTypes: [
          ReportReasons.misleadingSpam, "com.atproto.moderation.defs#reasonSpam",
        ])
        == ReportReasons.misleadingSpam)
  }

  @Test("a reason with no old mapping is sent unchanged")
  func unmappedReasonUnchanged() {
    #expect(
      ReportFlow.resolveReasonType(selected: ReportReasons.other, labelerReasonTypes: ["x"])
        == ReportReasons.other)
  }

  // MARK: - Video timestamp tool metadata

  @Test("the video timestamp is attached for a post reported to Bluesky")
  func videoTimestampAttached() throws {
    let subject = ParsedReportSubject.post(
      uri: "at://did:plc:a/app.bsky.feed.post/1", cid: "c", nsid: "app.bsky.feed.post",
      attributes: PostReportAttributes(video: true))
    let submission = try ReportFlow.submission(
      state: state(includeVideoTimestamp: true), subject: subject,
      modToolName: "bsky-app/ios/test", videoTimestampSeconds: 42)
    #expect(submission.modTool?["name"]?.stringValue == "bsky-app/ios/test")
    #expect(
      submission.modTool?["meta"]?.objectValue?["videoTimestampSeconds"]?.intValue == 42)
  }

  @Test("the video timestamp is not attached when not opted in")
  func videoTimestampNotOptedIn() throws {
    let subject = ParsedReportSubject.post(
      uri: "u", cid: "c", nsid: "app.bsky.feed.post", attributes: PostReportAttributes())
    let submission = try ReportFlow.submission(
      state: state(includeVideoTimestamp: false), subject: subject,
      modToolName: "bsky-app/ios/test", videoTimestampSeconds: 42)
    #expect(submission.modTool == nil)
  }

  @Test("the video timestamp is not attached for a non-post subject")
  func videoTimestampOnlyForPosts() throws {
    let submission = try ReportFlow.submission(
      state: state(includeVideoTimestamp: true),
      subject: .account(did: "did:plc:a", nsid: "x"),
      modToolName: "bsky-app/ios/test", videoTimestampSeconds: 42)
    #expect(submission.modTool == nil)
  }

  @Test("the video timestamp is not attached when reporting to another labeler")
  func videoTimestampOnlyForBluesky() throws {
    let subject = ParsedReportSubject.post(
      uri: "u", cid: "c", nsid: "app.bsky.feed.post", attributes: PostReportAttributes())
    let submission = try ReportFlow.submission(
      state: state(labelerDid: "did:plc:other", includeVideoTimestamp: true), subject: subject,
      modToolName: "bsky-app/ios/test", videoTimestampSeconds: 42)
    #expect(submission.modTool == nil)
  }

  @Test("the mod-tool names match RN's platform shapes")
  func modToolNames() {
    #expect(ReportModTool.ios(bundleIdentifier: "xyz.blueskyweb.app") == "bsky-app/ios/xyz.blueskyweb.app")
    #expect(ReportModTool.android(bundleIdentifier: "xyz.blueskyweb.app") == "bsky-app/android/xyz.blueskyweb.app")
    #expect(ReportModTool.web(hostname: "bsky.app") == "bsky-web/bsky.app")
  }

  // MARK: - Labeler eligibility

  @Test("an undeclared-capability labeler supports everything")
  func undeclaredLabelerSupportsAll() {
    let labeler = ReportFlow.LabelerCapabilities(did: "did:plc:l")
    #expect(
      ReportFlow.labelerSupports(
        labeler, subject: .account(did: "did:plc:a", nsid: "x"),
        reason: ReportReasons.harassmentTroll))
  }

  @Test("a labeler that does not declare the subject type is filtered out")
  func subjectTypeFilter() {
    let labeler = ReportFlow.LabelerCapabilities(did: "did:plc:l", subjectTypes: ["record"])
    #expect(
      !ReportFlow.labelerSupports(
        labeler, subject: .account(did: "did:plc:a", nsid: "x"),
        reason: ReportReasons.harassmentTroll))
  }

  @Test("a account subject requires the account subject type")
  func accountSubjectType() {
    let labeler = ReportFlow.LabelerCapabilities(did: "did:plc:l", subjectTypes: ["account"])
    #expect(
      ReportFlow.labelerSupports(
        labeler, subject: .account(did: "did:plc:a", nsid: "x"),
        reason: ReportReasons.harassmentTroll))
  }

  @Test("chat subjects require the chat subject type")
  func chatSubjectType() {
    // Chat subjects are Bluesky-only, so the labeler must be Bluesky for the
    // subject-type filter to be the thing under test.
    let labeler = ReportFlow.LabelerCapabilities(did: bskyModerationDid, subjectTypes: ["chat"])
    #expect(
      ReportFlow.labelerSupports(
        labeler, subject: .convo(convoId: "c", did: "d"),
        reason: ReportReasons.harassmentOther))
    let recordOnly = ReportFlow.LabelerCapabilities(
      did: bskyModerationDid, subjectTypes: ["record"])
    #expect(
      !ReportFlow.labelerSupports(
        recordOnly, subject: .convo(convoId: "c", did: "d"),
        reason: ReportReasons.harassmentOther))
  }

  @Test("a labeler that does not declare the collection is filtered out")
  func collectionFilter() {
    let labeler = ReportFlow.LabelerCapabilities(
      did: "did:plc:l", subjectCollections: ["app.bsky.feed.post"])
    #expect(
      !ReportFlow.labelerSupports(
        labeler, subject: .list(uri: "u", cid: "c", nsid: "app.bsky.graph.list"),
        reason: ReportReasons.harassmentTroll))
  }

  @Test("chat subjects bypass the collection filter")
  func chatBypassesCollections() {
    // Same caveat as above: the labeler must be Bluesky to reach this filter.
    let labeler = ReportFlow.LabelerCapabilities(
      did: bskyModerationDid, subjectCollections: ["app.bsky.feed.post"])
    #expect(
      ReportFlow.labelerSupports(
        labeler, subject: .convo(convoId: "c", did: "d"),
        reason: ReportReasons.harassmentOther))
  }

  @Test("the starter pack collection check uses the real NSID")
  func starterPackCollectionUsesRealNsid() {
    let subject = ParsedReportSubject.starterPack(
      uri: "u", cid: "c", nsid: ReportSubjectParser.starterPackNsid,
      sourceType: "app.bsky.graph.defs#starterPackView")
    let matching = ReportFlow.LabelerCapabilities(
      did: "did:plc:l", subjectCollections: ["app.bsky.graph.starterpack"])
    let typo = ReportFlow.LabelerCapabilities(
      did: "did:plc:l", subjectCollections: ["app.bsky.graph.starterPack"])
    #expect(
      ReportFlow.labelerSupports(matching, subject: subject, reason: ReportReasons.harassmentTroll))
    // A labeler declaring RN's typo'd collection no longer matches, because the
    // parsed subject carries the real NSID. This is the intended deviation.
    #expect(
      !ReportFlow.labelerSupports(typo, subject: subject, reason: ReportReasons.harassmentTroll))
  }

  @Test("a labeler declaring neither reason form is filtered out")
  func reasonTypeFilter() {
    let labeler = ReportFlow.LabelerCapabilities(
      did: "did:plc:l", reasonTypes: ["tools.ozone.report.defs#reasonOther"])
    #expect(
      !ReportFlow.labelerSupports(
        labeler, subject: .account(did: "did:plc:a", nsid: "x"),
        reason: ReportReasons.harassmentTroll))
  }

  @Test("a labeler declaring only the old reason form is kept")
  func oldReasonFormPasses() {
    let labeler = ReportFlow.LabelerCapabilities(
      did: "did:plc:l", reasonTypes: ["com.atproto.moderation.defs#reasonRude"])
    #expect(
      ReportFlow.labelerSupports(
        labeler, subject: .account(did: "did:plc:a", nsid: "x"),
        reason: ReportReasons.harassmentTroll))
  }

  @Test("a child-safety reason is Bluesky-only regardless of declarations")
  func blueskyOnlyReason() {
    let generous = ReportFlow.LabelerCapabilities(did: "did:plc:l")
    #expect(
      !ReportFlow.labelerSupports(
        generous, subject: .account(did: "did:plc:a", nsid: "x"),
        reason: ReportReasons.childSafetyCSAM))
    let bluesky = ReportFlow.LabelerCapabilities(did: bskyModerationDid)
    #expect(
      ReportFlow.labelerSupports(
        bluesky, subject: .account(did: "did:plc:a", nsid: "x"),
        reason: ReportReasons.childSafetyCSAM))
  }

  @Test("a status subject is Bluesky-only regardless of declarations")
  func blueskyOnlySubject() {
    let generous = ReportFlow.LabelerCapabilities(did: "did:plc:l")
    #expect(
      !ReportFlow.labelerSupports(
        generous, subject: .status(uri: "u", cid: "c", nsid: "app.bsky.actor.status"),
        reason: ReportReasons.harassmentTroll))
    #expect(
      ReportFlow.labelerSupports(
        ReportFlow.LabelerCapabilities(did: bskyModerationDid),
        subject: .status(uri: "u", cid: "c", nsid: "app.bsky.actor.status"),
        reason: ReportReasons.harassmentTroll))
  }

  @Test("a convo subject is Bluesky-only regardless of declarations")
  func convoIsBlueskyOnly() {
    #expect(ReportFlow.isBlueskyOnly(reason: nil, subject: .convo(convoId: "c", did: "d")))
  }

  @Test("the subject-type-name and subject-kind vocabularies are distinct")
  func subjectTypeNameAndKindDiffer() {
    // `BSKY_LABELER_ONLY_SUBJECT_TYPES` is written in RN's ParsedReportSubject
    // discriminant vocabulary, while labeler eligibility uses account/chat/
    // record. Conflating them silently disables the Bluesky-only gate.
    let status = ParsedReportSubject.status(uri: "u", cid: "c", nsid: "app.bsky.actor.status")
    #expect(ReportFlow.subjectTypeName(status) == "status")
    #expect(ReportFlow.subjectKind(status) == "record")

    let account = ParsedReportSubject.account(did: "d", nsid: "x")
    #expect(ReportFlow.subjectTypeName(account) == "account")
    #expect(ReportFlow.subjectKind(account) == "account")

    let convo = ParsedReportSubject.convo(convoId: "c", did: "d")
    #expect(ReportFlow.subjectTypeName(convo) == "convo")
    #expect(ReportFlow.subjectKind(convo) == "chat")

    // Every subject's type name is one of RN's discriminants.
    let discrminants: Set<String> = [
      "account", "status", "list", "feed", "starterPack", "post", "convoMessage", "convo",
    ]
    for subject in [
      ParsedReportSubject.list(uri: "u", cid: "c", nsid: "n"),
      ParsedReportSubject.feed(uri: "u", cid: "c", nsid: "n"),
      ParsedReportSubject.starterPack(uri: "u", cid: "c", nsid: "n", sourceType: "t"),
      ParsedReportSubject.post(uri: "u", cid: "c", nsid: "n", attributes: PostReportAttributes()),
      ParsedReportSubject.convoMessage(
        convoId: "c", message: ParsedConvoMessage(messageId: "m", convoId: "c", senderDid: "d")),
    ] {
      #expect(discrminants.contains(ReportFlow.subjectTypeName(subject)))
    }
  }

  @Test("supportedLabelers preserves input order")
  func supportedLabelersOrder() {
    let labelers = [
      ReportFlow.LabelerCapabilities(did: "did:plc:a"),
      ReportFlow.LabelerCapabilities(did: "did:plc:b", subjectTypes: ["chat"]),
      ReportFlow.LabelerCapabilities(did: "did:plc:c"),
    ]
    let supported = ReportFlow.supportedLabelers(
      labelers, subject: .account(did: "did:plc:x", nsid: "x"),
      reason: ReportReasons.harassmentTroll)
    #expect(supported.map(\.did) == ["did:plc:a", "did:plc:c"])
  }

  // MARK: - Subject kinds

  @Test("subject kinds map to account/chat/record")
  func subjectKinds() {
    #expect(ReportFlow.subjectKind(.account(did: "d", nsid: "x")) == "account")
    #expect(ReportFlow.subjectKind(.convo(convoId: "c", did: "d")) == "chat")
    #expect(
      ReportFlow.subjectKind(
        .convoMessage(
          convoId: "c", message: ParsedConvoMessage(messageId: "m", convoId: "c", senderDid: "d")))
        == "chat")
    #expect(ReportFlow.subjectKind(.list(uri: "u", cid: "c", nsid: "n")) == "record")
  }

  // MARK: - Reason catalog

  @Test("the reason catalog has every RN category in order")
  func catalogCategoryOrder() {
    #expect(
      ReportReasonCatalog.categories.map(\.key) == [
        .misleading, .sexualAdultContent, .harassmentHate, .violencePhysicalHarm,
        .childSafety, .selfHarm, .ruleBreaking, .other,
      ])
  }

  @Test("the details-allowing reasons match RN's set")
  func otherReasonsSet() {
    #expect(otherReportReasons.count == 8)
    #expect(otherReportReasons.contains(ReportReasons.other))
    #expect(otherReportReasons.contains(ReportReasons.ruleOther))
    #expect(!otherReportReasons.contains(ReportReasons.harassmentTroll))
  }

  @Test("the Bluesky-only reasons match RN's set")
  func blueskyOnlyReasonsSet() {
    #expect(
      bskyLabelerOnlyReportReasons == [
        ReportReasons.childSafetyCSAM, ReportReasons.childSafetyGroom,
        ReportReasons.childSafetyOther, ReportReasons.violenceExtremistContent,
      ])
  }

  @Test("every catalog option has a reason and a title")
  func catalogOptionsPopulated() {
    #expect(!ReportReasonCatalog.allOptions.isEmpty)
    for option in ReportReasonCatalog.allOptions {
      #expect(!option.reason.isEmpty)
      #expect(!option.title.isEmpty)
    }
  }

  @Test("newToOldReasonsMap covers every catalog reason")
  func newToOldMapCoversCatalog() {
    for option in ReportReasonCatalog.allOptions {
      #expect(newToOldReasonsMap[option.reason] != nil)
    }
  }
}
