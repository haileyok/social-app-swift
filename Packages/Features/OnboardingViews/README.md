# OnboardingViews

The SwiftUI half of onboarding: the post-signup wizard's step screens.

Ported from `src/screens/Onboarding/**` in the React Native app. Every decision
lives in the `OnboardingLogic` package next door (`Packages/Features/Onboarding`)
- the step machine, the skippability model, the validation rules, the interest
taxonomy, the suggestion services. This package renders that state and calls the
flow; it re-derives no rule.

## What is here

- `OnboardingWizardScreen` - the step container, port of `index.tsx` plus the
  `Layout.tsx` chrome (back affordance, step position, pinned footer).
- `OnboardingWizardModel` - the `@Observable` adapter over `OnboardingFlow`,
  mirroring the `LoginViews` pattern: the logic flow is `Sendable` with an
  `addListener` callback, not `Observable`, so the view model bridges it.
- The seven step screens: `ProfileStep`, `InterestsStep`,
  `SuggestedAccountsStep`, `StarterPacksStep`, `FindContactsIntroStep`,
  `FindContactsStep`, `FinishedStep`.
- Shared chrome: `OnboardingStepScaffold`, `OnboardingTitle`,
  `OnboardingDescription`, `OnboardingPosition`, `OnboardingHeading`,
  `InterestChip`, `SuggestedAccountRow`, `StarterPackRow`, `FlowLayout`.
- `OnboardingCopy` - the strings seam. Every user-facing string reads through it,
  so replacing it with a String Catalog is a single-file change.
- `OnboardingFixtures` / `OnboardingCaptureScreen` - the fixture surface the CI
  screenshot loop can pin to a step.

## Skippability

The footer's skip affordance is not decided here: `OnboardingWizardModel.canSkip`
reads `OnboardingState.canSkipActiveStep`, which is the step definition's
`StepSkippability`. The find-contacts pair and the finished step skip through
their own actions (`skipContacts`, `finish`); the suggestion steps use the
container's generic `skip`. `profile` and `interests` are `required` in the logic
layer and get no skip affordance.

## Deviations from the RN screens

1. **Profile step collects a display name.** RN's `StepProfile` only collects an
   avatar (its `StepFinished` writes `displayName = ''`). The Swift profile step
   adds the field because `ProfileStepResult` already carries one and
   `ProfileValidation` already has the rule; the limit and the UTF-16 counting
   match the RN `EditProfileDialog` text field.
2. **The avatar creator is not ported.** The profile step now uses the native
   photo library picker, previews the selected image, retains it across failed
   submissions, and sends its bytes/MIME type through the tested logic upload.
   RN's emoji-and-background avatar creator remains a separate enhancement.
3. **Suggested-account pagination is not ported.** The screen now matches RN's
   “All” plus selected-interest tab bar and refetches with the chosen category,
   while preserving follow selections across tabs. Each tab currently loads the
   service's first 25 recommendations rather than infinite paging.
4. **Find-contacts defers its work to the app.** RN's `StepFindContacts` is a
   whole contacts flow (permission, hashing, upload) owned by the app's contacts
   component. This package renders the step's chrome and its two transitions
   (allow advances, skip jumps the pair); the contact matching itself is the
   app's, which is why the finding is presented as in-progress rather than as a
   result list.
5. **Hero images are symbol stand-ins.** RN ships illustrations for the
   find-contacts intro and the value-proposition pages. The same geometry is
   rendered with SF Symbols so the layout matches without shipping art; swapping
   in the real assets is a view-local change.
6. **The value-proposition sub-step machine is view-local.** RN's
   `StepFinished` pages through three propositions before finishing. The wizard's
   own state is already at `finished`, so the pager's index is `@State` in
   `FinishedStep`, matching the RN component's own `useState`.

## Not implemented here

- No session or root takeover. The wizard reports completion through
  `OnboardingViewDependencies.onFinished`; deciding what the app root shows
  afterwards is the shell's call.
- No live suggestion or action services. `OnboardingViewDependencies` takes an
  `OnboardingSuggestionService`, and the flow takes an
  `OnboardingActionService`; the app supplies the live ones over the session's
  clients, and `OnboardingFixtures` supplies inert ones for capture and previews.
