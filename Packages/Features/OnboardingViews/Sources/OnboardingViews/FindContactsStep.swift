import DesignSystem
import OnboardingLogic
import SwiftUI
import UIComponents

/// The contact-sync step: the permission prompt and the match.
///
/// Port of `screens/Onboarding/StepFindContacts/index.tsx`. RN delegates the
/// whole screen to the contacts component's flow state; the actual contact
/// access, the hashing and the upload all live in the app layer, which this
/// package cannot reach. What is real here is the step's chrome, its
/// skippability, and the flow transition: allowing advances the wizard, skipping
/// jumps the pair.
///
/// The step is never counted toward the progress indicator
/// (``OnboardingStepDefinition/countsTowardProgress``), so it shows the position
/// of the folded find-contacts-intro step through the wizard's own index.
public struct FindContactsStep: View {
  private let model: OnboardingWizardModel

  @Environment(\.alfTheme) private var theme

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      OnboardingHeading(
        OnboardingCopy.findContactsTitle,
        description: OnboardingCopy.findContactsSyncDescription)

      spinner

      controls
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.findContactsStep)
  }

  /// The in-progress affordance for the contact match.
  private var spinner: some View {
    VStack(spacing: Spacing.md) {
      ProgressView()
        .controlSize(.large)
      Text("Matching your contacts…")
        .font(TypeScale.sm.font())
        .foregroundStyle(theme.atomColors.textContrastMedium)
    }
    .frame(maxWidth: .infinity)
    .padding(.xl, .vertical)
  }

  /// The allow and skip controls.
  private var controls: some View {
    VStack(spacing: Spacing.sm) {
      AlfButton(
        OnboardingCopy.findContactsAllowAction,
        color: .primary,
        size: .large,
        action: { Task { await model.advance() } })
        .disabled(model.isRunning)
        .accessibilityIdentifier(OnboardingAccessibility.findContactsAllow)
      AlfButton(
        OnboardingCopy.skipLabel,
        color: .secondary,
        size: .large,
        action: { Task { await model.skipContacts() } })
        .disabled(model.isRunning)
        .accessibilityIdentifier(OnboardingAccessibility.findContactsSkip)
    }
  }
}
