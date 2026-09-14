import Foundation

/// The wizard's three steps, in order.
///
/// Port of `const steps = ['Details', 'Profiles', 'Feeds'] as const` in
/// `src/screens/StarterPack/Wizard/State.tsx`. The order is load-bearing: the
/// reducer derives the next and previous step from a step's index in this list.
public enum StarterPackWizardStep: String, Sendable, CaseIterable, Hashable {
  /// Name and description.
  case details = "Details"
  /// Member selection.
  case profiles = "Profiles"
  /// Feed selection.
  case feeds = "Feeds"

  /// The steps in wizard order.
  public static let order: [StarterPackWizardStep] = [.details, .profiles, .feeds]

  /// This step's index in the order.
  public var index: Int { Self.order.firstIndex(of: self) ?? 0 }
}

/// The direction the last step change moved in, for the transition animation.
///
/// Port of `transitionDirection: 'Backward' | 'Forward'`.
public enum WizardTransitionDirection: String, Sendable, Equatable {
  /// Moving to a later step.
  case forward = "Forward"
  /// Moving to an earlier step.
  case backward = "Backward"
}

/// One member of a pack under construction.
///
/// RN holds `bsky.profile.AnyProfileView` values straight from the search
/// results. The wizard only ever reads `did`, `handle` and `displayName`, so the
/// Logic type carries exactly those: a Views layer keeps whatever else it needs.
public struct WizardProfile: Sendable, Equatable, Hashable {
  /// The account's DID.
  public let did: String
  /// The account's handle.
  public let handle: String
  /// The account's display name, when set.
  public let displayName: String?

  /// Creates a member.
  public init(did: String, handle: String, displayName: String? = nil) {
    self.did = did
    self.handle = handle
    self.displayName = displayName
  }

  /// The name to show for this member, RN's `getName`: the sanitized display
  /// name when there is one, else the sanitized handle.
  public var displayLabel: String {
    if let displayName, !displayName.isEmpty {
      return StarterPackStrings.enforceLen(
        StarterPackStrings.sanitizeDisplayName(displayName), 28, ellipsis: true)
    }
    return StarterPackStrings.enforceLen(
      StarterPackStrings.sanitizeHandle(handle), 28, ellipsis: true)
  }
}

/// One feed of a pack under construction.
public struct WizardFeed: Sendable, Equatable, Hashable {
  /// The generator's AT URI.
  public let uri: String
  /// The generator's display name.
  public let displayName: String

  /// Creates a feed.
  public init(uri: String, displayName: String) {
    self.uri = uri
    self.displayName = displayName
  }

  /// The name to show for this feed, RN's `getName`.
  public var displayLabel: String {
    StarterPackStrings.enforceLen(
      StarterPackStrings.sanitizeDisplayName(displayName), 28, ellipsis: true)
  }
}

/// A refusal the reducer produced instead of applying an action.
///
/// RN shows a toast and drops the action; a Logic layer has no toast, so the
/// refusal is returned and the caller decides how to present it.
public enum WizardRefusal: Sendable, Equatable {
  /// The people list is full: RN's `You may only add up to N profiles`.
  case profileCapReached(limit: Int)
  /// The feed list is full: RN's `You may only add up to 3 feeds`.
  case feedCapReached(limit: Int)

  /// The message RN renders for this refusal, with the profile cap substituted.
  public var message: String {
    switch self {
    case .profileCapReached(let limit):
      "You may only add up to \(limit) profiles"
    case .feedCapReached(let limit):
      "You may only add up to \(limit) feeds"
    }
  }
}

/// The wizard's state, with no I/O.
///
/// Port of the `State` interface and `reducer` in
/// `src/screens/StarterPack/Wizard/State.tsx`. It is a value type: every
/// transition returns a new value, and the caller owns the current one.
///
/// The behaviors the port pins:
///
/// - **Name slice.** `SetName` slices to 50 characters, exactly as RN does.
/// - **Member cap.** RN's `AddProfile` guard is `state.profiles.length >
///   STARTER_PACK_MAX_SIZE`, so the 151st profile is accepted and the 152nd is
///   refused. That off-by-one is reproduced deliberately: see
///   ``WizardRefusal/profileCapReached(limit:)``.
/// - **Feed cap.** `state.feeds.length >= 3` refuses the fourth feed.
/// - **Navigation clamping.** `Next` at the last step and `Back` at the first
///   are no-ops, and neither changes ``transitionDirection``.
public struct StarterPackWizard: Sendable, Equatable {
  /// Whether the footer's *Next* button is enabled.
  ///
  /// RN initializes this to `true` and never flips it in the reducer; the screen
  /// gates on it alongside its own step checks.
  public var canNext: Bool
  /// The step the user is on.
  public private(set) var currentStep: StarterPackWizardStep
  /// The pack name as typed, already sliced.
  public var name: String?
  /// The pack description as typed.
  public var description: String?
  /// The selected members, in selection order. RN seeds this with the profile
  /// the wizard was opened against.
  public private(set) var profiles: [WizardProfile]
  /// The selected feeds, in selection order.
  public private(set) var feeds: [WizardFeed]
  /// Whether a submit is in flight.
  public var processing: Bool
  /// The last error, when one was recorded.
  public var error: String?
  /// The direction of the last step change.
  public private(set) var transitionDirection: WizardTransitionDirection
  /// The profile the wizard was opened against, RN's `targetDid`.
  public let targetDID: String?
  /// The refusals produced by the most recent transition, for the caller to
  /// surface. RN raises these as toasts; a value type cannot.
  public private(set) var lastRefusals: [WizardRefusal]

  // MARK: - Construction

  /// Creates a wizard for a fresh pack, seeded with the target profile.
  ///
  /// Port of the `else` branch of `createInitialState`: the people list starts
  /// with the target profile, the feed list is empty, and the step is
  /// ``StarterPackWizardStep/details``.
  public init(targetProfile: WizardProfile) {
    self.canNext = true
    self.currentStep = .details
    self.name = nil
    self.description = nil
    self.profiles = [targetProfile]
    self.feeds = []
    self.processing = false
    self.error = nil
    self.transitionDirection = .forward
    self.targetDID = targetProfile.did
    self.lastRefusals = []
  }

  /// Creates a wizard for editing an existing pack.
  ///
  /// Port of the `starterPack` branch of `createInitialState`: the name and
  /// description come from the record, the people list from the list items
  /// (minus anyone who opted out), and the feeds from the view. `canNext` is
  /// `true`, even though RN sets it that way in both branches of the ternary it
  /// is written as.
  public init(
    editingName: String?,
    description: String?,
    listItems: [WizardProfile],
    feeds: [WizardFeed],
    targetProfile: WizardProfile
  ) {
    self.canNext = true
    self.currentStep = .details
    self.name = editingName
    self.description = description
    self.profiles = listItems
    self.feeds = feeds
    self.processing = false
    self.error = nil
    self.transitionDirection = .forward
    self.targetDID = targetProfile.did
    self.lastRefusals = []
  }

  // MARK: - Derived

  /// Whether the current step is the first.
  public var isFirstStep: Bool { currentStep == StarterPackWizardStep.order.first }

  /// Whether the current step is the last.
  public var isLastStep: Bool { currentStep == StarterPackWizardStep.order.last }

  /// The step after the current one, or nil at the end.
  public var nextStep: StarterPackWizardStep? {
    let index = currentStep.index
    let order = StarterPackWizardStep.order
    guard index + 1 < order.count else { return nil }
    return order[index + 1]
  }

  /// The step before the current one, or nil at the start.
  public var previousStep: StarterPackWizardStep? {
    let index = currentStep.index
    guard index > 0 else { return nil }
    return StarterPackWizardStep.order[index - 1]
  }

  /// The number of items on the current step: people on the people step, feeds
  /// otherwise. Port of the screen's `items` binding.
  public var currentItemsCount: Int {
    currentStep == .profiles ? profiles.count : feeds.count
  }

  /// The cap shown beside the current step's count.
  public var currentItemsLimit: Int {
    currentStep == .profiles ? StarterPackConstants.maxSize : StarterPackConstants.maximumFeeds
  }

  /// Whether the screen renders the *Edit* affordance for this step.
  ///
  /// Port of `isEditEnabled`: more than one person on the people step (the first
  /// entry is the wizard's own target), or any feed on the feeds step.
  public var isEditEnabled: Bool {
    if currentStep == .profiles { return profiles.count > 1 }
    if currentStep == .feeds { return !feeds.isEmpty }
    return false
  }

  /// Whether the people step has enough members to continue.
  ///
  /// Port of the footer's `state.currentStep === 'Profiles' && items.length < 8`
  /// gate: *Next* is disabled below eight members.
  public var meetsMinimumProfiles: Bool {
    profiles.count >= StarterPackConstants.minimumProfiles
  }

  /// How many more members are needed to continue. Zero once the minimum is met.
  public func remainingProfilesNeeded() -> Int {
    max(0, StarterPackConstants.minimumProfiles - profiles.count)
  }

  /// Whether the *Next* button is enabled for the current step.
  ///
  /// Port of the footer's `disabled` expression: the step gate, the processing
  /// flag, and the people minimum.
  public var canSubmitCurrentStep: Bool {
    guard canNext, !processing else { return false }
    if currentStep == .profiles { return meetsMinimumProfiles }
    return true
  }

  /// The label RN gives the footer button for the current step.
  public var nextButtonLabel: String {
    switch currentStep {
    case .details, .profiles: "Next"
    case .feeds: feeds.isEmpty ? "Skip" : "Finish"
    }
  }

  // MARK: - Navigation

  /// Advances one step.
  ///
  /// Port of the `Next` branch: the step moves forward unless the current step
  /// is already the last, and the direction is recorded either way only when a
  /// move actually happens.
  public mutating func next() {
    guard let next = nextStep else { return }
    currentStep = next
    transitionDirection = .forward
  }

  /// Steps back one step.
  ///
  /// Port of the `Back` branch: a no-op at the first step, and the direction is
  /// only recorded on a real move.
  public mutating func back() {
    guard let previous = previousStep else { return }
    currentStep = previous
    transitionDirection = .backward
  }

  /// Jumps to a step, recording the direction by order.
  @discardableResult
  public mutating func move(to step: StarterPackWizardStep) -> Bool {
    guard step != currentStep else { return false }
    transitionDirection = step.index > currentStep.index ? .forward : .backward
    currentStep = step
    return true
  }

  // MARK: - Mutations

  /// Sets the pack name, sliced to 50 characters.
  ///
  /// Port of `SetName`, including the `slice(0, 50)`.
  public mutating func setName(_ value: String) {
    name = String(value.prefix(StarterPackConstants.maxNameLength))
  }

  /// Sets the pack description, unsliced (the lexicon caps it, not the reducer).
  public mutating func setDescription(_ value: String) {
    description = value
  }

  /// Adds a member, or refuses when the list is full.
  ///
  /// Port of `AddProfile`. RN's guard is `state.profiles.length >
  /// STARTER_PACK_MAX_SIZE`, which admits the profile that takes the list to
  /// `maxSize + 1` and refuses the next one. Reproduced as written.
  public mutating func addProfile(_ profile: WizardProfile) {
    if profiles.count > StarterPackConstants.maxSize {
      lastRefusals.append(.profileCapReached(limit: StarterPackConstants.maxSize))
      return
    }
    profiles.append(profile)
  }

  /// Removes a member by DID, keeping selection order otherwise.
  ///
  /// Port of `RemoveProfile`, which filters on `did`.
  public mutating func removeProfile(did: String) {
    profiles.removeAll { $0.did == did }
  }

  /// Adds a feed, or refuses at the three-feed cap.
  ///
  /// Port of `AddFeed`. RN's guard is `state.feeds.length >= 3`.
  public mutating func addFeed(_ feed: WizardFeed) {
    if feeds.count >= StarterPackConstants.maximumFeeds {
      lastRefusals.append(.feedCapReached(limit: StarterPackConstants.maximumFeeds))
      return
    }
    feeds.append(feed)
  }

  /// Removes a feed by URI.
  ///
  /// Port of `RemoveFeed`, which filters on `uri`.
  public mutating func removeFeed(uri: String) {
    feeds.removeAll { $0.uri == uri }
  }

  /// Sets the processing flag.
  public mutating func setProcessing(_ value: Bool) {
    processing = value
  }

  /// Records an error.
  public mutating func setError(_ message: String) {
    error = message
  }

  /// Clears the refusals recorded by earlier transitions.
  public mutating func clearRefusals() {
    lastRefusals = []
  }

  /// Whether a member is already selected.
  public func hasProfile(did: String) -> Bool {
    profiles.contains { $0.did == did }
  }

  /// Whether a feed is already selected.
  public func hasFeed(uri: String) -> Bool {
    feeds.contains { $0.uri == uri }
  }
}

/// The people and feeds the wizard's edit dialog removes.
///
/// Port of `WizardEditListDialog`'s `getData`: on the feeds step it lists the
/// feeds, and otherwise it lists the target profile first followed by everyone
/// else (so the person the pack is about cannot be removed from the dialog's
/// list by accident).
public enum WizardEditList {
  /// The entries the edit dialog shows for a step.
  public static func entries(
    for step: StarterPackWizardStep, wizard: StarterPackWizard
  ) -> WizardEditEntries {
    if step == .feeds { return .feeds(wizard.feeds) }
    let others = wizard.profiles.filter { $0.did != wizard.targetDID }
    let target = wizard.profiles.first { $0.did == wizard.targetDID }
    return .profiles((target.map { [$0] } ?? []) + others)
  }
}

/// The edit dialog's rows, tagged by kind.
public enum WizardEditEntries: Sendable, Equatable {
  /// Member rows.
  case profiles([WizardProfile])
  /// Feed rows.
  case feeds([WizardFeed])
}
