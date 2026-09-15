import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents

/// The per-step chrome: the header, the scrollable body, and a pinned footer.
///
/// Port of `screens/Onboarding/Layout.tsx`. The header carries the back
/// affordance and whatever header content a step adds (the profile step shows
/// its progress line there, as RN does on phone widths); the footer pins the
/// step's primary controls, ported from the `OnboardingControls` outlet.
///
/// The layout does not decide anything: `showsBack` and the footer content are
/// supplied by the container, which reads them from the wizard's skippability
/// and navigation model.
struct OnboardingStepScaffold<Content: View, Footer: View>: View {
  private let showsBack: Bool
  private let onBack: () -> Void
  private let header: AnyView?
  private let content: Content
  private let footer: Footer

  @Environment(\.alfTheme) private var theme

  init(
    showsBack: Bool,
    onBack: @escaping () -> Void,
    header: AnyView? = nil,
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.showsBack = showsBack
    self.onBack = onBack
    self.header = header
    self.content = content()
    self.footer = footer()
  }

  var body: some View {
    VStack(spacing: 0) {
      bar
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          content
        }
        .padding(.xl, .horizontal)
        .padding(.md, .vertical)
        .frame(maxWidth: OnboardingGeometry.columnWidth)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      footerContainer
    }
    .background(theme.atomColors.bg)
  }

  /// The header bar: the back affordance on the leading edge, the step's own
  /// header content on the trailing edge.
  private var bar: some View {
    HStack {
      if showsBack {
        AlfIconButton(
          systemImage: "chevron.left",
          label: OnboardingCopy.backLabel,
          color: .secondary,
          size: .small,
          shape: .round,
          action: onBack)
          .accessibilityIdentifier(OnboardingAccessibility.back)
      }
      Spacer(minLength: Spacing.sm)
      if let header {
        header
      }
    }
    .padding(.xl, .horizontal)
    .padding(.sm, .vertical)
    .frame(minHeight: OnboardingGeometry.headerHeight)
    .frame(maxWidth: OnboardingGeometry.columnWidth)
    .frame(maxWidth: .infinity)
  }

  /// The pinned footer, matching the RN controls outlet.
  private var footerContainer: some View {
    VStack(spacing: 0) {
      Rectangle()
        .fill(theme.atomColors.borderContrastLow)
        .frame(height: 1)
      footer
        .padding(.xl, .horizontal)
        .padding(.md, .vertical)
        .frame(maxWidth: OnboardingGeometry.columnWidth)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(OnboardingAccessibility.footer)
    }
    .background(theme.atomColors.bg)
  }
}

/// The geometry the wizard's column shares with the RN layout.
enum OnboardingGeometry {
  /// `ONBOARDING_COL_WIDTH` from `Layout.tsx`.
  static let columnWidth: Double = 420
  /// Roughly `HEADER_SLOT_SIZE`, the header's minimum height.
  static let headerHeight: Double = 48
}

/// The step's title, port of `OnboardingTitleText`.
struct OnboardingTitle: View {
  private let content: String

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontScale) private var fontScale
  @Environment(\.alfFontFamily) private var family

  init(_ content: String) {
    self.content = content
  }

  var body: some View {
    Text(content)
      .font(TypeScale.xxxl.font(fontScale: fontScale, family: family, weight: Scales.FontWeight.bold))
      .foregroundStyle(theme.atomColors.text)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// The step's supporting line, port of `OnboardingDescriptionText`.
struct OnboardingDescription: View {
  private let content: String

  @Environment(\.alfTheme) private var theme

  init(_ content: String) {
    self.content = content
  }

  var body: some View {
    AlfText(content, scale: .md, color: theme.atomColors.textContrastMedium)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// The progress position line, port of `OnboardingPosition`.
struct OnboardingPosition: View {
  private let text: String

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontScale) private var fontScale

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(TypeScale.sm.font(fontScale: fontScale, weight: Scales.FontWeight.medium))
      .foregroundStyle(theme.atomColors.textContrastMedium)
      .accessibilityIdentifier(OnboardingAccessibility.position)
  }
}

/// A heading block: title plus optional description, in the RN order.
struct OnboardingHeading: View {
  private let title: String
  private let description: String?

  init(_ title: String, description: String? = nil) {
    self.title = title
    self.description = description
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      OnboardingTitle(title)
      if let description {
        OnboardingDescription(description)
      }
    }
    .padding(.sm, .bottom)
  }
}
