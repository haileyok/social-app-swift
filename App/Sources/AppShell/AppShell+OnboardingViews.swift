import DesignSystem
import DesignSystemCore
import OnboardingLogic
import SwiftUI

// Re-exported so the app and its test targets reach the wizard surface (and
// `OnboardingFixtures`/`OnboardingAccessibility`) through `import AppShell`
// alone, the same way they reach `ShellAccessibility`. XCUITest bundles are
// built by the project rather than by a package, so they link only the AppShell
// product.
@_exported import OnboardingViews

/**
 The onboarding surfaces, for the app shell and the CI screenshot loop.

 Mirrors `AppShell+Components.swift` and `AppShell+Login.swift`: the hook lives
 in its own file so the shell agent's work on the root view and this surface do
 not conflict, and nothing here is referenced by the root view by default. The
 wizard is presented over the shell once a signup completes; the app root mounts
 `OnboardingSurfaces.wizardScreen(theme:)` when the session reports a
 post-signup account that has not finished onboarding.

 ```swift
 // AppRootView, once the session can answer "needs onboarding":
 OnboardingSurfaces.wizardScreen(theme: themePreference)
 ```
 */
@MainActor
public enum OnboardingSurfaces {

  /**
   The fixture-bound wizard, pinned to a step and a theme.

   The wizard rendered here is the same one the app presents: it drives
   ``OnboardingFlow`` and renders the real step screens. What makes it
   fixture-bound is the flow it is handed - an inert action service (no writes)
   and a fixed suggestion page - so the surface renders and navigates without a
   session. That is what the debug entry point and the CI capture use.

   - Parameters:
     - theme: the ALF theme to render under. `.system` re-resolves against the
       current appearance, which is the app default.
     - step: the step to pin the wizard to. Defaults to the wizard's own first
       step, i.e. the real entry point.
   */
  public static func wizardScreen(
    theme: ThemePreference = .system,
    step: OnboardingStep? = nil
  ) -> some View {
    OnboardingWizardScreen(
      flow: OnboardingFixtures.flow(),
      dependencies: OnboardingFixtures.dependencies(),
      initialStep: step
    )
    .theme(theme)
  }

  /**
   The wizard for a finished signup, driven by the app's real flow.

   The caller owns the flow (built over the session's action service and
   preferences engine) and the completion hook, which is what leaves onboarding
   once the flow reaches its finished step.
   */
  public static func wizardScreen(
    flow: OnboardingFlow,
    dependencies: OnboardingViewDependencies,
    theme: ThemePreference = .system
  ) -> some View {
    OnboardingWizardScreen(flow: flow, dependencies: dependencies)
      .theme(theme)
  }

  /**
   The step a `-uiTestScreen onboarding-<step>` launch value names, or nil.

   Mirror of `OnboardingCaptureScreen.step(forLaunchValue:)`, surfaced here so
   the screenshot loop and the app root read one definition.
   */
  public static func step(forLaunchValue value: String) -> OnboardingStep? {
    OnboardingCaptureScreen.step(forLaunchValue: value)
  }
}
