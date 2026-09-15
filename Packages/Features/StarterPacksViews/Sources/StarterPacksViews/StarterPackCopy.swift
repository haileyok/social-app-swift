import Foundation
import StarterPacksLogic

/**
 The user-facing strings of the starter-pack surfaces.

 These are not yet wired into Lingui's message catalog - the RN app wraps each
 one in a `msg` macro, and the Swift port does the same job later. Keeping them
 in one type makes that a mechanical change and keeps the view bodies readable.
 */
public enum StarterPackCopy {
  /// The pack screen's title bar.
  public static let screenTitle = "Starter Pack"
  /// The people tab's label.
  public static let peopleTab = "People"
  /// The feeds tab's label.
  public static let feedsTab = "Feeds"
  /// The posts tab's label.
  public static let postsTab = "Posts"
  /// The tab shown when a pack has no backing list and no feeds.
  public static let aboutTab = "About"

  /// The suffix every pack stat line carries.
  public static let joinedVia = "joined Bluesky via this Starter Pack"
  /// The label above the member count on the people tab.
  public static let membersHeading = "People"
  /// Shown while the member list is empty on the first load.
  public static let membersEmptyTitle = "No members yet"
  /// The empty member list's explanatory line.
  public static let membersEmptyMessage =
    "Nobody has been added to this Starter Pack yet."
  /// Shown when the pack's backing list is missing but the viewer owns it.
  public static let deletedListTitle = "This Starter Pack is broken"
  /// The deleted-list explanation, port of the RN copy for the same state.
  public static let deletedListMessage =
    "This Starter Pack references a list that no longer exists."

  /// The join affordance's label.
  public static let joinAction = "Join"
  /// The label once the viewer is already in the pack.
  public static let joinedAction = "Joined"
  /// The leave affordance's label.
  public static let leaveAction = "Leave"
  /// The share affordance's label.
  public static let shareAction = "Share"
  /// The "follow everyone" bulk action.
  public static let followAllAction = "Follow All"
  /// The edit affordance on a pack the viewer owns.
  public static let editAction = "Edit"
  /// The copy-link action on web.
  public static let copyLinkAction = "Copy Link"
  /// The native share action.
  public static let shareLinkAction = "Share link"
  /// The QR sheet's action.
  public static let shareQRAction = "Share QR code"
  /// The QR card download action.
  public static let saveImageAction = "Save image"

  // MARK: - Share

  /// The share dialog's heading.
  public static let shareTitle = "Invite people to this Starter Pack!"
  /// The share dialog's explanatory line.
  public static let shareMessage =
    "Share this Starter Pack and help people join your community on Bluesky."
  /// The placeholder under the QR card while it is unavailable.
  public static let qrPlaceholderTitle = "QR code"
  /// The placeholder's explanatory line.
  public static let qrPlaceholderMessage = "The code will appear here."

  // MARK: - Landing

  /// The landing screen's "you'll follow these people right away" line.
  public static let landingFollowAll = "You\u{2019}ll follow these people right away"
  /// The landing screen's creator line prefix.
  public static let landingBy = "Starter Pack by"
  /// The landing screen's join action, which continues into sign-up.
  public static let landingJoinAction = "Join this Starter Pack"

  // MARK: - Wizard

  /// The details step's title bar.
  public static let wizardDetailsHeader = "Starter Pack"
  /// The people step's title bar.
  public static let wizardProfilesHeader = "Choose People"
  /// The feeds step's title bar.
  public static let wizardFeedsHeader = "Choose Feeds"
  /// The name field's label.
  public static let nameLabel = "Name"
  /// The name field's placeholder, from the RN `StepDetails` screen.
  public static let namePlaceholder = "e.g. Great Artists"
  /// The name field's remaining-characters counter suffix.
  public static let nameLimitSuffix = "characters remaining"
  /// The description field's label.
  public static let descriptionLabel = "Description"
  /// The description field's placeholder.
  public static let descriptionPlaceholder = "e.g. A starter pack of great artists"
  /// The people search field's placeholder.
  public static let searchPeoplePlaceholder = "Search for people"
  /// The feeds search field's placeholder.
  public static let searchFeedsPlaceholder = "Search for feeds"
  /// The wizard's empty search result line.
  public static let searchEmptyMessage = "Nobody was found. Try searching for someone else."
  /// The feeds step's empty search result line.
  public static let searchFeedsEmptyMessage = "No feeds were found."
  /// The edit-lists sheet's title.
  public static let editListsTitle = "Remove items"
  /// The edit-lists sheet's confirm action.
  public static let editListsDoneAction = "Done"
  /// The edit affordance with a count, e.g. "Edit (12)".
  public static func editAction(count: Int) -> String { "Edit (\(count))" }
  /// The people step's minimum-count notice, e.g. "Add 3 more to continue".
  public static func addMoreToContinue(remaining: Int) -> String {
    "Add \(remaining) more to continue"
  }
  /// The landing screen's remainder copy.
  public static func landingFollowRemainder(count: Int) -> String {
    "You\u{2019}ll follow these people and \(count) others"
  }
  /// The joined line's full sentence.
  public static func joinedLine(count: Int) -> String {
    "\(count) joined Bluesky via this Starter Pack"
  }
  /// The profile-row subtitle for a member.
  public static func memberSubtitle(handle: String) -> String { "@\(handle)" }
  /// The opted-out badge on a wizard row.
  public static func optedOutBadge(name: String) -> String { "\(name) opted out" }

  /// The wizard step's title bar, from the step itself.
  public static func wizardHeader(for step: StarterPackWizardStep) -> String {
    switch step {
    case .details: wizardDetailsHeader
    case .profiles: wizardProfilesHeader
    case .feeds: wizardFeedsHeader
    }
  }
}
