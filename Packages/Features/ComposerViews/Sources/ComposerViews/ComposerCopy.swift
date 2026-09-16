import ComposerLogic

/// The view-owned copy for the composer, and the seam a String Catalog replaces
/// later.
///
/// Every user-facing string on a composer surface is read through one of these
/// static members, so swapping them for `String(localized:)` calls is a
/// single-file change and no view carries a scattered literal. The same
/// arrangement ``LoginCopy`` uses.
///
/// Two rules carried over from the login screen:
///
/// 1. Where `ComposerLogic` already owns RN-sourced English text, the copy
///    defers to it rather than restating it (``validationMessage(_:)`` reads the
///    logic layer's error case). A reworded message is then fixed in one place.
/// 2. The catalog carries only what the logic layer has no reason to know:
///    button labels, field placeholders, sheet chrome.
public enum ComposerCopy {
  // MARK: - Screen chrome

  /// The composer screen's title for a new post.
  public static let newPostTitle = "New post"
  /// The composer screen's title when composing a reply.
  public static let replyTitle = "Reply"
  /// The title when the composer was opened to quote another post.
  public static let quoteTitle = "Quote post"
  /// The publish action ("Post" / "Post all" as the thread grows).
  public static let postAction = "Post"
  /// The publish action for a multi-post thread.
  public static let postAllAction = "Post all"
  /// The dismiss control.
  public static let cancelAction = "Cancel"
  /// The action that inserts another post into the thread.
  public static let addPostAction = "Add another post"
  /// The action removing a post from the thread.
  public static let removePostAction = "Remove post"

  // MARK: - Editor

  /// The text field's placeholder on the first post.
  public static let textPlaceholder = "What's up?"
  /// The placeholder for a continuation post in a thread.
  public static let continuationPlaceholder = "Add another post…"
  /// The placeholder for a post that only carries an image.
  public static let imagePlaceholder = "Describe the image…"
  /// The alt-text field's accessibility label.
  public static let altTextLabel = "Alt text"
  /// The alt-text field's placeholder.
  public static let altTextPlaceholder = "Describe this image"
  /// Guidance shown while one or more attached images do not have alt text.
  public static let altTextHelp =
    "Alt text describes images for blind and low-vision users, and gives context to everyone."
  /// The character counter's accessibility label prefix.
  public static let characterCountLabel = "Characters remaining"

  // MARK: - Attachments

  /// The label on the media add control.
  public static let addMediaAction = "Add media"
  /// The gallery header.
  public static let galleryTitle = "Gallery"
  /// The remove control on one attached image.
  public static let removeImageAction = "Remove image"
  /// The remove control on the video attachment.
  public static let removeVideoAction = "Remove video"
  /// The label on the video attach row while the pipeline is idle.
  public static let videoLabel = "Video"
  /// The video's alt-text field placeholder.
  public static let videoAltPlaceholder = "Describe this video"
  /// The caption-track add control.
  public static let addCaptionsAction = "Add captions"
  /// The person-placeholder label for a GIF's alt text.
  public static let gifAltPlaceholder = "Describe this GIF"

  // MARK: - Context

  /// The reply context header's leading label.
  public static let replyingToLabel = "Replying to"
  /// The quote context header's leading label.
  public static let quotingLabel = "Quoting"
  /// The label above the link card row.
  public static let linkCardLabel = "Link card"
  /// The remove control on the link card and the quote header.
  public static let removeAction = "Remove"

  // MARK: - Sheets

  /// The language picker's title.
  public static let languageTitle = "Post languages"
  /// The language picker's add control.
  public static let addLanguageAction = "Add language"
  /// The language field's placeholder.
  public static let languagePlaceholder = "Language code (e.g. en)"
  /// The self-labels sheet's title.
  public static let labelsTitle = "Content warnings"
  /// The self-labels sheet's explanatory line.
  public static let labelsDescription = "Add warnings to your post."
  /// The threadgate sheet's title.
  public static let threadgateTitle = "Who can reply"
  /// The threadgate sheet's explanatory line.
  public static let threadgateDescription = "Choose who can reply to this thread."
  /// The postgate toggle's label in the threadgate sheet.
  public static let postgateLabel = "Allow quote posts"
  /// The threadgate sheet's confirm control.
  public static let saveAction = "Save"

  // MARK: - Publish

  /// The progress label while the thread publishes.
  public static let publishingLabel = "Posting…"
  /// The generic publish failure line.
  public static let publishFailed = "Could not publish your post. Try again."
  /// The retry control on the failure banner.
  public static let retryAction = "Try again"
  /// The toast shown after a successful publish.
  public static let publishedToast = "Your post was sent"

  // MARK: - Drafts

  /// The save-as-draft control.
  public static let saveDraftAction = "Save draft"
  /// The drafts sheet's title.
  public static let draftsTitle = "Drafts"
  /// The empty-drafts line.
  public static let draftsEmpty = "No drafts yet"
  /// The delete control on a draft row.
  public static let deleteDraftAction = "Delete draft"
  /// Shown when the account is at its draft limit.
  public static let draftLimitReached = "You have reached the draft limit."
  /// Shown when a draft could not be saved.
  public static let draftSaveFailed = "Could not save your draft."

  // MARK: - Validation

  /// The user-facing line for a validation failure.
  ///
  /// The composer's own validation is the source of truth; this only phrases it.
  /// `nil` (a publishable thread) has no line.
  public static func validationMessage(_ error: ComposerValidationError?) -> String? {
    switch error {
    case nil: nil
    case .imageMissingAltText: "One or more images is missing alt text."
    case .gifMissingAltText: "One or more GIFs is missing alt text."
    case .videoMissingAltText: "One or more videos is missing alt text."
    case .unavailableChatInvite: "One or more chat invites are unavailable."
    case .postOverGraphemeLimit: "One or more posts is too long."
    case .videoFailed: "One or more videos failed to process."
    case .nothingToPost: "Write something to post."
    }
  }

  /// The confirmation line shown when a thread has a non-trailing empty post.
  public static let nonTrailingEmptyPost =
    "One of your posts is empty. Publish anyway?"

  /// The label for a reply-permission setting.
  public static func threadgateLabel(_ setting: ThreadgateAllowUISetting) -> String {
    switch setting {
    case .everybody: "Everybody"
    case .nobody: "Nobody"
    case .mention: "Mentioned users"
    case .following: "People you follow"
    case .followers: "Your followers"
    case .list: "Users in a list"
    }
  }

  /// The label for a self-label value.
  public static func label(_ value: String) -> String {
    switch value {
    case "sexual": "Sexually suggestive"
    case "nudity": "Nudity"
    case "porn": "Adult content"
    case "graphic-media": "Graphic media"
    default: value
    }
  }

  /// The status line for a video pipeline phase.
  public static func videoStatus(_ status: String) -> String {
    switch status {
    case "compressing": "Compressing…"
    case "uploading": "Uploading…"
    case "processing": "Processing…"
    case "done": "Ready"
    case "error": "Could not process this video"
    default: "Preparing…"
    }
  }
}
