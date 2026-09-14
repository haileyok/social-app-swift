import DesignSystem
import OnboardingLogic
import SwiftUI
import UIComponents

/// The suggested-starter-packs step: pick one pack to join.
///
/// Port of `screens/Onboarding/StepSuggestedStarterpacks/index.tsx`. The packs
/// come from ``OnboardingSuggestionService``; the choice is recorded through
/// `runStarterPacksStep`, which stores the URI the completion step resolves into
/// follows and pinned feeds.
public struct StarterPacksStep: View {
  private let model: OnboardingWizardModel

  @Environment(\.alfTheme) private var theme

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      OnboardingHeading(OnboardingCopy.suggestedStarterPacksTitle)

      listBody

      continueButton
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.starterPacksStep)
  }

  /// The list, its loading state, or its empty/error state.
  @ViewBuilder private var listBody: some View {
    if model.isLoadingSuggestions {
      ListSkeleton(rowCount: 3)
    } else if model.suggestionsFailed {
      ErrorStateView(
        error: ListState.ListErrorState(
          title: "Could not load starter packs",
          message: OnboardingStrings.genericError),
        retry: { Task { await model.loadSuggestionsIfNeeded() } })
    } else if model.suggestedStarterPacks.isEmpty {
      EmptyStateView(
        icon: "person.3",
        title: "No starter packs",
        message: OnboardingStrings.noSuggestions,
        actionLabel: OnboardingCopy.retryAction,
        action: { Task { await model.loadSuggestionsIfNeeded() } })
    } else {
      VStack(spacing: Spacing.md) {
        ForEach(model.suggestedStarterPacks) { pack in
          StarterPackRow(
            pack: pack, isSelected: model.selectedStarterPackURI == pack.uri
          ) {
            model.selectStarterPack(pack.uri)
          }
        }
      }
    }
  }

  /// The step's continue action.
  private var continueButton: some View {
    AlfButton(
      OnboardingCopy.continueAction,
      color: .primary,
      size: .large,
      action: { Task { await model.submitStarterPacks() } })
      .disabled(!model.canContinue)
      .accessibilityIdentifier(OnboardingAccessibility.starterPacksContinue)
  }
}
