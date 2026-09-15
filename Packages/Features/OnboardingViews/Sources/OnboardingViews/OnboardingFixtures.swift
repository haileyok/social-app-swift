import DesignSystem
import DesignSystemCore
import OnboardingLogic
import SwiftUI

/// Sample data and preconfigured flows for previews, the debug surface, and the
/// CI screenshot capture.
///
/// Pure and deterministic: the same call builds the same wizard, so a captured
/// screenshot is comparable run to run. Nothing here reaches the network - the
/// suggestion service returns a fixed page, and the action service performs no
/// writes.
public enum OnboardingFixtures {

  /// A configuration with every optional step enabled.
  ///
  /// The default configuration omits the find-contacts pair, so a capture
  /// surface that only had the default could not show those two screens.
  public static let fullConfiguration = OnboardingStepConfiguration(
    starterPacksStepEnabled: true, findContactsStepEnabled: true)

  /// The suggestion service every fixture wizard is built over.
  public static func suggestionService() -> FixtureOnboardingSuggestionService {
    FixtureOnboardingSuggestionService()
  }

  /// The view dependencies for a fixture wizard.
  public static func dependencies(
    interestsRequired: Bool = false,
    suggestionService: any OnboardingSuggestionService = FixtureOnboardingSuggestionService(),
    onFinished: @escaping () -> Void = {}
  ) -> OnboardingViewDependencies {
    OnboardingViewDependencies(
      suggestionService: suggestionService,
      interestsRequired: interestsRequired,
      onFinished: onFinished)
  }

  /// A flow over the fixture action service, with an in-memory progress sink so
  /// a fixture run never persists.
  public static func flow(
    configuration: OnboardingStepConfiguration = fullConfiguration
  ) -> OnboardingFlow {
    OnboardingFlow(
      actions: InertOnboardingActionService(),
      preferences: OnboardingViewDependencies.defaultPreferencesEngine(),
      sink: InMemoryOnboardingProgressSink(),
      configuration: configuration)
  }

  /// A model positioned at `step`, for a preview or a capture.
  ///
  /// The step is applied through the flow, so a step the configuration does not
  /// include is refused rather than forced.
  @MainActor
  public static func model(
    step: OnboardingStep = .profile,
    configuration: OnboardingStepConfiguration = fullConfiguration,
    interests: [String] = ["art", "music", "science"],
    displayName: String = ""
  ) -> OnboardingWizardModel {
    let model = OnboardingWizardModel(
      flow: flow(configuration: configuration), dependencies: dependencies())
    model.selectedInterests = interests
    model.displayName = displayName
    return model
  }

  /// The sample suggested accounts.
  public static let suggestedUsers: [SuggestedUser] = [
    SuggestedUser(
      did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice"),
    SuggestedUser(
      did: "did:plc:bob", handle: "bob.bsky.social", displayName: "Bob"),
    SuggestedUser(
      did: "did:plc:carol", handle: "carol.bsky.social", displayName: "Carol"),
    SuggestedUser(
      did: "did:plc:dave", handle: "dave.bsky.social", displayName: "Dave"),
    SuggestedUser(
      did: "did:plc:erin", handle: "erin.bsky.social", displayName: "Erin"),
    SuggestedUser(
      did: "did:plc:frank", handle: "frank.bsky.social", displayName: nil),
  ]

  /// The sample suggested starter packs.
  public static let suggestedStarterPacks: [SuggestedStarterPack] = [
    SuggestedStarterPack(
      uri: "at://did:plc:sample/app.bsky.graph.starterpack/science",
      cid: "bafyreisciencesample",
      listURI: "at://did:plc:sample/app.bsky.graph.list/science",
      name: "Science",
      feedURIs: ["at://did:plc:sample/app.bsky.feed.generator/science"]),
    SuggestedStarterPack(
      uri: "at://did:plc:sample/app.bsky.graph.starterpack/art",
      cid: "bafyreiartsample",
      listURI: "at://did:plc:sample/app.bsky.graph.list/art",
      name: "Art",
      feedURIs: [
        "at://did:plc:sample/app.bsky.feed.generator/art",
        "at://did:plc:sample/app.bsky.feed.generator/photography",
      ]),
  ]

  /// The step order the capture surface iterates, in configuration order.
  public static let captureSteps: [OnboardingStep] = OnboardingSteps.all.map(\.step)
}

/// A suggestion service that returns the fixture page.
///
/// The failure switch exists so a capture can show the error state without a
/// network; the successful case is what the per-step captures use.
public struct FixtureOnboardingSuggestionService: OnboardingSuggestionService {
  /// Whether every call should fail.
  public let shouldFail: Bool

  /// Creates the service.
  public init(shouldFail: Bool = false) {
    self.shouldFail = shouldFail
  }

  public func suggestedUsers(
    category: String?, limit: Int, interests: [String]
  ) async throws -> SuggestedUsersPage {
    if shouldFail { throw FixtureSuggestionError.unavailable }
    return SuggestedUsersPage(actors: OnboardingFixtures.suggestedUsers, recID: "fixture")
  }

  public func suggestedStarterPacks(
    limit: Int, interests: [String]
  ) async throws -> [SuggestedStarterPack] {
    if shouldFail { throw FixtureSuggestionError.unavailable }
    return OnboardingFixtures.suggestedStarterPacks
  }
}

/// The error the fixture service throws when asked to fail.
public enum FixtureSuggestionError: Error, Sendable {
  /// Suggestions could not be loaded.
  case unavailable
}

/// The fixture-bound capture surface for CI screenshots.
///
/// Renders the wizard pinned to one step and one theme, so
/// `-uiTestScreen onboarding-<step>` can land the app on a known screen without
/// a session. The step is applied once, on appear, through the flow - which
/// means the configuration's gating is honoured rather than bypassed.
public struct OnboardingCaptureScreen: View {
  private let step: OnboardingStep
  private let theme: ThemePreference

  /// Creates a capture surface.
  ///
  /// - Parameters:
  ///   - step: the step to pin the wizard to.
  ///   - theme: the ALF theme to render under.
  public init(step: OnboardingStep = .profile, theme: ThemePreference = .light) {
    self.step = step
    self.theme = theme
  }

  public var body: some View {
    OnboardingWizardScreen(
      flow: OnboardingFixtures.flow(),
      dependencies: OnboardingFixtures.dependencies(),
      initialStep: step
    )
    .theme(theme)
  }

  /// The launch-argument value for a step, e.g. `onboarding-profile`.
  public static func launchValue(for step: OnboardingStep) -> String {
    "onboarding-\(step.rawValue)"
  }

  /// The step a launch-argument value names, or nil when it names none.
  public static func step(forLaunchValue value: String) -> OnboardingStep? {
    let prefix = "onboarding-"
    guard value.hasPrefix(prefix) else { return nil }
    return OnboardingStep(rawValue: String(value.dropFirst(prefix.count)))
  }
}
