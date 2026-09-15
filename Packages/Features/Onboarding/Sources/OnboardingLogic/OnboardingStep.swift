import Foundation

/// The ordered steps of the onboarding wizard.
///
/// Port of the `OnboardingScreen` union in `screens/Onboarding/state.ts`. The
/// raw values are the RN strings so persisted progress written by a future
/// cross-platform store stays legible.
public enum OnboardingStep: String, Sendable, CaseIterable, Codable, Hashable {
  case profile
  case interests
  case suggestedAccounts = "suggested-accounts"
  case suggestedStarterPacks = "suggested-starterpacks"
  case findContactsIntro = "find-contacts-intro"
  case findContacts = "find-contacts"
  case finished
}

/// Whether a step can be left without doing its work.
///
/// RN does not carry an explicit flag: "skippable" is a property of each
/// screen's controls. It is modelled here because the wizard needs to answer
/// "can this step be bypassed" without knowing about a view.
public enum StepSkippability: Sendable, Equatable {
  /// The step must be completed before advancing.
  case required
  /// The step can be advanced past without completing it.
  case skippable
}

/// Static description of one step: its identity plus the policy the state
/// machine applies to it.
public struct OnboardingStepDefinition: Sendable, Equatable {
  /// Which step this describes.
  public let step: OnboardingStep
  /// Whether the step can be skipped.
  public let skippability: StepSkippability
  /// Whether the step is presentation-only, so it does not count toward the
  /// progress indicator. RN's `getStepOrder` excludes `find-contacts` and
  /// `finished` from the display index.
  public let countsTowardProgress: Bool

  /// Creates a definition.
  public init(
    step: OnboardingStep,
    skippability: StepSkippability,
    countsTowardProgress: Bool = true
  ) {
    self.step = step
    self.skippability = skippability
    self.countsTowardProgress = countsTowardProgress
  }
}

/// The step definitions, in the RN order.
///
/// `profile`, `interests`, `suggested-accounts`, and `finished` are always
/// present. `suggested-starterpacks` and the two `find-contacts` steps are
/// gated (see ``OnboardingStepConfiguration``).
///
/// Skippability is taken from each screen's controls:
/// - `profile` and `interests` only offer Continue (interests can be empty
///   unless the required-interests feature gate is on, which is a runtime
///   policy, not a step policy).
/// - `suggested-accounts` and `suggested-starterpacks` render a Skip button.
/// - `find-contacts-intro` and `find-contacts` are skippable as a unit.
public enum OnboardingSteps {
  /// Every definition, in flow order.
  public static let all: [OnboardingStepDefinition] = [
    OnboardingStepDefinition(step: .profile, skippability: .required),
    OnboardingStepDefinition(step: .interests, skippability: .required),
    OnboardingStepDefinition(step: .suggestedAccounts, skippability: .skippable),
    OnboardingStepDefinition(step: .suggestedStarterPacks, skippability: .skippable),
    OnboardingStepDefinition(step: .findContactsIntro, skippability: .skippable),
    OnboardingStepDefinition(
      step: .findContacts, skippability: .skippable, countsTowardProgress: false),
    OnboardingStepDefinition(
      step: .finished, skippability: .required, countsTowardProgress: false),
  ]

  /// The definition for a step.
  public static func definition(for step: OnboardingStep) -> OnboardingStepDefinition {
    all.first { $0.step == step }
      ?? OnboardingStepDefinition(step: step, skippability: .required)
  }
}

/// Which optional steps this session includes.
///
/// RN derives these from feature gates and platform:
/// - `suggested-starterpacks` needs `ENV !== 'e2e'` and a content-language set
///   that probably speaks English (`probablySpeaksEnglish` in
///   `screens/Onboarding/index.tsx`).
/// - the `find-contacts` steps need native, the country allowlist, and the
///   `ImportContactsOnboardingDisable` gate.
///
/// The app layer evaluates those and passes the result in.
public struct OnboardingStepConfiguration: Sendable, Equatable, Codable {
  /// Include the suggested-starter-packs step.
  public var starterPacksStepEnabled: Bool
  /// Include the find-contacts intro and find-contacts steps.
  public var findContactsStepEnabled: Bool

  /// Creates a configuration.
  public init(starterPacksStepEnabled: Bool = true, findContactsStepEnabled: Bool = false) {
    self.starterPacksStepEnabled = starterPacksStepEnabled
    self.findContactsStepEnabled = findContactsStepEnabled
  }

  /// The RN default: starter packs on, find contacts off.
  public static let `default` = OnboardingStepConfiguration()

  /// Whether a step is part of the flow under this configuration.
  public func includes(_ step: OnboardingStep) -> Bool {
    switch step {
    case .profile, .interests, .suggestedAccounts, .finished:
      return true
    case .suggestedStarterPacks:
      return starterPacksStepEnabled
    case .findContactsIntro, .findContacts:
      return findContactsStepEnabled
    }
  }

  /// The enabled steps, in order. Port of `getStepOrder` in `state.ts`.
  public var stepOrder: [OnboardingStep] {
    OnboardingSteps.all.map(\.step).filter(includes)
  }
}

/// The direction of the most recent step change, for a transition animation.
public enum StepTransitionDirection: String, Sendable, Equatable, Codable {
  case forward = "Forward"
  case backward = "Backward"
}

/// Per-step completion state.
///
/// RN keeps results in the reducer (`interestsStepResults`,
/// `profileStepResults`) and infers completion from them. The wizard records
/// completion explicitly as well, because resumability needs to know a step
/// was finished even when it was finished by skipping.
public struct StepCompletion: Sendable, Equatable, Codable {
  /// Steps the user has advanced past.
  public var completed: Set<OnboardingStep>
  /// Steps the user advanced past by skipping rather than completing.
  public var skipped: Set<OnboardingStep>

  /// Creates completion state.
  public init(
    completed: Set<OnboardingStep> = [], skipped: Set<OnboardingStep> = []
  ) {
    self.completed = completed
    self.skipped = skipped
  }

  /// Whether the step was advanced past, by completion or by skip.
  public func isSettled(_ step: OnboardingStep) -> Bool {
    completed.contains(step) || skipped.contains(step)
  }

  /// Whether the step was advanced past by skipping.
  public func isSkipped(_ step: OnboardingStep) -> Bool {
    skipped.contains(step)
  }
}

/// The result carried out of the profile step.
///
/// Port of `profileStepResults` in `state.ts`. The RN version holds an image
/// descriptor (path/mime/size/width/height) and a generated-avatar descriptor.
/// The Swift flow uploads the avatar at completion, so the step result needs
/// the bytes and mime type rather than a device path.
public struct ProfileStepResult: Sendable, Equatable, Codable {
  /// The avatar bytes to upload, when the user picked a photo.
  public var avatarImageData: Data?
  /// The mime type for ``avatarImageData``.
  public var avatarMimeType: String?
  /// Whether the avatar came from the avatar creator rather than a photo.
  public var isCreatedAvatar: Bool
  /// The display name the user set. RN writes an empty display name from the
  /// onboarding flow (`next.displayName = ''` in `StepFinished`); the field
  /// exists here so a fork can fill it in.
  public var displayName: String

  /// Creates a profile step result.
  public init(
    avatarImageData: Data? = nil,
    avatarMimeType: String? = nil,
    isCreatedAvatar: Bool = false,
    displayName: String = ""
  ) {
    self.avatarImageData = avatarImageData
    self.avatarMimeType = avatarMimeType
    self.isCreatedAvatar = isCreatedAvatar
    self.displayName = displayName
  }

  /// Whether an avatar should be uploaded.
  public var hasAvatarToUpload: Bool {
    avatarImageData != nil && avatarMimeType != nil
  }
}

/// The result carried out of the interests step.
public struct InterestsStepResult: Sendable, Equatable, Codable {
  /// The selected interest tags.
  public var selectedInterests: [String]

  /// Creates an interests step result.
  public init(selectedInterests: [String] = []) {
    self.selectedInterests = selectedInterests
  }
}

/// The result carried out of the suggested-accounts step.
public struct SuggestedAccountsStepResult: Sendable, Equatable, Codable {
  /// DIDs followed during the step, in follow order.
  public var followedDIDs: [String]

  /// Creates a suggested-accounts step result.
  public init(followedDIDs: [String] = []) {
    self.followedDIDs = followedDIDs
  }
}

/// The result carried out of the suggested-starter-packs step.
public struct StarterPacksStepResult: Sendable, Equatable, Codable {
  /// The starter pack the user chose to join, when one was chosen.
  public var joinedStarterPackURI: String?

  /// Creates a starter-packs step result.
  public init(joinedStarterPackURI: String? = nil) {
    self.joinedStarterPackURI = joinedStarterPackURI
  }
}

/// Everything the flow has collected.
public struct OnboardingResults: Sendable, Equatable, Codable {
  /// Profile step output.
  public var profile: ProfileStepResult
  /// Interests step output.
  public var interests: InterestsStepResult
  /// Suggested-accounts step output.
  public var suggestedAccounts: SuggestedAccountsStepResult
  /// Suggested-starter-packs step output.
  public var starterPacks: StarterPacksStepResult

  /// Creates empty results.
  public init(
    profile: ProfileStepResult = ProfileStepResult(),
    interests: InterestsStepResult = InterestsStepResult(),
    suggestedAccounts: SuggestedAccountsStepResult = SuggestedAccountsStepResult(),
    starterPacks: StarterPacksStepResult = StarterPacksStepResult()
  ) {
    self.profile = profile
    self.interests = interests
    self.suggestedAccounts = suggestedAccounts
    self.starterPacks = starterPacks
  }
}

/// How onboarding as a whole finished.
public enum OnboardingCompletionOutcome: String, Sendable, Equatable, Codable {
  /// Every step was run to the end.
  case completed
  /// The user left the flow before the final step.
  case abandoned
}
