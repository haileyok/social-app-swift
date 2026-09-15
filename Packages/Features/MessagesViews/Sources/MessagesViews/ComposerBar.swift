import DesignSystem
import DesignTokens
import MessagesLogic
import SwiftUI
import UIComponents

/// The send bar: a text field, a send button, and the failed-send state.
///
/// Port of the RN `MessageComposer` minus embeds and replies (out of the minimal
/// 1:1 scope). The draft lives in the caller; this view binds to it. When the
/// outbox is stuck the bar shows a retry line above the field rather than
/// swallowing the failure - the RN treatment - and the send button keeps working
/// so a new message can be attempted.
struct ComposerBar: View {
  @Environment(\.alfTheme) private var theme

  @Binding var text: String
  let canSend: Bool
  let failure: SendFailure?
  let onSend: () -> Void
  let onRetry: () -> Void

  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      Divider().overlay(theme.atomColors.borderContrastLow)
      if failure != nil {
        failureBanner
      }
      HStack(alignment: .bottom, spacing: Spacing.sm) {
        field
        sendButton
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(theme.atomColors.bg)
    }
  }

  private var field: some View {
    TextField(MessagesCopy.composerPlaceholder, text: $text, axis: .vertical)
      .lineLimit(1...6)
      .font(TypeScale.md.font())
      .foregroundStyle(theme.atomColors.text)
      .textFieldStyle(.plain)
      .focused($isFocused)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, 9)
      .background(theme.atomColors.bgContrast100)
      .clipShape(.capsule)
      .overlay(
        Capsule().stroke(theme.atomColors.borderContrastLow, lineWidth: 1))
      .accessibilityIdentifier(MessagesAccessibility.composerField)
      .onSubmit(onSend)
  }

  private var sendButton: some View {
    Button(action: onSend) {
      Image(systemName: "arrow.up.circle.fill")
        .font(.system(size: 28))
        .foregroundStyle(canSend ? theme.colors.primary500 : theme.atomColors.textContrastLow)
    }
    .disabled(!canSend)
    .accessibilityLabel(MessagesCopy.sendAccessibilityLabel)
    .accessibilityIdentifier(MessagesAccessibility.composerSend)
    .padding(.bottom, 2)
  }

  private var failureBanner: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 12))
        .foregroundStyle(theme.colors.negative500)
      AlfText(MessagesCopy.sendFailed, scale: .sm, color: theme.colors.negative500)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: Spacing.sm)
      Button(MessagesCopy.retry, action: onRetry)
        .buttonStyle(.alf(color: .negativeSubtle, size: .tiny))
        .accessibilityIdentifier(MessagesAccessibility.composerRetry)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(theme.colors.negative50)
  }
}
