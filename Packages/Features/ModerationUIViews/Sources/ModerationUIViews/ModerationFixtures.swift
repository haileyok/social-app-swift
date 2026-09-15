import Foundation
import Lexicons
import Moderation
import ModerationUILogic
import SwiftAtproto

/// Deterministic sample data for the moderation surfaces.
///
/// The `#Preview`s below each screen and the fixture screens use these, so a
/// rendered moderation surface never depends on a live session or a network
/// read. Everything here is built through the same public initializers the app
/// uses, and the derived parts (which label rows exist, what a muted-word row
/// shows) are produced by `ModerationUILogic` rather than hand-written, so a
/// fixture cannot drift from the logic it is meant to stand in for.
public enum ModerationFixtures {

  // MARK: - Content labels

  /// A content-labels model with one labeler section and the global rows.
  public static func contentLabelsModel() -> ContentLabelsModel {
    let globalRows = ContentLabels.globalLabelIdentifiers.compactMap {
      identifier -> ContentLabelRow? in
      guard let definition = Moderation.labels[identifier] else { return nil }
      return ContentLabelRow(
        identifier: identifier,
        definition: definition,
        labelerDid: nil,
        savedPreference: nil,
        preference: definition.defaultSetting,
        configurable: true,
        adultDisabled: false,
        isGlobalLabel: true,
        canWarn: !(definition.blurs == .none && definition.severity == .none),
        showsStaticValue: true)
    }

    return ContentLabelsModel(
      globalRows: globalRows,
      sections: [customLabelerSection(), unsubscribedLabelerSection()],
      showsGlobalRows: true,
      isAdultContentEnabled: true)
  }

  /// A subscribed labeler with two of its own labels.
  public static func customLabelerSection() -> ContentLabelSection {
    ContentLabelSection(
      labelerDid: "did:plc:labelerexample",
      title: "Example Moderation",
      handle: "mod.example.com",
      isSubscribed: true,
      customDefinitions: [],
      rows: [
        ContentLabelRow(
          identifier: "example-spoiler",
          definition: sampleDefinition(
            identifier: "example-spoiler", severity: .alert, blurs: .content,
            definedBy: "did:plc:labelerexample"),
          labelerDid: "did:plc:labelerexample",
          savedPreference: .warn,
          preference: .warn,
          configurable: true,
          adultDisabled: false,
          isGlobalLabel: false,
          canWarn: true,
          showsStaticValue: false),
        ContentLabelRow(
          identifier: "example-adult",
          definition: sampleDefinition(
            identifier: "example-adult", severity: .alert, blurs: .media,
            definedBy: "did:plc:labelerexample", adultOnly: true),
          labelerDid: "did:plc:labelerexample",
          savedPreference: nil,
          // An adult label while adult content is off is forced to hide, which is
          // the state this row demonstrates.
          preference: .hide,
          configurable: false,
          adultDisabled: true,
          isGlobalLabel: false,
          canWarn: true,
          showsStaticValue: true),
      ])
  }

  /// A labeler the viewer has not subscribed to, whose rows render inert.
  public static func unsubscribedLabelerSection() -> ContentLabelSection {
    ContentLabelSection(
      labelerDid: "did:plc:unsubscribedexample",
      title: "Another Labeler",
      handle: "other.example.com",
      isSubscribed: false,
      customDefinitions: [],
      rows: [
        ContentLabelRow(
          identifier: "other-misinfo",
          definition: sampleDefinition(
            identifier: "other-misinfo", severity: .inform, blurs: .none,
            definedBy: "did:plc:unsubscribedexample"),
          labelerDid: "did:plc:unsubscribedexample",
          savedPreference: nil,
          preference: .warn,
          configurable: false,
          adultDisabled: false,
          isGlobalLabel: false,
          // `blurs: none` with `severity: inform` cannot warn, so the stored
          // warn is coerced away and the group offers only Show/Hide.
          canWarn: false,
          showsStaticValue: false),
      ])
  }

  /// A label definition with the fixture's defaults filled in.
  static func sampleDefinition(
    identifier: String, severity: LabelSeverity, blurs: LabelBlurs, definedBy: String,
    adultOnly: Bool = false
  ) -> LabelValueDefinition {
    LabelValueDefinition(
      identifier: identifier,
      severity: severity,
      blurs: blurs,
      defaultSetting: .warn,
      flags: adultOnly ? [.adult] : [],
      behaviors: LabelTargetBehaviors(
        account: ModerationBehavior(),
        profile: ModerationBehavior(),
        content: ModerationBehavior()),
      definedBy: definedBy)
  }

  // MARK: - Muted words

  /// Muted-word rows, newest first, as the list screen renders them.
  public static func mutedWordRows(now: Date = Date(timeIntervalSince1970: 1_800_000_000))
    -> [MutedWordRowModel]
  {
    let words = [
      MutedWord(value: "spoilers", targets: [.tag, .content], actorTarget: .all),
      MutedWord(value: "crypto", targets: [.tag], actorTarget: .excludeFollowing),
      MutedWord(
        value: "oldnews", targets: [.tag], actorTarget: .all,
        expiresAt: iso(Date(timeIntervalSince1970: 1_700_000_000))),
      MutedWord(
        value: "futuredate", targets: [.tag, .content], actorTarget: .all,
        expiresAt: iso(now.addingTimeInterval(86_400 * 7))),
    ]
    return MutedWordsEditor.rows(words, now: now)
  }

  static func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  // MARK: - Accounts

  /// Sample profiles for the blocked/muted lists.
  public static func profileViews(count: Int = 5) -> [ModerationProfileView] {
    (0..<count).map { index in
      ModerationProfileView(
        did: FormatString<DID>(rawValue: "did:plc:fixture\(index)"),
        displayName: "Fixture Account \(index)",
        handle: FormatString<Handle>(rawValue: "fixture\(index).test"))
    }
  }

  // MARK: - Labelers

  /// Sample labeler directory rows.
  public static func labelerRows(subscribed: Bool, startIndex: Int = 0, count: Int = 3)
    -> [LabelerRowModel]
  {
    (0..<count).map { offset in
      let index = startIndex + offset
      return LabelerRowModel(
        did: "did:plc:labeler\(index)",
        title: "Labeler \(index)",
        handle: "labeler\(index).test",
        description: "A moderation service used by the fixture surfaces.",
        isSubscribed: subscribed,
        isConfigurable: true)
    }
  }

  // MARK: - Report

  /// A post subject with image and reply attributes.
  public static func reportSubject() -> ParsedReportSubject {
    .post(
      uri: "at://did:plc:fixture/app.bsky.feed.post/3kfixture",
      cid: "bafyreibfixture",
      nsid: "app.bsky.feed.post",
      attributes: PostReportAttributes(reply: true, image: true))
  }

  /// Two candidate moderation services, one of which cannot review an account
  /// or a chat subject.
  public static func reportLabelers() -> [ReportLabeler] {
    [
      ReportLabeler(
        did: bskyModerationDid,
        displayName: "Bluesky Moderation Service",
        handle: "moderation.bsky.app"),
      ReportLabeler(
        did: "did:plc:labelerexample",
        displayName: "Example Moderation",
        handle: "mod.example.com",
        reasonTypes: [ReportReasons.misleadingSpam, ReportReasons.harassmentTroll],
        subjectCollections: ["app.bsky.feed.post", "app.bsky.actor.profile"],
        subjectTypes: ["record", "account"]),
    ]
  }
}
