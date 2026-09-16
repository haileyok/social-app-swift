#if canImport(SwiftUI)
import ComposerLogic
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents
import UIComponentsCore

/// The reply-context header.
///
/// Ported from `ComposerReplyTo.tsx`: the post being replied to stays visible
/// above the editor so the author can write with the thread's context in view.
/// Native-first, this keeps the original's compact form (author line plus the
/// target's text) rather than a full embedded post, which is also what the RN
/// screen renders.
struct ComposerReplyHeader: View {
  /// The target post's display data.
  let context: ComposerReplyContext

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "arrowshape.turn.up.left.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(theme.colors.primary500)
        .frame(width: 32, height: 32)
        .background(theme.colors.primary50)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(spacing: Spacing.xxs) {
          AlfText(
            ComposerCopy.replyingToLabel,
            scale: .xs,
            color: theme.atomColors.textContrastMedium)
          AlfText(
            "@\(context.handle)",
            scale: .xs,
            weight: Scales.FontWeight.semiBold,
            color: theme.colors.primary500)
        }
        AlfText(context.text, scale: .sm, color: theme.atomColors.text)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.atomColors.bgContrast25)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        .strokeBorder(theme.atomColors.borderContrastLow, lineWidth: 1)
    }
    .clipShape(.rect(cornerRadius: Radius.lg, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(ComposerAccessibility.replyHeader)
  }
}

/// The quote-context header, with its remove control.
///
/// Ported from the quote branch of `Composer.tsx`: when the composer was opened
/// to quote a post (or a pasted post URL was promoted to a quote) the target
/// shows above the editor with a control to drop the quote.
struct ComposerQuoteHeader: View {
  /// The quoted post's URI.
  let uri: String
  /// Called when the quote is removed.
  let onRemove: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.sm) {
      Image(systemName: "quote.opening")
        .foregroundStyle(theme.atomColors.textContrastMedium)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(
          ComposerCopy.quotingLabel,
          scale: .xs,
          color: theme.atomColors.textContrastMedium)
        AlfText(uri, scale: .sm, color: theme.atomColors.text)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: Spacing.sm)
      Button(ComposerCopy.removeAction, action: onRemove)
        .font(.caption)
        .foregroundStyle(theme.colors.primary500)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(theme.atomColors.bgContrast25)
    .cornerRadius(.md)
    .accessibilityIdentifier(ComposerAccessibility.quoteHeader)
  }
}

/// The composer's context/settings strip.
///
/// The row of controls the RN composer keeps above the keyboard: languages,
/// content warnings, reply permissions, and the drafts list. Each is a button
/// that opens its sheet; the button's state reflects what the composer currently
/// holds, so the user can see at a glance that (for example) replies are gated.
struct ComposerSettingsStrip: View {
  /// The post's self-labels, as the reducer holds them.
  let labels: SelfLabelSet
  /// The current language selection.
  let languages: LanguageSelection
  /// The thread's reply permissions.
  let threadgate: [ThreadgateAllowUISetting]
  /// Opens the language sheet.
  let onLanguages: () -> Void
  /// Opens the self-labels sheet.
  let onLabels: () -> Void
  /// Opens the threadgate sheet.
  let onThreadgate: () -> Void
  /// Opens the drafts sheet.
  let onDrafts: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    HStack(spacing: Spacing.sm) {
      chip(
        labels.isEmpty ? ComposerCopy.labelsTitle : "\(labels.values.count) warning",
        systemImage: "exclamationmark.triangle",
        isActive: !labels.isEmpty,
        identifier: ComposerAccessibility.labelsButton,
        action: onLabels)
      chip(
        languages.codes.isEmpty ? ComposerCopy.languageTitle : languages.codes.joined(separator: ", "),
        systemImage: "globe",
        isActive: !languages.codes.isEmpty,
        identifier: ComposerAccessibility.languageButton,
        action: onLanguages)
      chip(
        threadgateLabel,
        systemImage: "bubble.left.and.bubble.right",
        isActive: !threadgate.contains(.everybody),
        identifier: ComposerAccessibility.threadgateButton,
        action: onThreadgate)
      Spacer(minLength: 0)
      chip(
        ComposerCopy.draftsTitle,
        systemImage: "tray.full",
        isActive: false,
        identifier: ComposerAccessibility.draftsButton,
        action: onDrafts)
    }
  }

  /// The reply-permission summary, which is the first (only) setting's label.
  private var threadgateLabel: String {
    guard let first = threadgate.first else { return ComposerCopy.threadgateTitle }
    return ComposerCopy.threadgateLabel(first)
  }

  private func chip(
    _ label: String,
    systemImage: String,
    isActive: Bool,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: systemImage)
          .font(.caption2)
        AlfText(
          label,
          scale: .xs,
          color: isActive ? theme.atomColors.text : theme.atomColors.textContrastMedium)
          .lineLimit(1)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(isActive ? theme.colors.primary100 : theme.atomColors.bgContrast50)
      .cornerRadius(.full)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
  }
}

/// The thread's continuation posts.
///
/// Ported from the multi-post branch of `Composer.tsx`: the thread's later posts
/// stay on the same screen, stacked under the first, so a thread reads as one
/// composition. Each row carries its own editor, counter and remove control.
struct ComposerThreadPosts: View {
  /// The thread's posts after the first.
  let posts: [PostDraft]
  /// Called when a post's text changes.
  let onText: (String, RichTextValue) -> Void
  /// Called when the post's remove control is tapped.
  let onRemove: (String) -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    ForEach(posts) { post in
      VStack(alignment: .leading, spacing: Spacing.xs) {
        HStack {
          AlfText(
            "Post \(indexLabel(for: post))",
            scale: .xs,
            color: theme.atomColors.textContrastMedium)
          Spacer(minLength: Spacing.sm)
          Button(action: { onRemove(post.id) }, label: {
            Image(systemName: "minus.circle")
          })
          .foregroundStyle(theme.atomColors.textContrastMedium)
          .accessibilityLabel(ComposerCopy.removePostAction)
          .accessibilityIdentifier("\(ComposerAccessibility.addPostButton).remove.\(post.id)")
        }

        // The continuation editor is uncontrolled on purpose: it is a secondary
        // field, and giving every thread post its own `@FocusState` binding to
        // the screen's active-post index would fight the reducer for focus.
        TextEditorBinding(post: post, onText: onText)

        HStack {
          Spacer(minLength: 0)
          ComposerCharacterCounter(post: post)
        }
      }
      .padding(Spacing.sm)
      .background(theme.atomColors.bgContrast25)
      .cornerRadius(.md)
    }
  }

  /// The 1-based label for a continuation post.
  ///
  /// `posts` here is the thread's tail, so the index is offset by the first
  /// post's position.
  private func indexLabel(for post: PostDraft) -> Int {
    (posts.firstIndex(where: { $0.id == post.id }) ?? 0) + 2
  }
}

/// One continuation post's editor.
///
/// A `TextField` over the post's rich text, writing through the same
/// detection-on-edit path the first post's editor uses.
private struct TextEditorBinding: View {
  let post: PostDraft
  let onText: (String, RichTextValue) -> Void

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale

  var body: some View {
    TextField(
      ComposerCopy.continuationPlaceholder,
      text: Binding(
        get: { post.richText.text },
        set: { newValue in
          guard newValue != post.richText.text else { return }
          onText(post.id, RichTextValue(text: newValue).detectingFacetsWithoutResolution())
        }),
      axis: .vertical
    )
    .font(TypeScale.lg.font(fontScale: fontScale, family: family, weight: Scales.FontWeight.normal))
    .foregroundStyle(theme.atomColors.text)
    .tint(theme.colors.primary500)
    .lineLimit(2...8)
    .accessibilityIdentifier("\(ComposerAccessibility.textEditor).\(post.id)")
  }
}
#endif
