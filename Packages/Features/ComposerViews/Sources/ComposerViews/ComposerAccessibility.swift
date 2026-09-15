/**
 Accessibility identifiers for the composer surfaces.

 The XCUITest target links `AppShell`, which re-exports this package, so the app
 and the test read the same constants instead of duplicating string literals -
 the same arrangement `LoginAccessibility` uses. Names are dot-scoped
 (`composer.*`) so a `descendants(matching:).matching(identifier:)` lookup cannot
 collide with the shell's `app.*` or the login screens' `login.*` identifiers.
 */
public enum ComposerAccessibility {
  /// The composer screen's content container.
  public static let screen = "composer.screen"
  /// The active post's text editor.
  public static let textEditor = "composer.textEditor"
  /// The character/grapheme counter.
  public static let characterCounter = "composer.counter"
  /// The validation line beneath the editor.
  public static let validationMessage = "composer.validation"
  /// The publish button.
  public static let publishButton = "composer.publish"
  /// The cancel/dismiss control.
  public static let cancelButton = "composer.cancel"
  /// The add-another-post control.
  public static let addPostButton = "composer.addPost"
  /// The media attach control.
  public static let addMediaButton = "composer.addMedia"

  /// One attached image's row, suffixed by its id.
  public static func imageRow(_ id: String) -> String { "composer.image.\(id)" }
  /// One image's alt-text field, suffixed by its id.
  public static func imageAltField(_ id: String) -> String { "composer.image.alt.\(id)" }
  /// One image's remove control, suffixed by its id.
  public static func imageRemove(_ id: String) -> String { "composer.image.remove.\(id)" }

  /// The video attach row.
  public static let videoRow = "composer.video"
  /// The video's alt-text field.
  public static let videoAltField = "composer.video.alt"
  /// The video's remove control.
  public static let videoRemove = "composer.video.remove"
  /// The video progress indicator.
  public static let videoProgress = "composer.video.progress"

  /// The reply context header.
  public static let replyHeader = "composer.context.reply"
  /// The quote context header.
  public static let quoteHeader = "composer.context.quote"
  /// The link card row.
  public static let linkCardRow = "composer.linkCard"

  /// The language picker control that opens the sheet.
  public static let languageButton = "composer.language"
  /// The presented language sheet.
  public static let languageSheet = "composer.language.sheet"
  /// The language sheet's add-code field.
  public static let languageField = "composer.language.field"

  /// The self-labels control that opens the sheet.
  public static let labelsButton = "composer.labels"
  /// The presented self-labels sheet.
  public static let labelsSheet = "composer.labels.sheet"
  /// One self-label toggle, suffixed by its value.
  public static func labelToggle(_ value: String) -> String { "composer.labels.\(value)" }

  /// The threadgate control that opens the sheet.
  public static let threadgateButton = "composer.threadgate"
  /// The presented threadgate sheet.
  public static let threadgateSheet = "composer.threadgate.sheet"
  /// One reply-permission row, suffixed by the setting's storage key.
  public static func threadgateOption(_ key: String) -> String {
    "composer.threadgate.\(key)"
  }
  /// The postgate (quoting) toggle inside the threadgate sheet.
  public static let postgateToggle = "composer.threadgate.postgate"

  /// The publish progress banner.
  public static let publishProgress = "composer.publishProgress"
  /// The publish failure banner.
  public static let publishError = "composer.publishError"
  /// The retry control on the failure banner.
  public static let publishRetry = "composer.publishRetry"

  /// The save-as-draft control.
  public static let saveDraftButton = "composer.saveDraft"
  /// The drafts control that opens the drafts sheet.
  public static let draftsButton = "composer.drafts"
  /// The presented drafts sheet.
  public static let draftsSheet = "composer.drafts.sheet"
  /// One draft row, suffixed by its id.
  public static func draftRow(_ id: String) -> String { "composer.drafts.\(id)" }
}
