import DesignSystem
import DesignTokens
import OnboardingLogic
import SwiftUI
import UIComponents

/// The profile step: an avatar picker, a display name, and validation.
///
/// Port of `screens/Onboarding/StepProfile/index.tsx`. RN's profile step only
/// collects an avatar (its photo picker and avatar creator); the display name
/// field is the Swift addition the logic layer's ``ProfileStepResult`` already
/// carries, validated by ``ProfileValidation`` so the two clients agree on the
/// limit.
///
/// The avatar picker itself is a placeholder: the photo library and the avatar
/// creator both need app-level services (photo permission, image loading, the
/// creator's canvas) that are outside this package. The control renders and
/// reports, so the wiring can land without touching the layout.
public struct ProfileStep: View {
  private let model: OnboardingWizardModel

  @Environment(\.alfTheme) private var theme

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      OnboardingHeading(
        OnboardingCopy.profileTitle, description: OnboardingCopy.profileDescription)

      avatarPicker

      nameField

      continueButton
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.profileStep)
  }

  /// The avatar placeholder: a dashed circle with an add affordance.
  private var avatarPicker: some View {
    VStack(spacing: Spacing.md) {
      ZStack {
        Circle()
          .fill(theme.atomColors.bgContrast100)
        Circle()
          .strokeBorder(theme.atomColors.borderContrastMedium, style: StrokeStyle(dash: [6, 4]))
        Image(systemName: "camera.fill")
          .font(.system(size: 28))
          .foregroundStyle(theme.atomColors.textContrastMedium)
      }
      .frame(width: 140, height: 140)
      .accessibilityLabel(OnboardingCopy.profileAvatarLabel)

      Text(OnboardingCopy.profileAvatarAdd)
        .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
        .foregroundStyle(theme.atomColors.textLink)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, .lg)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(OnboardingAccessibility.profileAvatarPicker)
  }

  /// The display-name field with its inline validation line.
  private var nameField: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(OnboardingCopy.profileNameLabel)
        .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
        .foregroundStyle(theme.atomColors.textContrastMedium)

      TextField(OnboardingCopy.profileNamePlaceholder, text: Binding(
        get: { model.displayName },
        set: { model.displayName = $0 }))
        .font(TypeScale.md.font())
        .textFieldStyle(.plain)
        .padding(.md)
        .background(theme.atomColors.bgContrast50)
        .clipShape(.rect(cornerRadius: Radius.sm))
        .overlay {
          RoundedRectangle(cornerRadius: Radius.sm)
            .strokeBorder(borderColor)
        }
        .accessibilityIdentifier(OnboardingAccessibility.profileNameField)

      if case .tooLong = model.displayNameValidation {
        Text(OnboardingCopy.profileNameTooLong)
          .font(TypeScale.sm.font())
          .foregroundStyle(theme.atomColors.text)
      }
    }
  }

  /// The name field's border, reddened when the value is over the limit.
  private var borderColor: Color {
    if case .tooLong = model.displayNameValidation {
      return theme.colors.primary500
    }
    return theme.atomColors.borderContrastLow
  }

  /// The step's continue action.
  private var continueButton: some View {
    AlfButton(
      OnboardingCopy.continueAction,
      color: .primary,
      size: .large,
      action: { Task { await model.submitProfile() } })
      .disabled(!model.canContinue || !canSubmit)
      .accessibilityIdentifier(OnboardingAccessibility.profileContinue)
  }

  /// Whether the entered name is in a state that can be written.
  private var canSubmit: Bool {
    if case .tooLong = model.displayNameValidation { return false }
    return true
  }
}
