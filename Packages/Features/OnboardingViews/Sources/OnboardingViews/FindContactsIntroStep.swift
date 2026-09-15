import DesignSystem
import DesignSystemCore
import OnboardingLogic
import SwiftUI
import UIComponents

/// The find-contacts intro: explain the import before asking for access.
///
/// Port of `screens/Onboarding/StepFindContactsIntro/index.tsx`. RN shows a hero
/// illustration; this renders a symbol stand-in of the same size so the layout
/// matches without shipping art.
///
/// The step is skippable as a unit with the contact-sync step that follows
/// (``OnboardingStepDefinition``), so its footer carries both an import action
/// and a skip.
public struct FindContactsIntroStep: View {
  private let model: OnboardingWizardModel

  @Environment(\.alfTheme) private var theme

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      hero

      OnboardingHeading(
        OnboardingCopy.findContactsTitle, description: OnboardingCopy.findContactsDescription)

      controls
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.findContactsIntroStep)
  }

  /// The hero image stand-in.
  private var hero: some View {
    Image(systemName: "person.2.badge.plus")
      .font(.system(size: 64))
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .frame(maxWidth: .infinity)
      .frame(height: 140)
      .background(theme.atomColors.bgContrast50)
      .clipShape(.rect(cornerRadius: Radius.lg))
      .accessibilityHidden(true)
  }

  /// The import and skip controls.
  private var controls: some View {
    VStack(spacing: Spacing.sm) {
      AlfButton(
        OnboardingCopy.importContactsAction,
        color: .primary,
        size: .large,
        action: { Task { await model.advance() } })
        .disabled(model.isRunning)
        .accessibilityIdentifier(OnboardingAccessibility.findContactsImport)
      AlfButton(
        OnboardingCopy.skipLabel,
        color: .secondary,
        size: .large,
        action: { Task { await model.skipContacts() } })
        .disabled(model.isRunning)
    }
  }
}
