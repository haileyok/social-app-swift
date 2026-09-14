import Foundation

/// Accessibility identifiers shared by the onboarding views and any future UI
/// test bundle.
///
/// The RN screens carry `testID`s (`onboardingContinue`,
/// `onboardingInterests`); these keep the same names where one exists so a
/// ported UI test can find the control, and add identifiers for the chrome the
/// wizard introduces.
public enum OnboardingAccessibility {
  /// The wizard's root container (RN `role="dialog"`).
  public static let screen = "onboarding.screen"
  /// The per-step content container.
  public static let stepContainer = "onboarding.stepContainer"
  /// The `OnboardingPosition` progress label.
  public static let position = "onboarding.position"
  /// The header's back button (`Layout.tsx`).
  public static let back = "onboarding.back"
  /// The footer area holding the step's primary controls (`OnboardingControls`).
  public static let footer = "onboarding.footer"

  /// The profile step's container.
  public static let profileStep = "onboarding.profileStep"
  /// The profile step's continue button (RN `onboardingContinue`).
  public static let profileContinue = "onboardingContinue"
  /// The profile step's display-name field.
  public static let profileNameField = "onboarding.displayName"
  /// The profile step's avatar picker (RN `onboardingAvatarCreator`).
  public static let profileAvatarPicker = "onboardingAvatarCreator"

  /// The interests step's container (RN `onboardingInterests`).
  public static let interestsStep = "onboardingInterests"
  /// The interests step's continue button.
  public static let interestsContinue = "onboarding.interestsContinue"
  /// The interests chip group.
  public static let interestsGroup = "onboarding.interestsGroup"
  /// The identifier for one interest chip, keyed by the wire tag.
  public static func interestChip(_ tag: String) -> String { "onboarding.interest.\(tag)" }

  /// The suggested-accounts step's container.
  public static let suggestedAccountsStep = "onboarding.suggestedAccountsStep"
  /// The suggested-accounts step's follow-all button.
  public static let suggestedAccountsFollowAll = "onboarding.followAll"
  /// The suggested-accounts step's continue button.
  public static let suggestedAccountsContinue = "onboarding.suggestedAccountsContinue"
  /// The identifier for one suggested-account row, keyed by DID.
  public static func suggestedAccountRow(_ did: String) -> String {
    "onboarding.suggestedAccount.\(did)"
  }

  /// The starter-packs step's container.
  public static let starterPacksStep = "onboarding.starterPacksStep"
  /// The starter-packs step's continue button.
  public static let starterPacksContinue = "onboarding.starterPacksContinue"
  /// The identifier for one starter-pack row, keyed by AT URI.
  public static func starterPackRow(_ uri: String) -> String { "onboarding.starterPack.\(uri)" }

  /// The find-contacts intro step.
  public static let findContactsIntroStep = "onboarding.findContactsIntroStep"
  /// The find-contacts intro's import button.
  public static let findContactsImport = "onboarding.findContactsImport"
  /// The find-contacts step.
  public static let findContactsStep = "onboarding.findContactsStep"
  /// The find-contacts step's allow button.
  public static let findContactsAllow = "onboarding.findContactsAllow"
  /// The find-contacts step's skip button.
  public static let findContactsSkip = "onboarding.findContactsSkip"

  /// The finished step's container.
  public static let finishedStep = "onboarding.finishedStep"
  /// The finished step's advance button.
  public static let finishedNext = "onboarding.finishedNext"
  /// The finished step's skip button.
  public static let finishedSkip = "onboarding.finishedSkip"
  /// The value-proposition pager.
  public static let finishedPager = "onboarding.valuePropPager"
  /// The page indicator for one value-proposition page, keyed by index.
  public static func finishedPage(_ index: Int) -> String { "onboarding.valueProp.\(index)" }
}
