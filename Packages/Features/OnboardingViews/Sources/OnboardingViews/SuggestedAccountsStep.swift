import DesignSystem
import DesignTokens
import OnboardingLogic
import SwiftUI
import UIComponents
import UIComponentsCore

/// The suggested-accounts step: a selectable list of accounts to follow.
///
/// Port of `screens/Onboarding/StepSuggestedAccounts/index.tsx`. The list comes
/// from ``OnboardingSuggestionService`` (supplied by the app or the fixtures),
/// not from the flow: the flow owns the follow write, the view owns the fetch.
///
/// The horizontal interest tabs issue category-scoped requests through the
/// existing suggestion service, while selections remain shared across tabs.
public struct SuggestedAccountsStep: View {
  private let model: OnboardingWizardModel

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      OnboardingHeading(OnboardingCopy.suggestedAccountsTitle)

      interestTabs

      listBody

      footerControls
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.suggestedAccountsStep)
  }

  /// RN's “All” tab followed by the interests selected in the prior step.
  private var interestTabs: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.sm) {
        interestTab(title: "All", category: nil)
        ForEach(model.selectedInterests, id: \.self) { interest in
          interestTab(title: interest.replacingOccurrences(of: "-", with: " ").capitalized,
                      category: interest)
        }
      }
      .padding(.horizontal, 1)
    }
    .accessibilityLabel("Suggestion categories")
  }

  private func interestTab(title: String, category: String?) -> some View {
    let selected = model.suggestedAccountsCategory == category
    return Button {
      model.selectSuggestedAccountsCategory(category)
    } label: {
      Text(title)
        .font(TypeScale.sm.font(weight: Scales.FontWeight.semiBold))
        .foregroundStyle(selected ? theme.atomColors.textInverted : theme.atomColors.text)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(selected ? theme.colors.primary500 : theme.atomColors.bgContrast50)
        .clipShape(.capsule)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// The list, its loading state, or its empty/error state.
  @ViewBuilder private var listBody: some View {
    if model.isLoadingSuggestions {
      ListSkeleton(rowCount: 6)
    } else if model.suggestionsFailed {
      ErrorStateView(
        error: ListState.ListErrorState(
          title: "Could not load suggestions",
          message: OnboardingStrings.genericError),
        retry: { Task { await model.loadSuggestionsIfNeeded() } })
    } else if model.suggestedUsers.isEmpty {
      EmptyStateView(
        icon: "person.2",
        title: "No suggestions",
        message: OnboardingStrings.noSuggestions,
        actionLabel: OnboardingCopy.retryAction,
        action: { Task { await model.loadSuggestionsIfNeeded() } })
    } else {
      VStack(spacing: 0) {
        ForEach(model.suggestedUsers) { user in
          SuggestedAccountRow(
            user: user, isSelected: model.selectedSuggestedDIDs.contains(user.did)
          ) {
            model.toggleSuggestedAccount(user.did)
          }
          if user.id != model.suggestedUsers.last?.id {
            Rectangle()
              .fill(theme.atomColors.borderContrastLow)
              .frame(height: 1)
          }
        }
      }
    }
  }

  /// Follow all / Skip / Continue, matching the RN controls outlet.
  private var footerControls: some View {
    VStack(spacing: Spacing.sm) {
      if !model.suggestedUsers.isEmpty {
        AlfButton(
          OnboardingCopy.followAllAction,
          color: .primarySubtle,
          size: .large,
          action: { model.selectAllSuggestedAccounts() })
          .disabled(model.isRunning)
          .accessibilityIdentifier(OnboardingAccessibility.suggestedAccountsFollowAll)
      }
      AlfButton(
        OnboardingCopy.continueAction,
        color: .primary,
        size: .large,
        action: { Task { await model.submitSuggestedAccounts() } })
        .disabled(!model.canContinue)
        .accessibilityIdentifier(OnboardingAccessibility.suggestedAccountsContinue)
    }
  }

  @Environment(\.alfTheme) private var theme
}
