import Foundation

/// The accessibility identifiers the moderation surfaces expose.
///
/// One place for every string an XCUITest addresses, so a test bundle can import
/// the package and read them instead of repeating literals. The `app.moderation.`
/// prefix keeps them clear of the shell's `app.*` identifiers and of
/// `LoginAccessibility`'s.
public enum ModerationAccessibility {
  /// The content-label preferences screen.
  public static let contentLabelsScreen = "app.moderation.contentLabels"
  /// The muted-words list screen.
  public static let mutedWordsScreen = "app.moderation.mutedWords"
  /// The add/edit muted-word sheet.
  public static let mutedWordSheet = "app.moderation.mutedWords.sheet"
  /// The muted-word value field.
  public static let mutedWordField = "app.moderation.mutedWords.field"
  /// The muted-word sheet's submit button.
  public static let mutedWordSubmit = "app.moderation.mutedWords.submit"
  /// The muted-word sheet's validation line.
  public static let mutedWordValidation = "app.moderation.mutedWords.validation"
  /// The blocked-accounts list screen.
  public static let blockedAccountsScreen = "app.moderation.blockedAccounts"
  /// The muted-accounts list screen.
  public static let mutedAccountsScreen = "app.moderation.mutedAccounts"
  /// The labeler directory screen.
  public static let labelerServicesScreen = "app.moderation.labelers"
  /// The report dialog sheet.
  public static let reportSheet = "app.moderation.report"
  /// The report dialog's category step.
  public static let reportStepCategory = "app.moderation.report.step.category"
  /// The report dialog's reason step.
  public static let reportStepReason = "app.moderation.report.step.reason"
  /// The report dialog's details field.
  public static let reportDetailsField = "app.moderation.report.details"
  /// The report dialog's submit button.
  public static let reportSubmit = "app.moderation.report.submit"
  /// The report dialog's error banner.
  public static let reportError = "app.moderation.report.error"
  /// The report dialog's success state.
  public static let reportSuccess = "app.moderation.report.success"
  /// The report dialog's reportable-subject failure state.
  public static let reportInvalidSubject = "app.moderation.report.invalidSubject"

  /// The identifier for one account row, e.g. `app.moderation.row.at.did`.
  public static func accountRow(_ did: String) -> String {
    "app.moderation.row.\(did)"
  }

  /// The identifier for one label toggle row.
  public static func contentLabelRow(_ labelerDid: String, _ identifier: String) -> String {
    "app.moderation.label.\(labelerDid).\(identifier)"
  }

  /// The identifier for one label preference option button.
  public static func contentLabelOption(_ labelerDid: String, _ identifier: String, _ value: String)
    -> String
  {
    "app.moderation.label.\(labelerDid).\(identifier).\(value)"
  }

  /// The identifier for one mounted moderation surface fixture.
  public static func surface(_ name: String) -> String {
    "app.moderation.surface.\(name)"
  }
}
