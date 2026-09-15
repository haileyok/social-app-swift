import OnboardingLogic

/// The view-side dependencies a wizard needs that `OnboardingLogic` deliberately
/// does not own.
///
/// The flow owns every decision and every write. These three things can only be
/// answered by the app layer: which suggestions to render, whether the interests
/// step is gated as required, and what to do once onboarding is done.
public struct OnboardingViewDependencies {
  /// Fetches the suggested accounts and starter packs each step shows.
  ///
  /// Supplied by the app (the live implementation over the appview client) or by
  /// the fixtures. The wizard owns no client of its own.
  public var suggestionService: any OnboardingSuggestionService

  /// Whether the interests step refuses an empty selection.
  ///
  /// Port of the `OnboardingInterestsRequiredEnable` gate; the logic layer
  /// already models it as `runInterestsStep(selected:required:)`.
  public var interestsRequired: Bool

  /// Called once the flow settles on the finished step, so the app can leave
  /// onboarding. The wizard does not navigate.
  public var onFinished: () -> Void

  /// Creates the dependencies.
  public init(
    suggestionService: any OnboardingSuggestionService = EmptyOnboardingSuggestionService(),
    interestsRequired: Bool = false,
    onFinished: @escaping () -> Void = {}
  ) {
    self.suggestionService = suggestionService
    self.interestsRequired = interestsRequired
    self.onFinished = onFinished
  }

  /// The default: no suggestions, interests optional, no completion action.
  ///
  /// Enough to render and drive every step without a session, which is what the
  /// debug entry point and the previews use.
  public static var `default`: OnboardingViewDependencies { OnboardingViewDependencies() }
}

/// A suggestion service that returns nothing.
///
/// Used when a wizard is rendered without a session: every suggestion step shows
/// its empty state rather than failing, which is the same thing the RN screens
/// show when a suggestion query comes back empty.
public struct EmptyOnboardingSuggestionService: OnboardingSuggestionService {
  /// Creates the service.
  public init() {}

  public func suggestedUsers(
    category: String?, limit: Int, interests: [String]
  ) async throws -> SuggestedUsersPage {
    SuggestedUsersPage(actors: [])
  }

  public func suggestedStarterPacks(
    limit: Int, interests: [String]
  ) async throws -> [SuggestedStarterPack] {
    []
  }
}
