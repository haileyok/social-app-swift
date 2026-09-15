/**
 Accessibility identifiers for the settings surfaces.

 Names are dot-scoped (`settings.*`) so a `descendants(matching:).matching(identifier:)`
 lookup cannot collide with the shell's `app.*` identifiers or the login flow's
 `login.*` ones.
 */
public enum SettingsAccessibility {
  /// The settings root list.
  public static let root = "settings.root"

  /// The appearance screen's container.
  public static let appearance = "settings.appearance"
  /// The colour-mode picker.
  public static let colorModePicker = "settings.appearance.colorMode"
  /// The dark-theme picker.
  public static let darkThemePicker = "settings.appearance.darkTheme"
  /// The font-scale picker.
  public static let fontScalePicker = "settings.appearance.fontScale"
  /// The font-family picker.
  public static let fontFamilyPicker = "settings.appearance.fontFamily"

  /// The app-passwords list.
  public static let appPasswords = "settings.appPasswords"
  /// The "add app password" toolbar control.
  public static let addAppPasswordButton = "settings.appPasswords.add"
  /// One app-password row, suffixed by its name.
  public static func appPasswordRow(_ name: String) -> String {
    "settings.appPasswords.row.\(name)"
  }
  /// The revoke control for one app-password row.
  public static func appPasswordRevoke(_ name: String) -> String {
    "settings.appPasswords.revoke.\(name)"
  }
  /// The create sheet.
  public static let createAppPasswordSheet = "settings.appPasswords.create"
  /// The name field inside the create sheet.
  public static let appPasswordNameField = "settings.appPasswords.create.name"
  /// The create sheet's submit button.
  public static let appPasswordSubmitButton = "settings.appPasswords.create.submit"
  /// The inline validation message inside the create sheet.
  public static let appPasswordError = "settings.appPasswords.create.error"
  /// The one-time plaintext password screen.
  public static let appPasswordCreatedSheet = "settings.appPasswords.created"

  /// The saved-feeds editor.
  public static let savedFeeds = "settings.savedFeeds"
  /// The saved-feeds save control.
  public static let savedFeedsSaveButton = "settings.savedFeeds.save"
  /// One saved-feed row, suffixed by its id.
  public static func savedFeedRow(_ id: String) -> String {
    "settings.savedFeeds.row.\(id)"
  }
  /// The pin toggle for one saved-feed row.
  public static func savedFeedPin(_ id: String) -> String {
    "settings.savedFeeds.pin.\(id)"
  }

  /// The following-feed preferences screen.
  public static let followingFeed = "settings.followingFeed"
  /// One following-feed toggle, suffixed by the field name.
  public static func followingFeedToggle(_ field: String) -> String {
    "settings.followingFeed.\(field)"
  }

  /// The thread preferences screen.
  public static let threads = "settings.threads"
  /// The reply-sort picker.
  public static let threadSortPicker = "settings.threads.sort"
  /// The tree-view toggle.
  public static let threadTreeViewToggle = "settings.threads.treeView"

  /// The content-and-media screen.
  public static let contentAndMedia = "settings.contentAndMedia"
  /// The adult-content toggle.
  public static let adultContentToggle = "settings.contentAndMedia.adultContent"
  /// One label-matrix row, suffixed by its label identifier.
  public static func labelRow(_ identifier: String) -> String {
    "settings.contentAndMedia.label.\(identifier)"
  }

  /// The language screen.
  public static let language = "settings.language"
  /// The UI-language picker.
  public static let appLanguagePicker = "settings.language.appLanguage"
  /// The primary-language picker.
  public static let primaryLanguagePicker = "settings.language.primaryLanguage"

  /// The account screen.
  public static let account = "settings.account"
  /// The change-handle sheet.
  public static let changeHandleSheet = "settings.account.changeHandle"
  /// The subdomain field inside the change-handle sheet.
  public static let changeHandleSubdomainField = "settings.account.changeHandle.subdomain"
  /// The custom-domain field inside the change-handle sheet.
  public static let changeHandleDomainField = "settings.account.changeHandle.domain"
  /// The delete-account sheet.
  public static let deleteAccountSheet = "settings.account.deleteAccount"
  /// The deactivate-account sheet.
  public static let deactivateAccountSheet = "settings.account.deactivate"
  /// The export sheet.
  public static let exportSheet = "settings.account.export"

  /// The privacy-and-security screen.
  public static let privacyAndSecurity = "settings.privacyAndSecurity"
}
