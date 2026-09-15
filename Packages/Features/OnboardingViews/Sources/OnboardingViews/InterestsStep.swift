import DesignSystem
import DesignTokens
import OnboardingLogic
import SwiftUI
import UIComponents

/// The interests step: the taxonomy rendered as selectable chips.
///
/// Port of `screens/Onboarding/StepInterests/index.tsx`. The chips come from
/// ``Interests/all`` in the logic layer - the wire vocabulary - and the
/// selection is committed through `runInterestsStep`, which filters to known
/// tags and applies the required-selection gate.
///
/// The RN screen boosts the popular interests by putting them first; that
/// ordering is used here too, so the common choices are above the fold.
public struct InterestsStep: View {
  private let model: OnboardingWizardModel

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      OnboardingHeading(OnboardingCopy.interestsTitle, description: description)

      chipGrid

      continueButton
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.interestsStep)
  }

  /// The grid of chips, in the boosted order.
  private var chipGrid: some View {
    FlowLayout(spacing: Spacing.sm) {
      ForEach(orderedInterests, id: \.self) { tag in
        InterestChip(tag: tag, isSelected: model.isSelected(tag)) {
          model.toggleInterest(tag)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(OnboardingCopy.interestsGroupLabel)
    .accessibilityIdentifier(OnboardingAccessibility.interestsGroup)
  }

  /// The step's continue action.
  private var continueButton: some View {
    AlfButton(
      OnboardingCopy.continueAction,
      color: .primary,
      size: .large,
      action: { Task { await model.submitInterests() } })
      .disabled(!model.canContinue)
      .accessibilityIdentifier(OnboardingAccessibility.interestsContinue)
  }

  /// The description, switching on the required-selection gate.
  private var description: String {
    model.dependencies.interestsRequired
      ? OnboardingCopy.interestsRequiredDescription
      : OnboardingCopy.interestsDescription
  }

  /// The taxonomy, popular interests floated to the front.
  private var orderedInterests: [String] {
    let popular = Interests.popular.filter(Interests.isValid)
    let rest = Interests.all.filter { !popular.contains($0) }
    return popular + rest
  }
}
