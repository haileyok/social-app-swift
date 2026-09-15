#if canImport(SwiftUI)
import ComposerLogic
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents

/// The publish progress and failure banner.
///
/// The publish flow writes records and uploads blobs; while it runs this banner
/// shows the spinner and its line, and on failure it shows the message with a
/// retry control, so the composer stays mounted and the draft is preserved.
struct ComposerPublishBanner: View {
  /// The current phase.
  let phase: ComposerPublishPhase
  /// Called when the retry control is tapped.
  let onRetry: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    switch phase {
    case .posting(let detail):
      HStack(spacing: Spacing.sm) {
        ProgressView()
        AlfText(detail, scale: .sm, color: theme.atomColors.textContrastMedium)
        Spacer(minLength: 0)
      }
      .padding(Spacing.sm)
      .background(theme.atomColors.bgContrast25)
      .cornerRadius(.md)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(ComposerAccessibility.publishProgress)

    case .failed(let message):
      HStack(alignment: .top, spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(theme.colors.negative500)
        AlfText(message, scale: .sm, color: theme.colors.negative600)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: Spacing.sm)
        Button(ComposerCopy.retryAction, action: onRetry)
          .font(.caption)
          .foregroundStyle(theme.colors.primary500)
          .accessibilityIdentifier(ComposerAccessibility.publishRetry)
      }
      .padding(Spacing.sm)
      .background(theme.colors.negative25)
      .cornerRadius(.md)
      .accessibilityIdentifier(ComposerAccessibility.publishError)
    }
  }
}
#endif
