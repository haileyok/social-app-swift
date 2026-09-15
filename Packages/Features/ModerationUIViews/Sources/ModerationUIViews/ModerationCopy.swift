import Foundation
import ModerationUILogic

/// The view-owned copy for the moderation surfaces.
///
/// This is the seam a String Catalog replaces later: every user-facing string on
/// a moderation screen is read through one of these static members, so swapping
/// them for `String(localized:)` calls is a single-file change and no view
/// carries a scattered literal.
///
/// Copy that `ModerationUILogic` already owns is read from there rather than
/// restated: the report reason catalog's titles and descriptions come from
/// ``ReportReasonCatalog``, and the muted-word validation message comes from
/// ``MutedWordsEditor/emptyValueMessage``. This catalog adds only the chrome the
/// logic layer has no reason to know about.
public enum ModerationCopy {
  // MARK: - Content labels

  /// The content-label screen's title.
  public static let contentLabelsTitle = "Content & Media"
  /// The line under the content-label screen's title.
  public static let contentLabelsDescription =
    "Control what content you see and how it is shown to you."
  /// The heading above the global (app-defined) adult content rows.
  public static let globalLabelsHeading = "Adult content"
  /// The notice shown when adult content is disabled, which hides the global rows.
  public static let adultContentOffNotice =
    "Adult content is disabled. Enable it to configure these labels."
  /// The heading above a labeler's rows.
  public static func labelerHeading(_ title: String) -> String { title }
  /// The notice on a row whose labeler the viewer is not subscribed to.
  public static let notSubscribedNotice = "Subscribe to this labeler to configure its labels."
  /// The notice on a row that cannot be changed here.
  public static let staticValueNotice = "This label is configured on the moderation screen."
  /// The notice on an adult row while adult content is off.
  public static let adultDisabledNotice = "Enable adult content to change this label."

  /// The option labels for a label preference, keyed by the wire value.
  public static let showOption = "Show"
  public static let warnOption = "Warn"
  public static let hideOption = "Hide"

  /// The localized option label for a preference.
  public static func optionLabel(_ preference: String) -> String {
    switch preference {
    case "ignore": return showOption
    case "warn": return warnOption
    case "hide": return hideOption
    default: return preference
    }
  }

  /// The display name for a label identifier.
  ///
  /// The `labels` table in `Moderation` carries no display name (it is the
  /// engine's definition table), so the four global labels are named here and
  /// anything else falls back to a humanized form of its identifier. That
  /// fallback is what a labeler-defined label shows until the labeler supplies
  /// a localized title of its own.
  public static func labelTitle(_ identifier: String) -> String {
    switch identifier {
    case "porn": return "Adult content"
    case "sexual": return "Sexually suggestive"
    case "graphic-media": return "Graphic media"
    case "nudity": return "Nudity"
    default: return humanize(identifier)
    }
  }

  /// Turns `graphic-media` or `fooBar` into a readable title.
  static func humanize(_ identifier: String) -> String {
    let source = identifier.hasPrefix("!") ? String(identifier.dropFirst()) : identifier
    var words: [String] = []
    var current = ""
    for character in source {
      if character == "-" || character == "_" {
        if !current.isEmpty { words.append(current) }
        current = ""
      } else if character.isUppercase, !current.isEmpty {
        words.append(current)
        current = String(character)
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty { words.append(current) }
    let joined = words.joined(separator: " ")
    guard let first = joined.first else { return identifier }
    return first.uppercased() + joined.dropFirst()
  }

  // MARK: - Muted words

  /// The muted-words screen's title.
  public static let mutedWordsTitle = "Muted words & tags"
  /// The line under the muted-words screen's title.
  public static let mutedWordsDescription =
    "Muted words are hidden from your feeds and notifications."
  /// The empty-state title.
  public static let mutedWordsEmptyTitle = "No muted words"
  /// The empty-state message.
  public static let mutedWordsEmptyMessage = "Add a word, tag, or phrase to mute."
  /// The add button.
  public static let addMutedWordAction = "Add"
  /// The value field's placeholder.
  public static let mutedWordPlaceholder = "Enter a word, tag, or phrase"
  /// The value field's accessibility label.
  public static let mutedWordFieldLabel = "Word or phrase to mute"
  /// The submit button on the add sheet.
  public static let saveMutedWordAction = "Save"
  /// The heading above the surfaces radio.
  public static let mutedWordTargetsHeading = "Mute in"
  /// The "Text & tags" surface label.
  public static let targetContentLabel = "Text & tags"
  /// The "Tags only" surface label.
  public static let targetTagLabel = "Tags only"
  /// The heading above the duration radio.
  public static let mutedWordDurationHeading = "Duration"
  /// The `excludeFollowing` switch label.
  public static let excludeFollowingLabel = "Exclude users you follow"
  /// The prefix on a row that applies to post text as well as tags.
  public static let appliesToContentBadge = "Text & tags"
  /// The badge on a row that skips followed users.
  public static let excludesFollowingBadge = "Not following"
  /// The badge on an expired row.
  public static let expiredBadge = "Expired"

  /// The expiry line on a row that is still live.
  ///
  /// Formatted with the current locale rather than a fixed pattern, so the date
  /// reads the way the rest of the app renders dates.
  public static func expiryLine(_ date: Date) -> String {
    let formatted = date.formatted(date: .abbreviated, time: .shortened)
    return "Expires \(formatted)"
  }

  /// The remove action on a row.
  public static let removeMutedWordAction = "Remove"
  /// The confirmation message for a removal.
  public static func removeMutedWordConfirmation(_ word: String) -> String {
    "Remove “\(word)” from your muted words?"
  }

  /// The duration labels, keyed by ``MutedWordDuration``.
  public static func durationLabel(_ duration: MutedWordDuration) -> String {
    switch duration {
    case .forever: return "Forever"
    case .hours24: return "24 hours"
    case .days7: return "7 days"
    case .days30: return "30 days"
    }
  }

  // MARK: - Accounts

  /// The blocked-accounts screen's title.
  public static let blockedAccountsTitle = "Blocked accounts"
  /// The blocked-accounts screen's description.
  public static let blockedAccountsDescription =
    "Blocked accounts cannot see or interact with your content."
  /// The blocked-accounts empty title.
  public static let blockedAccountsEmptyTitle = "No blocked accounts"
  /// The blocked-accounts empty message.
  public static let blockedAccountsEmptyMessage =
    "Accounts you block will show up here."
  /// The muted-accounts screen's title.
  public static let mutedAccountsTitle = "Muted accounts"
  /// The muted-accounts screen's description.
  public static let mutedAccountsDescription =
    "Muted accounts are hidden from your feeds and notifications."
  /// The muted-accounts empty title.
  public static let mutedAccountsEmptyTitle = "No muted accounts"
  /// The muted-accounts empty message.
  public static let mutedAccountsEmptyMessage = "Accounts you mute will show up here."
  /// The unblock action.
  public static let unblockAction = "Unblock"
  /// The unmute action.
  public static let unmuteAction = "Unmute"

  // MARK: - Labelers

  /// The labeler directory screen's title.
  public static let labelerServicesTitle = "Labelers"
  /// The labeler directory screen's description.
  public static let labelerServicesDescription =
    "Labelers provide additional moderation for the content you see."
  /// The subscribed section heading.
  public static let subscribedLabelersHeading = "Subscribed"
  /// The all-labelers section heading.
  public static let allLabelersHeading = "Available labelers"
  /// The subscribe action.
  public static let subscribeAction = "Subscribe"
  /// The unsubscribe action.
  public static let unsubscribeAction = "Unsubscribe"
  /// The labelers empty state title.
  public static let labelersEmptyTitle = "No labelers"
  /// The labelers empty state message.
  public static let labelersEmptyMessage = "Labelers you can subscribe to will show up here."
  /// The failure copy when the labeler cap is reached.
  public static let maxLabelersMessage =
    "You have reached the maximum number of subscribed labelers. Unsubscribe from one to add another."
  /// The section heading for labelers whose subscription no longer resolves.
  public static let unavailableLabelersHeading = "Unavailable"

  // MARK: - Report dialog

  /// The report dialog's submit action.
  public static let submitReportAction = "Submit report"
  /// The report dialog's cancel action.
  public static let cancelAction = "Cancel"
  /// The report dialog's details placeholder.
  public static let reportDetailsPlaceholder = "Add more details (optional)"
  /// The report dialog's details heading.
  public static let reportDetailsHeading = "Add more details (optional)"
  /// The report dialog's back action.
  public static let backAction = "Back"
  /// The report dialog's success title.
  public static let reportSuccessTitle = "Report submitted"
  /// The report dialog's success message.
  public static let reportSuccessMessage = "Thanks for your report."
  /// The report dialog's generic failure copy.
  public static let reportFailureMessage = "Something went wrong, please try again"
  /// The report dialog's retry action.
  public static let reportRetryAction = "Retry"
  /// Shown when the subject handed to the dialog is not reportable.
  public static let invalidReportSubjectTitle = "Invalid report subject"
  /// The follow-on line for an invalid subject.
  public static let invalidReportSubjectMessage =
    "This content cannot be reported right now."

  /// The dialog's title and subtitle for a subject, port of `useCopyForSubject`.
  public static func reportCopy(for subject: ParsedReportSubject) -> (title: String, subtitle: String)
  {
    switch ReportFlow.subjectTypeName(subject) {
    case "account":
      return ("Report this user", "Why should this user be reviewed?")
    case "status":
      return ("Report this livestream", "Why should this livestream be reviewed?")
    case "post":
      return ("Report this post", "Why should this post be reviewed?")
    case "list":
      return ("Report this list", "Why should this list be reviewed?")
    case "feed":
      return ("Report this feed", "Why should this feed be reviewed?")
    case "starterPack":
      return ("Report this Starter Pack", "Why should this Starter Pack be reviewed?")
    case "convoMessage":
      return ("Report this message", "Why should this message be reviewed?")
    case "convo":
      return ("Report this conversation", "Why should this conversation be reviewed?")
    default:
      return ("Report", "Why should this be reviewed?")
    }
  }

  /// The user-facing line for a classified report failure.
  ///
  /// The `unexpected` bucket deliberately does not restate the server text: RN
  /// shows one generic line for it, and the bucket is what the telemetry hook
  /// forwards.
  public static func reportErrorMessage(_ classification: ReportErrorClassification) -> String {
    switch classification.kind {
    case .accountTakedown:
      return "Your account has been taken down and cannot submit reports."
    case .invalidReasonType:
      return "This reason is not supported by the selected moderation service."
    case .serviceUnavailable:
      return reportFailureMessage
    case .unexpected:
      return reportFailureMessage
    }
  }
}
