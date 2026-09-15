import DesignSystem
import DesignSystemCore
import DesignTokens
import OnboardingLogic
import SwiftUI
import UIComponents

/// The onboarding wizard: the post-signup step container.
///
/// Port of `screens/Onboarding/index.tsx`. It renders exactly one step and the
/// chrome the RN `Layout` provides (a back affordance that appears once the user
/// has moved forward, the step position, and the step's own footer controls),
/// driven by ``OnboardingWizardModel`` over the logic package's
/// ``OnboardingFlow``.
///
/// The container decides nothing: the active step, whether there is somewhere to
/// go back to, and whether the step may be skipped all come from the wizard's
/// own state, so the skippability model and the step order live in one place.
///
/// ```swift
/// OnboardingWizardScreen(flow: OnboardingFlow(actions: actions, preferences: prefs))
/// ```
public struct OnboardingWizardScreen: View {
  @State private var model: OnboardingWizardModel
  private let initialStep: OnboardingStep?

  /// Creates the wizard screen.
  ///
  /// - Parameters:
  ///   - flow: the logic flow to drive. Defaults to a session-free one, which
  ///     still renders and navigates every step (what the debug surface and the
  ///     previews use).
  ///   - dependencies: the app-supplied suggestion service and completion hook.
  ///   - initialStep: a step to pin the wizard to on appear. Used by the
  ///     fixture-bound capture surface; nil leaves the flow at whatever step its
  ///     restored progress names.
  @MainActor
  public init(
    flow: OnboardingFlow = OnboardingFlow(
      actions: InertOnboardingActionService(),
      preferences: OnboardingViewDependencies.defaultPreferencesEngine()),
    dependencies: OnboardingViewDependencies = .default,
    initialStep: OnboardingStep? = nil
  ) {
    _model = State(
      initialValue: OnboardingWizardModel(flow: flow, dependencies: dependencies))
    self.initialStep = initialStep
  }

  public var body: some View {
    stepScaffold
      .accessibilityElement(children: .contain)
      .accessibilityLabel(OnboardingCopy.dialogLabel)
      .accessibilityHint(OnboardingCopy.dialogHint)
      .accessibilityIdentifier(OnboardingAccessibility.screen)
      .task {
        await model.start()
        if let initialStep {
          await model.setStep(initialStep)
        }
      }
      .animation(.default, value: model.activeStep)
  }

  /// The scaffold, with the header content the step adds and the footer the
  /// container supplies.
  private var stepScaffold: some View {
    OnboardingStepScaffold(
      showsBack: model.canGoBack,
      onBack: { Task { await model.goBack() } },
      header: header,
      content: { stepContent },
      footer: { footerControls })
  }

  /// The header's trailing content: the progress position, which RN shows in the
  /// header on phone widths.
  private var header: AnyView? {
    guard let progressText = model.progressText else { return nil }
    return AnyView(OnboardingPosition(progressText))
  }

  /// The active step's screen.
  @ViewBuilder private var stepContent: some View {
    Group {
      switch model.activeStep {
      case .profile:
        ProfileStep(model: model)
      case .interests:
        InterestsStep(model: model)
      case .suggestedAccounts:
        SuggestedAccountsStep(model: model)
      case .suggestedStarterPacks:
        StarterPacksStep(model: model)
      case .findContactsIntro:
        FindContactsIntroStep(model: model)
      case .findContacts:
        FindContactsStep(model: model)
      case .finished:
        FinishedStep(model: model)
      }
    }
    .id(model.activeStep)
    .transition(stepTransition)
  }

  /// The animated transition between steps, in the flow's recorded direction.
  private var stepTransition: AnyTransition {
    switch model.transitionDirection {
    case .forward:
      return .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity))
    case .backward:
      return .asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity))
    }
  }

  /// The container-level footer: a failure banner and the generic skip, when the
  /// step is skippable and does not already render its own skip.
  @ViewBuilder private var footerControls: some View {
    VStack(spacing: Spacing.sm) {
      if let failure = model.failure {
        failureBanner(failure)
      }
      if model.canSkip && !stepRendersOwnSkipControls {
        AlfButton(
          OnboardingCopy.skipLabel,
          color: .secondary,
          size: .large,
          action: { Task { await model.skip() } })
          .disabled(model.isRunning)
      }
    }
  }

  /// The failure banner: the mapped message and a retry when the error is
  /// retryable.
  private func failureBanner(_ failure: OnboardingError) -> some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
      Text(OnboardingErrorPresentation.message(for: failure))
        .font(TypeScale.sm.font())
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: Spacing.sm)
      if OnboardingErrorPresentation.canRetry(failure) {
        Button(OnboardingCopy.retryAction) { model.clearFailure() }
          .font(TypeScale.sm.font(weight: Scales.FontWeight.medium))
      }
    }
    .foregroundStyle(.orange)
    .padding(.md)
    .background(.orange.opacity(0.12))
    .clipShape(.rect(cornerRadius: Radius.sm))
  }

  /// Whether the active step draws its own skip control in its body, so the
  /// container must not draw a second one.
  ///
  /// The find-contacts pair and the finished step skip through their own action
  /// (`skipContacts`, `finish`); the suggestion steps use the container's
  /// generic `skip`, which is the flow's skippability path.
  private var stepRendersOwnSkipControls: Bool {
    switch model.activeStep {
    case .findContactsIntro, .findContacts, .finished:
      return true
    case .profile, .interests, .suggestedAccounts, .suggestedStarterPacks:
      return false
    }
  }
}
