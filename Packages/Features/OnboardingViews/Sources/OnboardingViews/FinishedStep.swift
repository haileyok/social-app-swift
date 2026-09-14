import DesignSystem
import DesignSystemCore
import OnboardingLogic
import SwiftUI
import UIComponents

/// The finished step: the value-proposition pages, then the exit.
///
/// Port of `screens/Onboarding/StepFinished/index.tsx` and its
/// `ValuePropositionPager`. RN pages through three propositions; the last page's
/// button reads "Let's go!" and finishes onboarding, and a skip button is
/// available on every page. This reproduces that sub-step machine here, because
/// the logic layer has no notion of it - the wizard's own state is already at
/// its final step.
public struct FinishedStep: View {
  private let model: OnboardingWizardModel

  @State private var subStep = 0

  @Environment(\.alfTheme) private var theme

  /// Creates the step.
  public init(model: OnboardingWizardModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      page

      pageIndicator

      controls
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(OnboardingAccessibility.finishedStep)
  }

  /// The current value proposition.
  private var page: some View {
    let proposition = OnboardingCopy.valuePropositions[
      min(subStep, OnboardingCopy.valuePropositions.count - 1)]
    return VStack(alignment: .leading, spacing: Spacing.lg) {
      hero
      OnboardingHeading(proposition.title, description: proposition.description)
    }
    .accessibilityIdentifier(OnboardingAccessibility.finishedPage(subStep))
  }

  /// The page illustration stand-in.
  private var hero: some View {
    Image(systemName: "sparkles")
      .font(.system(size: 64))
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .frame(maxWidth: .infinity)
      .frame(height: 160)
      .background(theme.atomColors.bgContrast50)
      .clipShape(.rect(cornerRadius: Radius.lg))
      .accessibilityHidden(true)
  }

  /// The dots showing the current page.
  private var pageIndicator: some View {
    HStack(spacing: Spacing.sm) {
      ForEach(OnboardingCopy.valuePropositions.indices, id: \.self) { index in
        Circle()
          .fill(index == subStep ? theme.atomColors.text : theme.atomColors.bgContrast300)
          .frame(width: 8, height: 8)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }

  /// Next / Let's go! and the skip affordance.
  private var controls: some View {
    VStack(spacing: Spacing.sm) {
      AlfButton(
        isLastPage ? OnboardingCopy.letsGoAction : OnboardingCopy.nextAction,
        color: .primary,
        size: .large,
        action: { onNext() })
        .disabled(model.isRunning)
        .accessibilityIdentifier(OnboardingAccessibility.finishedNext)
      AlfButton(
        OnboardingCopy.skipLabel,
        color: .secondary,
        size: .large,
        action: { Task { await model.finish() } })
        .disabled(model.isRunning)
        .accessibilityIdentifier(OnboardingAccessibility.finishedSkip)
    }
  }

  /// Whether the pager is on its last page.
  private var isLastPage: Bool { subStep >= OnboardingCopy.valuePropositions.count - 1 }

  /// Advances the pager, or finishes onboarding on the last page.
  private func onNext() {
    if isLastPage {
      Task { await model.finish() }
    } else {
      subStep += 1
    }
  }
}
