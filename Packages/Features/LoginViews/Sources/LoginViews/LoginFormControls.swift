import DesignSystem
import DesignTokens
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The keyboard a login field asks for.
///
/// Declared here rather than taking a `UIKeyboardType` directly so the field's
/// signature stays platform-neutral: `keyboardType(_:)` does not exist outside
/// iOS, and these views are shared verbatim with previews.
enum LoginKeyboard {
  case `default`
  case emailAddress
  case url
  case asciiCapable

  #if canImport(UIKit)
  var uiKeyboardType: UIKeyboardType {
    switch self {
    case .default: .default
    case .emailAddress: .emailAddress
    case .url: .URL
    case .asciiCapable: .asciiCapable
    }
  }
  #endif
}

/// A labelled text field in ALF's form idiom.
///
/// The repo has no `TextField` component in `UIComponents` yet (only the button
/// matrix and the avatar/list surfaces), so the login form carries its own
/// field. It is deliberately small: a label above the input, a themed surface,
/// and an optional error line beneath it - the shape the RN form's `TextField`
/// produces.
///
/// The input is bound by `Binding` rather than left uncontrolled. The AGENTS.md
/// preference for `defaultValue` is about performance on the old architecture;
/// here the flow owns the identifier (``LoginFlow/setIdentifier(_:)``) and the
/// submit button's enabled state depends on both fields, so the values have to
/// reach SwiftUI state on every keystroke regardless.
struct LoginTextField<Field: Hashable>: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  let field: Field
  @FocusState.Binding var focusedField: Field?

  /// Renders the input as a secure entry field.
  var isSecure: Bool = false
  /// The keyboard to request.
  var keyboard: LoginKeyboard = .default
  /// The accessibility identifier the UI test addresses the field by.
  var identifier: String?
  /// The inline validation message, rendered beneath the field when set.
  var error: String?
  /// Submits the form when the keyboard's return key is tapped.
  var onSubmit: () -> Void = {}

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(
        label, scale: .sm, weight: Scales.FontWeight.semiBold,
        color: theme.atomColors.textContrastMedium)

      input
        .padding(.md, .horizontal)
        .padding(.sm, .vertical)
        .background(theme.atomColors.bgContrast25)
        .overlay {
          RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(borderColor, lineWidth: 1)
        }
        .cornerRadius(.md)

      if let error {
        // `fixedSize` keeps a long validation message on as many lines as it
        // needs instead of truncating at the field's width.
        AlfText(error, scale: .xs, color: theme.colors.negative600)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var input: some View {
    Group {
      if isSecure {
        SecureField(placeholder, text: $text)
      } else {
        TextField(placeholder, text: $text)
      }
    }
    .font(TypeScale.md.font())
    .foregroundStyle(theme.atomColors.text)
    .focused($focusedField, equals: field)
    .submitLabel(.go)
    .onSubmit(onSubmit)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier ?? "")
    .modifier(CredentialInputModifier(keyboard: keyboard))
  }

  private var isFocused: Bool { focusedField == field }

  private var borderColor: Color {
    if error != nil { return theme.colors.negative500 }
    return isFocused ? theme.atomColors.borderContrastHigh : theme.atomColors.borderContrastLow
  }
}

/// Applies the input traits a credential field needs: the requested keyboard,
/// autocapitalization off, and text assistance off.
///
/// Kept as one iOS-gated modifier so the field's own body stays free of platform
/// conditionals - `keyboardType(_:)`, `textInputAutocapitalization(_:)` and
/// `autocorrectionDisabled(_:)` do not all cross to macOS, and this package is
/// also built for it by SwiftPM's platform list.
private struct CredentialInputModifier: ViewModifier {
  let keyboard: LoginKeyboard

  func body(content: Content) -> some View {
    #if os(iOS)
    content
      .keyboardType(keyboard.uiKeyboardType)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
    #else
    content
    #endif
  }
}

/// The field-level validation line, separate from the text field so it can sit
/// at the top of a form the way the RN `LoginForm` renders it.
struct LoginValidationLine: View {
  let message: String

  @Environment(\.alfTheme) private var theme

  var body: some View {
    AlfText(message, scale: .sm, color: theme.colors.negative600)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier(LoginAccessibility.validationMessage)
  }
}

/// The failure banner that renders a mapped ``LoginError``.
///
/// Distinct from ``LoginValidationLine`` because the two carry different intent:
/// a validation line means "this submission never left the device", the banner
/// means "the server said no". The caller offers retry only when the error is
/// actually recoverable, so `appPasswordNotAllowed` and an unexpected failure do
/// not present a button that would fail identically.
struct LoginErrorBanner<Content: View>: View {
  let message: String
  @ViewBuilder var action: () -> Content

  @Environment(\.alfTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(theme.colors.negative600)
          .accessibilityHidden(true)
        AlfText(message, scale: .sm, color: theme.colors.negative700)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      action()
    }
    .padding(.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.negative50)
    .cornerRadius(.md)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(LoginAccessibility.errorBanner)
  }
}

extension LoginErrorBanner where Content == EmptyView {
  /// A banner with no action, for failures the user cannot retry.
  init(message: String) {
    self.init(message: message) { EmptyView() }
  }
}

/// A secondary, text-only action line, the shape the login form's "forgot
/// password" and "change server" affordances take.
struct LoginLinkButton: View {
  let title: String
  var identifier: String?
  let action: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    Button(action: action) {
      AlfText(
        title, scale: .sm, weight: Scales.FontWeight.semiBold,
        color: theme.atomColors.textLink)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier ?? "")
  }
}
