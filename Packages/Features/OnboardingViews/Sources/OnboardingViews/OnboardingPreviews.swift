import DesignSystemCore
import SwiftUI

/// Previews for each wizard step.
///
/// Every step is reachable directly, so a layout change can be checked without
/// driving the flow, and under each ALF theme.
#Preview("Profile") {
  OnboardingCaptureScreen(step: .profile, theme: .light)
}

#Preview("Interests") {
  OnboardingCaptureScreen(step: .interests, theme: .light)
}

#Preview("Suggested accounts") {
  OnboardingCaptureScreen(step: .suggestedAccounts, theme: .dark)
}

#Preview("Starter packs") {
  OnboardingCaptureScreen(step: .suggestedStarterPacks, theme: .light)
}

#Preview("Find contacts intro") {
  OnboardingCaptureScreen(step: .findContactsIntro, theme: .light)
}

#Preview("Find contacts") {
  OnboardingCaptureScreen(step: .findContacts, theme: .light)
}

#Preview("Finished") {
  OnboardingCaptureScreen(step: .finished, theme: .dim)
}
