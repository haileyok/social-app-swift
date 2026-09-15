import DesignSystem
import SwiftUI
import UIComponents

/// The search screen's field.
///
/// `UIComponents` has no `TextField` yet, so this is the search screen's own:
/// a leading magnifying-glass icon, a themed rounded surface, a clear button
/// while text is present, and a Cancel affordance beside it. The shape matches
/// the RN `SearchInput`, whose field is the screen's only chrome above the
/// content.
public struct SearchField: View {
  @Binding private var text: String
  private let placeholder: String
  private let onCommit: () -> Void
  private let onCancel: () -> Void
  private let identifier: String?

  @FocusState private var isFocused: Bool
  @Environment(\.alfTheme) private var theme

  public init(
    text: Binding<String>,
    placeholder: String = SearchCopy.searchPlaceholder,
    identifier: String? = SearchAccessibility.searchField,
    onCommit: @escaping () -> Void = {},
    onCancel: @escaping () -> Void = {}
  ) {
    self._text = text
    self.placeholder = placeholder
    self.identifier = identifier
    self.onCommit = onCommit
    self.onCancel = onCancel
  }

  public var body: some View {
    HStack(spacing: Spacing.sm) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 15))
          .foregroundStyle(theme.atomColors.textContrastMedium)
        TextField(placeholder, text: $text)
          .font(TypeScale.md.font())
          .foregroundStyle(theme.atomColors.text)
          .focused($isFocused)
          .submitLabel(.search)
          .onSubmit(onCommit)
          .autocorrectionDisabled()
          .accessibilityLabel(SearchCopy.searchFieldLabel)
          .accessibilityIdentifier(identifier ?? "")
        if !text.isEmpty {
          Button {
            text = ""
            isFocused = true
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 15))
              .foregroundStyle(theme.atomColors.textContrastMedium)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(SearchCopy.clearFieldAction)
        }
      }
      .padding(.md, .horizontal)
      .padding(.sm, .vertical)
      .background(theme.atomColors.bgContrast25)
      .overlay {
        RoundedRectangle(cornerRadius: Radius.full, style: .continuous)
          .strokeBorder(
            isFocused ? theme.atomColors.borderContrastHigh : theme.atomColors.borderContrastLow,
            lineWidth: 1)
      }
      .cornerRadius(.full)

      Button(SearchCopy.cancelSearchAction) {
        isFocused = false
        onCancel()
      }
      .buttonStyle(.plain)
      .font(TypeScale.md.font())
      .foregroundStyle(theme.atomColors.textLink)
    }
    .padding(.md, .horizontal)
    .padding(.sm, .vertical)
  }
}
