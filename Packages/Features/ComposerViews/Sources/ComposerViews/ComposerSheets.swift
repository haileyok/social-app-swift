#if canImport(SwiftUI)
import ComposerLogic
import DesignSystem
import DesignTokens
import SwiftUI
import UIComponents

/// The post-language picker.
///
/// Ported from `select-language/PostLanguageSelect.tsx`. The logic layer owns the
/// list and its cap; this sheet only shows and edits it. ``LanguageSelection``'s
/// mutating methods are used directly, so the cap and the auto/manual flip are
/// the logic layer's decisions, not the sheet's.
struct ComposerLanguageSheet: View {
  /// The current selection.
  let selection: LanguageSelection
  /// Called with the edited selection.
  let onChange: (LanguageSelection) -> Void
  /// Dismisses the sheet.
  let onDone: () -> Void

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale
  @State private var draftCode = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(selection.codes, id: \.self) { code in
            HStack {
              AlfText(code, scale: .md)
              Spacer(minLength: Spacing.sm)
              Button {
                var next = selection
                next.remove(code)
                onChange(next)
              } label: {
                Image(systemName: "minus.circle")
              }
              .foregroundStyle(theme.atomColors.textContrastMedium)
              .accessibilityLabel("Remove \(code)")
            }
          }
        } footer: {
          AlfText(
            "Up to \(LanguageSelection.maxLanguages) languages are attached to the post.",
            scale: .xs,
            color: theme.atomColors.textContrastMedium)
        }

        Section {
          HStack {
            TextField(ComposerCopy.languagePlaceholder, text: $draftCode)
              .font(TypeScale.md.font(fontScale: fontScale, family: family, weight: Scales.FontWeight.normal))
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .accessibilityIdentifier(ComposerAccessibility.languageField)
            Button(ComposerCopy.addLanguageAction) {
              var next = selection
              if next.add(draftCode.trimmingCharacters(in: .whitespaces)) {
                onChange(next)
                draftCode = ""
              }
            }
            .disabled(draftCode.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
      }
      .navigationTitle(ComposerCopy.languageTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(ComposerCopy.saveAction, action: onDone)
        }
      }
    }
    .accessibilityIdentifier(ComposerAccessibility.languageSheet)
  }
}

/// The content-warnings (self-labels) sheet.
///
/// Ported from `labels/LabelsBtn.tsx` and the RN labels dialog. The available
/// values come from ``SelfLabels``, so a change to the valid set is a change in
/// the logic layer only.
struct ComposerLabelsSheet: View {
  /// The labels currently attached to the post.
  let labels: SelfLabelSet
  /// Called with the edited set.
  let onChange: (SelfLabelSet) -> Void
  /// Dismisses the sheet.
  let onDone: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(SelfLabels.all, id: \.self) { value in
            Toggle(isOn: binding(for: value)) {
              AlfText(ComposerCopy.label(value), scale: .md)
            }
            .tint(theme.colors.primary500)
            .accessibilityIdentifier(ComposerAccessibility.labelToggle(value))
          }
        } footer: {
          AlfText(
            ComposerCopy.labelsDescription,
            scale: .xs,
            color: theme.atomColors.textContrastMedium)
        }
      }
      .navigationTitle(ComposerCopy.labelsTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(ComposerCopy.saveAction, action: onDone)
        }
      }
    }
    .accessibilityIdentifier(ComposerAccessibility.labelsSheet)
  }

  private func binding(for value: String) -> Binding<Bool> {
    Binding(
      get: { labels.contains(value) },
      set: { isOn in
        var next = labels
        if isOn {
          next.insert(value)
        } else {
          next.remove(value)
        }
        onChange(next)
      })
  }
}

/// The reply-permission (threadgate) sheet, with the quoting (postgate) toggle.
///
/// Ported from `threadgate/ThreadgateBtn.tsx`. The UI settings and the record
/// mapping are the logic layer's (`ThreadgateAllowUISetting` /
/// `ComposerGates.allowRecordValue`); this sheet writes settings and never
/// builds a record.
struct ComposerThreadgateSheet: View {
  /// The thread's current reply permissions.
  let threadgate: [ThreadgateAllowUISetting]
  /// Whether anyone may quote the post.
  let allowQuotes: Bool
  /// Called with the edited permissions.
  let onChange: ([ThreadgateAllowUISetting]) -> Void
  /// Called with the edited quoting setting.
  let onQuotesChange: (Bool) -> Void
  /// Dismisses the sheet.
  let onDone: () -> Void

  @Environment(\.alfTheme) private var theme

  /// The settings the sheet offers, in the RN sheet's order.
  private static let options: [ThreadgateAllowUISetting] = [
    .everybody, .nobody, .mention, .following, .followers,
  ]

  /// The first option a stored permission currently matches.
  private var current: ThreadgateAllowUISetting { threadgate.first ?? .everybody }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(Array(Self.options.enumerated()), id: \.offset) { _, option in
            Button {
              onChange([option])
            } label: {
              HStack {
                AlfText(
                  ComposerCopy.threadgateLabel(option),
                  scale: .md,
                  color: theme.atomColors.text)
                Spacer(minLength: Spacing.sm)
                if option == current {
                  Image(systemName: "checkmark")
                    .foregroundStyle(theme.colors.primary500)
                }
              }
            }
            .accessibilityIdentifier(
              ComposerAccessibility.threadgateOption(Self.key(for: option)))
          }
        } footer: {
          AlfText(
            ComposerCopy.threadgateDescription,
            scale: .xs,
            color: theme.atomColors.textContrastMedium)
        }

        Section {
          Toggle(isOn: Binding(get: { allowQuotes }, set: onQuotesChange)) {
            AlfText(ComposerCopy.postgateLabel, scale: .md)
          }
          .tint(theme.colors.primary500)
          .accessibilityIdentifier(ComposerAccessibility.postgateToggle)
        }
      }
      .navigationTitle(ComposerCopy.threadgateTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(ComposerCopy.saveAction, action: onDone)
        }
      }
    }
    .accessibilityIdentifier(ComposerAccessibility.threadgateSheet)
  }

  /// A stable storage key for an option, for the accessibility identifier. A
  /// list rule's key carries its URI, so two lists never collide.
  private static func key(for option: ThreadgateAllowUISetting) -> String {
    switch option {
    case .everybody: "everybody"
    case .nobody: "nobody"
    case .mention: "mention"
    case .following: "following"
    case .followers: "followers"
    case .list(let uri): "list-\(uri)"
    }
  }
}

/// The drafts list.
///
/// Ported from `drafts/DraftsListDialog.tsx`. The rows are ``DraftSummary``
/// values, which the drafts layer produced; the sheet shows what that layer
/// computed (post count, media presence, missing media) rather than
/// re-summarising the draft itself.
struct ComposerDraftsSheet: View {
  /// The draft rows.
  let drafts: [DraftSummary]
  /// Whether the list is still loading.
  let isLoading: Bool
  /// Opens a draft.
  let onOpen: (DraftSummary) -> Void
  /// Deletes a draft.
  let onDelete: (DraftSummary) -> Void
  /// Dismisses the sheet.
  let onDone: () -> Void

  @Environment(\.alfTheme) private var theme

  var body: some View {
    NavigationStack {
      Group {
        if isLoading && drafts.isEmpty {
          ListSkeleton(rowCount: 3)
        } else if drafts.isEmpty {
          EmptyStateView(
            icon: "tray",
            title: ComposerCopy.draftsTitle,
            message: ComposerCopy.draftsEmpty)
        } else {
          List {
            ForEach(drafts, id: \.id) { draft in
              Button {
                onOpen(draft)
              } label: {
                row(draft)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier(ComposerAccessibility.draftRow(draft.id))
              .swipeActions {
                Button(role: .destructive) {
                  onDelete(draft)
                } label: {
                  Label(ComposerCopy.deleteDraftAction, systemImage: "trash")
                }
              }
            }
          }
        }
      }
      .navigationTitle(ComposerCopy.draftsTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(ComposerCopy.saveAction, action: onDone)
        }
      }
    }
    .accessibilityIdentifier(ComposerAccessibility.draftsSheet)
  }

  private func row(_ draft: DraftSummary) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      AlfText(
        draft.posts.first?.text ?? ComposerCopy.draftsEmpty,
        scale: .md,
        color: theme.atomColors.text)
        .lineLimit(2)
      HStack(spacing: Spacing.sm) {
        AlfText(draft.meta.postCount == 1 ? "1 post" : "\(draft.meta.postCount) posts", scale: .xs, color: theme.atomColors.textContrastMedium)
        if draft.meta.hasMedia {
          AlfText("media", scale: .xs, color: theme.atomColors.textContrastMedium)
        }
        if draft.meta.hasMissingMedia {
          AlfText("missing media", scale: .xs, color: theme.colors.negative400)
        }
      }
    }
    .padding(.vertical, Spacing.xxs)
  }
}
#endif
