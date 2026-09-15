import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents

/// A settings section: an uppercase-ish heading, an optional description, and
/// the rows beneath it.
///
/// The moderation screens are a stack of these (labeler sections on the content
/// screen, target/duration groups on the muted-word sheet), so the heading
/// treatment lives in one place rather than being restated per screen.
struct ModerationSection<Content: View>: View {
  var title: String? = nil
  var description: String?
  @ViewBuilder var content: () -> Content

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if let title {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          AlfText(
            title, scale: .sm, weight: Scales.FontWeight.semiBold,
            color: theme.atomColors.textContrastMedium)
          if let description {
            AlfText(description, scale: .xs, color: theme.atomColors.textContrastLow)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      content()
    }
  }
}

/// A non-interactive informational row, the shape the RN `Admonition` produces.
///
/// Used for the adult-content-off notice and the not-subscribed notice: copy
/// that explains why a row is inert, in the place the row would be.
struct ModerationNotice: View {
  enum Kind {
    case info
    case warning
  }

  let message: String
  var kind: Kind = .info

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: systemImage)
        .foregroundStyle(iconColor)
        .accessibilityHidden(true)
      AlfText(message, scale: .xs, color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.atomColors.bgContrast25)
    .cornerRadius(.md)
    .accessibilityElement(children: .combine)
  }

  private var systemImage: String {
    switch kind {
    case .info: return "info.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    }
  }

  private var iconColor: Color {
    switch kind {
    case .info: return theme.atomColors.textContrastLow
    case .warning: return theme.colors.negative600
    }
  }
}

/// A hairline divider, the way the moderation lists separate rows.
///
/// A plain `Divider` is used rather than a tinted overlay so the separator
/// follows the platform's own separator colour and avoids the `overlay(_:)`
/// ambiguity between its `View` and `ShapeStyle` overloads.
struct ModerationDivider: View {
  var body: some View {
    Divider()
  }
}

/// A tappable settings row: a title, optional supporting line, and a trailing
/// affordance.
///
/// The account rows, the labeler rows and the "manage muted words" links are all
/// this shape, so the press feedback and the accessibility wiring live here.
struct ModerationRow<Trailing: View>: View {
  let title: String
  var subtitle: String?
  var action: (() -> Void)?
  @ViewBuilder var trailing: () -> Trailing

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Group {
      if let action {
        Button(action: action) { rowBody }
          .buttonStyle(.plain)
      } else {
        rowBody
      }
    }
  }

  private var rowBody: some View {
    HStack(alignment: .center, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(title, scale: .md, weight: Scales.FontWeight.semiBold)
        if let subtitle {
          AlfText(subtitle, scale: .xs, color: theme.atomColors.textContrastLow)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      trailing()
    }
    .padding(.md, .horizontal)
    .padding(.sm, .vertical)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
  }
}

extension ModerationRow where Trailing == EmptyView {
  init(
    title: String, subtitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.init(title: title, subtitle: subtitle, action: action, trailing: { EmptyView() })
  }
}

/// A labelled on/off control, the shape the adult-content and exclude-following
/// rows take.
struct ModerationToggleRow: View {
  let title: String
  var subtitle: String?
  @Binding var isOn: Bool

  var identifier: String?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(title, scale: .md, weight: Scales.FontWeight.semiBold)
        if let subtitle {
          AlfText(subtitle, scale: .xs, color: theme.atomColors.textContrastLow)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .tint(theme.colors.primary500)
    .padding(.md, .horizontal)
    .padding(.sm, .vertical)
    .accessibilityIdentifier(identifier ?? "")
  }
}

/// A horizontal radio group: the segmented control the RN label rows use for
/// Show / Warn / Hide, and the muted-word sheet reuses for targets and duration.
struct ModerationRadioGroup<Value: Hashable>: View {
  let options: [Value]
  let label: (Value) -> String
  @Binding var selection: Value
  /// The accessibility identifier for each option, given its value's label.
  var identifier: ((Value) -> String)?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      ForEach(options, id: \.self) { option in
        optionButton(option)
      }
    }
  }

  private func optionButton(_ option: Value) -> some View {
    let selected = option == selection
    return Button {
      selection = option
    } label: {
      AlfText(
        label(option), scale: .xs,
        weight: selected ? Scales.FontWeight.semiBold : Scales.FontWeight.normal,
        color: selected ? theme.atomColors.textInverted : theme.atomColors.text)
        .lineLimit(1)
        .padding(.sm, .horizontal)
        .padding(.xs, .vertical)
        .frame(maxWidth: .infinity)
        .background(selected ? theme.atomColors.text : theme.atomColors.bgContrast50)
        .clipShape(.capsule)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
    .accessibilityIdentifier(identifier?(option) ?? "")
  }
}

/// The inline error line the moderation forms use.
struct ModerationErrorLine: View {
  let message: String
  var identifier: String?

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(theme.colors.negative600)
        .accessibilityHidden(true)
      AlfText(message, scale: .sm, color: theme.colors.negative700)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.negative50)
    .cornerRadius(.md)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifier ?? "")
  }
}

/// A labelled text field in the moderation form idiom.
///
/// Mirrors the login form's field, which is the established shape in this repo
/// for a labelled input over a themed surface.
struct ModerationTextField: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  var identifier: String?
  var isMultiline = false

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(
        label, scale: .sm, weight: Scales.FontWeight.semiBold,
        color: theme.atomColors.textContrastMedium)

      input
        .font(TypeScale.md.font())
        .foregroundStyle(theme.atomColors.text)
        .padding(.md, .horizontal)
        .padding(.sm, .vertical)
        .background(theme.atomColors.bgContrast25)
        .overlay {
          RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(theme.atomColors.borderContrastLow, lineWidth: 1)
        }
        .cornerRadius(.md)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
  }

  @ViewBuilder
  private var input: some View {
    if isMultiline {
      TextField(placeholder, text: $text, axis: .vertical)
        .lineLimit(3...6)
    } else {
      TextField(placeholder, text: $text)
    }
  }
}

/// A primary form submit button, sized to the form's width.
struct ModerationSubmitButton: View {
  let title: String
  var isProcessing = false
  var identifier: String?
  var action: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Button(action: action) {
      if isProcessing {
        ProgressView().tint(theme.atomColors.textInverted)
      } else {
        AlfButtonText(title)
      }
    }
    .buttonStyle(.alf(color: .primary, size: .large, shape: .rectangular))
    .disabled(isProcessing)
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier(identifier ?? "")
  }
}

/// A tiny status pill, for the "Expired"/"Not following" badges on a muted-word
/// row.
struct ModerationBadge: View {
  let text: String
  var isWarning = false

  @Environment(\.alfTheme) private var theme

  var body: some View {
    AlfText(
      text, scale: .xxs, weight: Scales.FontWeight.semiBold,
      color: isWarning ? theme.colors.negative700 : theme.atomColors.textContrastMedium)
      .padding(.xs, .horizontal)
      .padding(.xxs, .vertical)
      .background(isWarning ? theme.colors.negative50 : theme.atomColors.bgContrast50)
      .clipShape(.capsule)
  }
}
