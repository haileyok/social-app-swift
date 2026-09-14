import Foundation
import OnboardingLogic

/// The view-owned copy for the onboarding wizard.
///
/// This is the seam a String Catalog replaces later: every user-facing string on
/// an onboarding screen is read through one of these members, so swapping them
/// for `String(localized:)` calls is a single-file change and no view carries a
/// scattered literal.
///
/// Copy that `OnboardingLogic` already owns - the RN-sourced English strings in
/// ``OnboardingStrings`` and the interest display names in ``Interests`` - is
/// deferred to rather than restated, so a reworded message never has to be fixed
/// in two packages. What lives here is what the logic layer has no reason to
/// know about: titles, button labels, field placeholders and screen chrome.
///
/// Wording is ported from the RN sources named on each member
/// (`src/screens/Onboarding/**`).
public enum OnboardingCopy {

  // MARK: - Screen chrome

  /// The wizard's accessibility label (`Layout.tsx`).
  public static let dialogLabel = "Set up your account"
  /// The wizard's accessibility hint (`Layout.tsx`).
  public static let dialogHint = "Customizes your Bluesky experience"
  /// The back button's label (`Layout.tsx`).
  public static let backLabel = "Go back to previous step"
  /// The generic skip button label (`StepSuggestedAccounts`, and others).
  public static let skipLabel = "Skip"
  /// The skip button's accessibility label where the visible text is just
  /// "Skip" (`StepSuggestedAccounts`).
  public static let skipToNextLabel = "Skip to next step"

  /// The progress position line, from `OnboardingPosition` in `Layout.tsx`.
  ///
  /// - Parameters:
  ///   - index: The zero-based display index the wizard reports.
  ///   - total: How many steps the indicator shows.
  public static func stepPosition(_ index: Int, of total: Int) -> String {
    "Step \(index + 1) of \(total)"
  }

  // MARK: - Actions

  /// The primary action on most steps.
  public static let continueAction = "Continue"
  /// The retry action on a failed list load (`StepSuggestedAccounts`).
  public static let retryAction = "Retry"
  /// The bulk-follow action on the suggested-accounts step.
  public static let followAllAction = "Follow all"
  /// The primary action on the find-contacts intro (`StepFindContactsIntro`).
  public static let importContactsAction = "Import contacts"
  /// The advance action on the final value-proposition page (`StepFinished`).
  public static let nextAction = "Next"
  /// The final action once every value-proposition page has been shown.
  public static let letsGoAction = "Let's go!"

  // MARK: - Step: profile

  /// `StepProfile/index.tsx`.
  public static let profileTitle = "Give your profile a face"
  /// `StepProfile/index.tsx`.
  public static let profileDescription =
    "Help people know you're not a bot by uploading a picture or creating an avatar."
  /// The avatar picker's placeholder affordance.
  public static let profileAvatarAdd = "Add avatar"
  /// The avatar picker's accessibility label.
  public static let profileAvatarLabel = "Avatar preview"
  /// `StepProfile/index.tsx`.
  public static let profileAvatarUploadInstead = "Upload a photo instead"
  /// `StepProfile/index.tsx`.
  public static let profileAvatarCreateInstead = "Create an avatar instead"
  /// The display-name field's placeholder.
  public static let profileNamePlaceholder = "Display name"
  /// The display-name field's accessibility label.
  public static let profileNameLabel = "Display name"
  /// Shown under the field when the name exceeds the limit.
  public static let profileNameTooLong = "Display names can be at most 64 characters."

  // MARK: - Step: interests

  /// `StepInterests/index.tsx`.
  public static let interestsTitle = "What are your interests?"
  /// `StepInterests/index.tsx`, the ungated description.
  public static let interestsDescription = "We'll use this to help customize your experience."
  /// `StepInterests/index.tsx`, the `OnboardingInterestsRequiredEnable` copy.
  public static let interestsRequiredDescription =
    "Choose at least one. We'll use this to customize your experience. You can change these anytime."
  /// The chip group's accessibility label (`StepInterests/index.tsx`).
  public static let interestsGroupLabel = "Select your interests from the options below"

  // MARK: - Step: suggested accounts

  /// `StepSuggestedAccounts/index.tsx`.
  public static let suggestedAccountsTitle = "Suggested for you"
  /// `StepSuggestedStarterpacks/index.tsx`.
  public static let suggestedStarterPacksTitle = "Find people to follow"

  // MARK: - Step: find contacts

  /// `StepFindContactsIntro/index.tsx`.
  public static let findContactsTitle = "Bluesky is more fun with friends"
  /// `StepFindContactsIntro/index.tsx`.
  public static let findContactsDescription =
    "Find your friends on Bluesky by verifying your phone number and matching with your contacts. "
    + "We protect your information and you control what happens next."
  /// The contact-sync step's explanatory line.
  public static let findContactsSyncDescription =
    "We'll match your contacts to find people you already know on Bluesky."
  /// The primary action on the contact-sync step.
  public static let findContactsAllowAction = "Continue"
  /// Shown when contact sync cannot run on this device
  /// (`StepFindContactsIntro/index.tsx`).
  public static let findContactsUnavailable =
    "Contact sync is not available on this device, as the app is unable to access your contacts."

  // MARK: - Step: finished

  /// The celebration headline on the final step.
  public static let finishedTitle = "You're all set"
  /// The celebration's supporting line.
  public static let finishedDescription = "Welcome to Bluesky."

  /// The value-proposition pages, port of `useValuePropText` in
  /// `StepFinished/ValuePropositionPager.shared.tsx`.
  public static let valuePropositions: [(title: String, description: String)] = [
    (
      "Free your feed",
      "No more doomscrolling junk-filled algorithms. Find feeds that work for you, not against you."
    ),
    (
      "Find your people",
      "Ditch the trolls and clickbait. Find real people and conversations that matter to you."
    ),
    (
      "Forget the noise",
      "No ads, no invasive tracking, no engagement traps. Bluesky respects your time and attention."
    ),
  ]

  // MARK: - Derived copy

  /// The label for an interest tag, from the logic layer's display-name table.
  ///
  /// Falls back to the tag capitalized, matching `useInterestsDisplayNames`.
  public static func interestName(_ tag: String) -> String {
    Interests.displayNames[tag] ?? tag.capitalized
  }

  /// The message shown for a failed step write.
  public static func errorMessage(_ error: OnboardingError) -> String {
    OnboardingErrorPresentation.message(for: error)
  }
}
