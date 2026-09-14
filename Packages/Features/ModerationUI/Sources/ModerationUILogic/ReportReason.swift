import Foundation

/// One selectable report reason.
///
/// Port of the `ReportOption` type in
/// `src/components/moderation/ReportDialog/utils/useReportOptions.ts`. The RN
/// version carries an already-localized `title`; the Swift port keeps the
/// English source copy plus the catalog identifier so the Views layer can look
/// up a translation, and the reason type is a plain string because the
/// generated `ModerationDefs_ReasonType` is a large enum that callers compare
/// on the wire value anyway.
public struct ReportReason: Sendable, Hashable {
  /// The `tools.ozone.report.defs#reason*` value sent as `reasonType`.
  public let reason: String
  /// English source copy for the option label.
  public let title: String

  public init(reason: String, title: String) {
    self.reason = reason
    self.title = title
  }
}

/// A category of report reasons, in the order the dialog shows them.
///
/// Port of `ReportCategoryConfig`.
public struct ReportCategory: Sendable, Hashable {
  public let key: ReportCategoryKey
  public let title: String
  public let description: String
  public let options: [ReportReason]

  public init(key: ReportCategoryKey, title: String, description: String, options: [ReportReason]) {
    self.key = key
    self.title = title
    self.description = description
    self.options = options
  }
}

/// The stable category identifiers, matching the RN union.
public enum ReportCategoryKey: String, Sendable, CaseIterable, Hashable {
  case misleading
  case sexualAdultContent
  case harassmentHate
  case violencePhysicalHarm
  case childSafety
  case selfHarm
  case ruleBreaking
  case other
}

/// The `tools.ozone.report.defs` reason values the dialog can send.
public enum ReportReasons {
  public static let appeal = "tools.ozone.report.defs#reasonAppeal"

  public static let violenceAnimal = "tools.ozone.report.defs#reasonViolenceAnimal"
  public static let violenceThreats = "tools.ozone.report.defs#reasonViolenceThreats"
  public static let violenceGraphicContent = "tools.ozone.report.defs#reasonViolenceGraphicContent"
  public static let violenceGlorification = "tools.ozone.report.defs#reasonViolenceGlorification"
  public static let violenceExtremistContent = "tools.ozone.report.defs#reasonViolenceExtremistContent"
  public static let violenceTrafficking = "tools.ozone.report.defs#reasonViolenceTrafficking"
  public static let violenceOther = "tools.ozone.report.defs#reasonViolenceOther"

  public static let sexualAbuseContent = "tools.ozone.report.defs#reasonSexualAbuseContent"
  public static let sexualNCII = "tools.ozone.report.defs#reasonSexualNCII"
  public static let sexualDeepfake = "tools.ozone.report.defs#reasonSexualDeepfake"
  public static let sexualAnimal = "tools.ozone.report.defs#reasonSexualAnimal"
  public static let sexualUnlabeled = "tools.ozone.report.defs#reasonSexualUnlabeled"
  public static let sexualOther = "tools.ozone.report.defs#reasonSexualOther"

  public static let childSafetyCSAM = "tools.ozone.report.defs#reasonChildSafetyCSAM"
  public static let childSafetyGroom = "tools.ozone.report.defs#reasonChildSafetyGroom"
  public static let childSafetyPrivacy = "tools.ozone.report.defs#reasonChildSafetyPrivacy"
  public static let childSafetyHarassment = "tools.ozone.report.defs#reasonChildSafetyHarassment"
  public static let childSafetyOther = "tools.ozone.report.defs#reasonChildSafetyOther"

  public static let harassmentTroll = "tools.ozone.report.defs#reasonHarassmentTroll"
  public static let harassmentTargeted = "tools.ozone.report.defs#reasonHarassmentTargeted"
  public static let harassmentHateSpeech = "tools.ozone.report.defs#reasonHarassmentHateSpeech"
  public static let harassmentDoxxing = "tools.ozone.report.defs#reasonHarassmentDoxxing"
  public static let harassmentOther = "tools.ozone.report.defs#reasonHarassmentOther"

  public static let misleadingBot = "tools.ozone.report.defs#reasonMisleadingBot"
  public static let misleadingImpersonation = "tools.ozone.report.defs#reasonMisleadingImpersonation"
  public static let misleadingSpam = "tools.ozone.report.defs#reasonMisleadingSpam"
  public static let misleadingScam = "tools.ozone.report.defs#reasonMisleadingScam"
  public static let misleadingElections = "tools.ozone.report.defs#reasonMisleadingElections"
  public static let misleadingOther = "tools.ozone.report.defs#reasonMisleadingOther"

  public static let ruleSiteSecurity = "tools.ozone.report.defs#reasonRuleSiteSecurity"
  public static let ruleProhibitedSales = "tools.ozone.report.defs#reasonRuleProhibitedSales"
  public static let ruleBanEvasion = "tools.ozone.report.defs#reasonRuleBanEvasion"
  public static let ruleOther = "tools.ozone.report.defs#reasonRuleOther"

  public static let selfHarmContent = "tools.ozone.report.defs#reasonSelfHarmContent"
  public static let selfHarmED = "tools.ozone.report.defs#reasonSelfHarmED"
  public static let selfHarmStunts = "tools.ozone.report.defs#reasonSelfHarmStunts"
  public static let selfHarmSubstances = "tools.ozone.report.defs#reasonSelfHarmSubstances"
  public static let selfHarmOther = "tools.ozone.report.defs#reasonSelfHarmOther"

  public static let other = "tools.ozone.report.defs#reasonOther"
}

/// Reasons that should optionally include additional details from the reporter.
///
/// Port of `OTHER_REPORT_REASONS`. Selecting one of these opens the "details"
/// field and allows the report to be submitted with a comment.
public let otherReportReasons: Set<String> = [
  ReportReasons.violenceOther,
  ReportReasons.sexualOther,
  ReportReasons.childSafetyOther,
  ReportReasons.harassmentOther,
  ReportReasons.misleadingOther,
  ReportReasons.ruleOther,
  ReportReasons.selfHarmOther,
  ReportReasons.other,
]

/// Reasons that may only be sent to Bluesky's moderation service.
///
/// Port of `BSKY_LABELER_ONLY_REPORT_REASONS`. When one of these is selected
/// the labeler picker is pinned to Bluesky's moderation DID.
public let bskyLabelerOnlyReportReasons: Set<String> = [
  ReportReasons.childSafetyCSAM,
  ReportReasons.childSafetyGroom,
  ReportReasons.childSafetyOther,
  ReportReasons.violenceExtremistContent,
]

/// Parsed subject types that may only be sent to Bluesky's moderation service
/// (port of `BSKY_LABELER_ONLY_SUBJECT_TYPES`).
public let bskyLabelerOnlySubjectTypes: Set<String> = [
  "convoMessage", "convo", "status",
]

/// Mapping of new (Ozone) reason types to the old
/// `com.atproto.moderation.defs#reason*` values, used for backwards
/// compatibility with labelers that only declared the old set.
///
/// Port of `NEW_TO_OLD_REASONS_MAP`.
public let newToOldReasonsMap: [String: String] = [
  ReportReasons.appeal: "com.atproto.moderation.defs#reasonAppeal",
  ReportReasons.other: "com.atproto.moderation.defs#reasonOther",

  ReportReasons.violenceAnimal: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.violenceThreats: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.violenceGraphicContent: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.violenceGlorification: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.violenceExtremistContent: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.violenceTrafficking: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.violenceOther: "com.atproto.moderation.defs#reasonViolation",

  ReportReasons.sexualAbuseContent: "com.atproto.moderation.defs#reasonSexual",
  ReportReasons.sexualNCII: "com.atproto.moderation.defs#reasonSexual",
  ReportReasons.sexualDeepfake: "com.atproto.moderation.defs#reasonSexual",
  ReportReasons.sexualAnimal: "com.atproto.moderation.defs#reasonSexual",
  ReportReasons.sexualUnlabeled: "com.atproto.moderation.defs#reasonSexual",
  ReportReasons.sexualOther: "com.atproto.moderation.defs#reasonSexual",

  ReportReasons.childSafetyCSAM: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.childSafetyGroom: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.childSafetyPrivacy: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.childSafetyHarassment: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.childSafetyOther: "com.atproto.moderation.defs#reasonViolation",

  ReportReasons.harassmentTroll: "com.atproto.moderation.defs#reasonRude",
  ReportReasons.harassmentTargeted: "com.atproto.moderation.defs#reasonRude",
  ReportReasons.harassmentHateSpeech: "com.atproto.moderation.defs#reasonRude",
  ReportReasons.harassmentDoxxing: "com.atproto.moderation.defs#reasonRude",
  ReportReasons.harassmentOther: "com.atproto.moderation.defs#reasonRude",

  ReportReasons.misleadingBot: "com.atproto.moderation.defs#reasonMisleading",
  ReportReasons.misleadingImpersonation: "com.atproto.moderation.defs#reasonMisleading",
  ReportReasons.misleadingSpam: "com.atproto.moderation.defs#reasonSpam",
  ReportReasons.misleadingScam: "com.atproto.moderation.defs#reasonMisleading",
  ReportReasons.misleadingElections: "com.atproto.moderation.defs#reasonMisleading",
  ReportReasons.misleadingOther: "com.atproto.moderation.defs#reasonMisleading",

  ReportReasons.ruleSiteSecurity: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.ruleProhibitedSales: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.ruleBanEvasion: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.ruleOther: "com.atproto.moderation.defs#reasonViolation",

  ReportReasons.selfHarmContent: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.selfHarmED: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.selfHarmStunts: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.selfHarmSubstances: "com.atproto.moderation.defs#reasonViolation",
  ReportReasons.selfHarmOther: "com.atproto.moderation.defs#reasonViolation",
]

/// Mapping of old reason types to the new Ozone values.
///
/// Port of `OLD_TO_NEW_REASONS_MAP`.
public let oldToNewReasonsMap: [String: String] = [
  "com.atproto.moderation.defs#reasonSpam": ReportReasons.misleadingSpam,
  "com.atproto.moderation.defs#reasonViolation": ReportReasons.ruleOther,
  "com.atproto.moderation.defs#reasonMisleading": ReportReasons.misleadingOther,
  "com.atproto.moderation.defs#reasonSexual": ReportReasons.sexualUnlabeled,
  "com.atproto.moderation.defs#reasonRude": ReportReasons.harassmentOther,
  "com.atproto.moderation.defs#reasonOther": ReportReasons.other,
  "com.atproto.moderation.defs#reasonAppeal": ReportReasons.appeal,
]

/// The reason catalog, in dialog order.
///
/// Port of the `categories` object built by `useReportOptions`.
public enum ReportReasonCatalog {
  public static let categories: [ReportCategory] = [
    ReportCategory(
      key: .misleading,
      title: "Misleading",
      description: "Spam or other inauthentic behavior or deception",
      options: [
        ReportReason(reason: ReportReasons.misleadingSpam, title: "Spam"),
        ReportReason(reason: ReportReasons.misleadingScam, title: "Scam"),
        ReportReason(reason: ReportReasons.misleadingBot, title: "Fake account or bot"),
        ReportReason(reason: ReportReasons.misleadingImpersonation, title: "Impersonation"),
        ReportReason(
          reason: ReportReasons.misleadingElections, title: "False information about elections"),
        ReportReason(reason: ReportReasons.misleadingOther, title: "Other misleading content"),
      ]),
    ReportCategory(
      key: .sexualAdultContent,
      title: "Adult content",
      description: "Unlabeled, abusive, or non-consensual adult content",
      options: [
        ReportReason(reason: ReportReasons.sexualUnlabeled, title: "Unlabeled adult content"),
        ReportReason(reason: ReportReasons.sexualAbuseContent, title: "Adult sexual abuse content"),
        ReportReason(
          reason: ReportReasons.sexualNCII, title: "Non-consensual intimate imagery"),
        ReportReason(reason: ReportReasons.sexualDeepfake, title: "Deepfake adult content"),
        ReportReason(reason: ReportReasons.sexualAnimal, title: "Animal sexual abuse"),
        ReportReason(reason: ReportReasons.sexualOther, title: "Other sexual violence content"),
      ]),
    ReportCategory(
      key: .harassmentHate,
      title: "Harassment or hate",
      description: "Abusive or discriminatory behavior",
      options: [
        ReportReason(reason: ReportReasons.harassmentTroll, title: "Trolling"),
        ReportReason(reason: ReportReasons.harassmentTargeted, title: "Targeted harassment"),
        ReportReason(reason: ReportReasons.harassmentHateSpeech, title: "Hate speech"),
        ReportReason(reason: ReportReasons.harassmentDoxxing, title: "Doxxing"),
        ReportReason(
          reason: ReportReasons.harassmentOther, title: "Other harassing or hateful content"),
      ]),
    ReportCategory(
      key: .violencePhysicalHarm,
      title: "Violence",
      description: "Violent or threatening content",
      options: [
        ReportReason(reason: ReportReasons.violenceAnimal, title: "Animal welfare"),
        ReportReason(reason: ReportReasons.violenceThreats, title: "Threats or incitement"),
        ReportReason(
          reason: ReportReasons.violenceGraphicContent, title: "Graphic violent content"),
        ReportReason(reason: ReportReasons.violenceGlorification, title: "Glorification of violence"),
        ReportReason(reason: ReportReasons.violenceExtremistContent, title: "Extremist content"),
        ReportReason(reason: ReportReasons.violenceTrafficking, title: "Human trafficking"),
        ReportReason(reason: ReportReasons.violenceOther, title: "Other violent content"),
      ]),
    ReportCategory(
      key: .childSafety,
      title: "Child safety",
      description: "Harming or endangering minors",
      options: [
        ReportReason(
          reason: ReportReasons.childSafetyCSAM, title: "Child Sexual Abuse Material (CSAM)"),
        ReportReason(
          reason: ReportReasons.childSafetyGroom, title: "Grooming or predatory behavior"),
        ReportReason(
          reason: ReportReasons.childSafetyPrivacy, title: "Privacy violation of a minor"),
        ReportReason(
          reason: ReportReasons.childSafetyHarassment, title: "Minor harassment or bullying"),
        ReportReason(reason: ReportReasons.childSafetyOther, title: "Other child safety issue"),
      ]),
    ReportCategory(
      key: .selfHarm,
      title: "Self-harm or dangerous behaviors",
      description: "Harmful or high-risk activities",
      options: [
        ReportReason(
          reason: ReportReasons.selfHarmContent,
          title: "Content promoting or depicting self-harm"),
        ReportReason(reason: ReportReasons.selfHarmED, title: "Eating disorders"),
        ReportReason(
          reason: ReportReasons.selfHarmStunts, title: "Dangerous challenges or activities"),
        ReportReason(
          reason: ReportReasons.selfHarmSubstances, title: "Dangerous substances or drug abuse"),
        ReportReason(reason: ReportReasons.selfHarmOther, title: "Other dangerous content"),
      ]),
    ReportCategory(
      key: .ruleBreaking,
      title: "Breaking site rules",
      description: "Banned activities or security violations",
      options: [
        ReportReason(reason: ReportReasons.ruleSiteSecurity, title: "Hacking or system attacks"),
        ReportReason(
          reason: ReportReasons.ruleProhibitedSales,
          title: "Promoting or selling prohibited items or services"),
        ReportReason(reason: ReportReasons.ruleBanEvasion, title: "Banned user returning"),
        ReportReason(reason: ReportReasons.ruleOther, title: "Other network rule-breaking"),
      ]),
    ReportCategory(
      key: .other,
      title: "Other",
      description: "An issue not included in these options",
      options: [
        ReportReason(reason: ReportReasons.other, title: "Other")
      ]),
  ]

  /// The category with `key`.
  public static func category(_ key: ReportCategoryKey) -> ReportCategory {
    categories.first { $0.key == key }!
  }

  /// Every option across every category, flattened in catalog order.
  public static let allOptions: [ReportReason] = categories.flatMap(\.options)
}
