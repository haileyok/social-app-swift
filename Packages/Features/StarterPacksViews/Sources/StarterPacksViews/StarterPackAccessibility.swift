/**
 Stable accessibility identifiers for the starter-pack surfaces.

 Mirrors `LoginAccessibility`: XCUITest bundles link only the AppShell product,
 so the identifiers live in the package that owns the views and the app
 re-exports them rather than duplicating string literals in a test.
 */
public enum StarterPackAccessibility {
  /// The pack detail screen's root.
  public static let screen = "starterPack.screen"
  /// The pack header.
  public static let header = "starterPack.header"
  /// The header's joined-count line.
  public static let joinedLine = "starterPack.joinedLine"
  /// The tab bar.
  public static let tabBar = "starterPack.tabBar"
  /// The people tab.
  public static let peopleTab = "starterPack.tab.people"
  /// The feeds tab.
  public static let feedsTab = "starterPack.tab.feeds"
  /// The posts tab.
  public static let postsTab = "starterPack.tab.posts"
  /// The member collection.
  public static let memberList = "starterPack.members"
  /// The join button.
  public static let joinButton = "starterPack.joinButton"
  /// The share button.
  public static let shareButton = "starterPack.shareButton"
  /// The edit button, shown to a pack's owner.
  public static let editButton = "starterPack.editButton"
  /// The follow-all button.
  public static let followAllButton = "starterPack.followAllButton"

  /// The broken-pack state shown to an owner whose list is gone.
  public static let deletedListState = "starterPack.deletedListState"

  // MARK: - Share

  /// The share sheet's root.
  public static let shareSheet = "starterPack.shareSheet"
  /// The QR card surface.
  public static let qrCard = "starterPack.qrCard"
  /// The QR placeholder shown when no card is available.
  public static let qrPlaceholder = "starterPack.qrPlaceholder"
  /// The share-link button.
  public static let shareLinkButton = "starterPack.shareLinkButton"
  /// The share-QR button.
  public static let shareQRButton = "starterPack.shareQRButton"
  /// The save-image button.
  public static let saveImageButton = "starterPack.saveImageButton"
  /// The share sheet's loading state.
  public static let shareLoading = "starterPack.shareLoading"

  // MARK: - Landing

  /// The logged-out landing screen's root.
  public static let landingScreen = "starterPack.landingScreen"
  /// The landing screen's join action.
  public static let landingJoinButton = "starterPack.landing.joinButton"

  // MARK: - Wizard

  /// The wizard's root.
  public static let wizard = "starterPack.wizard"
  /// The wizard's step title.
  public static let wizardTitle = "starterPack.wizard.title"
  /// The wizard's step indicator.
  public static let wizardSteps = "starterPack.wizard.steps"
  /// The details step.
  public static let detailsStep = "starterPack.wizard.details"
  /// The name field.
  public static let nameField = "starterPack.wizard.nameField"
  /// The description field.
  public static let descriptionField = "starterPack.wizard.descriptionField"
  /// The profiles step.
  public static let profilesStep = "starterPack.wizard.profiles"
  /// The profiles search field.
  public static let profilesSearchField = "starterPack.wizard.profiles.search"
  /// The feeds step.
  public static let feedsStep = "starterPack.wizard.feeds"
  /// The feeds search field.
  public static let feedsSearchField = "starterPack.wizard.feeds.search"
  /// The wizard footer's step counter.
  public static let footerCounter = "starterPack.wizard.counter"
  /// The wizard's back button.
  public static let backButton = "starterPack.wizard.backButton"
  /// The wizard's next/finish button.
  public static let nextButton = "starterPack.wizard.nextButton"
  /// The wizard's edit-lists button.
  public static let wizardEditButton = "starterPack.wizard.editButton"
  /// The wizard's inline error line.
  public static let inlineError = "starterPack.wizard.error"
  /// The wizard's edit-lists sheet.
  public static let editSheet = "starterPack.wizard.editSheet"
  /// A row in the wizard's edit-lists sheet.
  public static func editSheetRow(_ id: String) -> String {
    "starterPack.wizard.editSheet.row.\(id)"
  }

  /// A member row, keyed by the member's DID.
  public static func memberRow(_ did: String) -> String { "starterPack.member.\(did)" }
  /// A feed row, keyed by the generator's rkey.
  public static func feedRow(_ rkey: String) -> String { "starterPack.feed.\(rkey)" }
  /// A wizard search result row, keyed by DID or URI.
  public static func searchRow(_ id: String) -> String { "starterPack.search.\(id)" }
}
