import DesignSystem
import DesignTokens
import Moderation
import ModerationUILogic
import SwiftUI
import UIComponents

/// The muted words and tags screen.
///
/// A list of the viewer's muted words with a sheet to add or edit one. The list
/// of what to show - applied surfaces, expiry, whether a word excludes followed
/// users - comes from ``MutedWordsEditor/rows(_:items:now:)``; this view renders
/// those rows and forwards edits.
///
/// Ported from `components/dialogs/MutedWords.tsx` and the "Muted words & tags"
/// row's destination in `screens/Moderation/index.tsx`.
public struct MutedWordsScreen: View {
  private let rows: [MutedWordRowModel]
  private let onSubmit: (MutedWordDraft) async -> String?
  private let onRemove: (MutedWordRowModel) -> Void
  private let onRenew: (MutedWordRowModel, Int?) -> Void

  @State private var isAdding = false
  @State private var pendingRemoval: MutedWordRowModel?

  /// Creates the muted-words screen.
  ///
  /// - Parameters:
  ///   - rows: the derived row models, newest first.
  ///   - onSubmit: validates and applies a new word. Returns an error message to
  ///     display, or nil on success.
  ///   - onRemove: removes a word.
  ///   - onRenew: re-mints a word's expiry; a nil `days` clears it ("Forever").
  public init(
    rows: [MutedWordRowModel] = [],
    onSubmit: @escaping (MutedWordDraft) async -> String? = { _ in nil },
    onRemove: @escaping (MutedWordRowModel) -> Void = { _ in },
    onRenew: @escaping (MutedWordRowModel, Int?) -> Void = { _, _ in }
  ) {
    self.rows = rows
    self.onSubmit = onSubmit
    self.onRemove = onRemove
    self.onRenew = onRenew
  }

  @Environment(\.alfTheme) private var theme

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        header

        if rows.isEmpty {
          EmptyStateView(
            icon: "text.badge.xmark",
            title: ModerationCopy.mutedWordsEmptyTitle,
            message: ModerationCopy.mutedWordsEmptyMessage,
            actionLabel: ModerationCopy.addMutedWordAction,
            action: { isAdding = true })
        } else {
          VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
              mutedWordRow(row)
              ModerationDivider()
            }
          }
        }
      }
      .padding(.xl)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(ModerationAccessibility.mutedWordsScreen)
    .sheet(isPresented: $isAdding) {
      MutedWordEditorSheet(
        title: ModerationCopy.addMutedWordAction,
        initial: MutedWordDraft(rawValue: ""),
        onSubmit: onSubmit,
        onCancel: { isAdding = false })
    }
    .confirmationDialog(
      pendingRemoval.map { ModerationCopy.removeMutedWordConfirmation($0.word.value) } ?? "",
      isPresented: Binding(
        get: { pendingRemoval != nil },
        set: { if !$0 { pendingRemoval = nil } }),
      titleVisibility: .visible
    ) {
      Button(ModerationCopy.removeMutedWordAction, role: .destructive) {
        if let row = pendingRemoval { onRemove(row) }
        pendingRemoval = nil
      }
      Button(ModerationCopy.cancelAction, role: .cancel) { pendingRemoval = nil }
    }
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .firstTextBaseline) {
        AlfText(
          ModerationCopy.mutedWordsTitle, scale: .xxl, weight: Scales.FontWeight.bold)
          .frame(maxWidth: .infinity, alignment: .leading)

        Button { isAdding = true } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.alf(color: .primary, size: .small, shape: .round))
        .accessibilityLabel(ModerationCopy.addMutedWordAction)
      }

      AlfText(
        ModerationCopy.mutedWordsDescription, scale: .sm,
        color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func mutedWordRow(_ row: MutedWordRowModel) -> some View {
    HStack(alignment: .center, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        AlfText(
          row.word.value, scale: .md, weight: Scales.FontWeight.semiBold)
        .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: Spacing.xs) {
          if row.appliesToContent {
            ModerationBadge(text: ModerationCopy.appliesToContentBadge)
          }
          if row.excludesFollowing {
            ModerationBadge(text: ModerationCopy.excludesFollowingBadge)
          }
          if let expiry = row.expiryDate {
            if row.isExpired {
              ModerationBadge(text: ModerationCopy.expiredBadge, isWarning: true)
            } else {
              AlfText(
                ModerationCopy.expiryLine(expiry), scale: .xs,
                color: theme.atomColors.textContrastLow)
            }
          }
        }
      }

      Menu {
        ForEach(MutedWordDuration.allCases, id: \.self) { duration in
          Button(ModerationCopy.durationLabel(duration)) { onRenew(row, duration.days) }
        }
        Divider()
        Button(ModerationCopy.removeMutedWordAction, role: .destructive) {
          pendingRemoval = row
        }
      } label: {
        Image(systemName: "ellipsis")
          .foregroundStyle(theme.atomColors.textContrastMedium)
          .padding(.xs)
      }
      .accessibilityLabel(row.word.value)
    }
    .padding(.md, .horizontal)
    .padding(.sm, .vertical)
  }
}

/// Which surfaces a muted word is authored for.
///
/// The editor offers two choices, matching the RN radio: "Text & tags" and "Tags
/// only". ``MutedWordsEditor/payload(for:)`` always includes the `tag` target and
/// adds `content` only for the first, so the two collapse to one selection here.
enum MutedWordTargetChoice: String, Hashable, CaseIterable {
  case contentAndTags
  case tagsOnly

  /// The draft surfaces this choice produces.
  var surfaces: Set<MutedWordSurface> {
    switch self {
    case .contentAndTags: return [.content]
    case .tagsOnly: return [.tag]
    }
  }

  /// The choice for a draft's surfaces, defaulting to tags-only.
  init(surfaces: Set<MutedWordSurface>) {
    self = surfaces.contains(.content) ? .contentAndTags : .tagsOnly
  }

  var label: String {
    switch self {
    case .contentAndTags: return ModerationCopy.targetContentLabel
    case .tagsOnly: return ModerationCopy.targetTagLabel
    }
  }
}

/// The add/edit muted-word sheet.
///
/// Owns only presentation state: the draft in progress and the validation line.
/// Whether the draft is submittable is ``MutedWordsEditor/canSubmit(_:)`` and how
/// it serializes is ``MutedWordsEditor/payload(for:)``, so the sheet cannot
/// disagree with the logic layer about either.
struct MutedWordEditorSheet: View {
  let title: String
  let onSubmit: (MutedWordDraft) async -> String?
  let onCancel: () -> Void

  @State private var draft: MutedWordDraft
  @State private var validationMessage: String?
  @State private var submitError: String?
  @State private var isProcessing = false

  @Environment(\.alfTheme) private var theme

  init(
    title: String,
    initial: MutedWordDraft,
    onSubmit: @escaping (MutedWordDraft) async -> String?,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.onSubmit = onSubmit
    self.onCancel = onCancel
    _draft = State(initialValue: initial)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        AlfText(title, scale: .xl, weight: Scales.FontWeight.bold)

        ModerationTextField(
          label: ModerationCopy.mutedWordFieldLabel,
          placeholder: ModerationCopy.mutedWordPlaceholder,
          text: Binding(
            get: { draft.rawValue },
            set: {
              draft.rawValue = $0
              validationMessage = nil
            }),
          identifier: ModerationAccessibility.mutedWordField)

        ModerationSection(title: ModerationCopy.mutedWordTargetsHeading) {
          ModerationRadioGroup(
            options: MutedWordTargetChoice.allCases,
            label: { $0.label },
            selection: Binding(
              get: { MutedWordTargetChoice(surfaces: draft.surfaces) },
              set: { draft.surfaces = $0.surfaces }),
            identifier: { _ in "" })
        }

        ModerationSection(title: ModerationCopy.mutedWordDurationHeading) {
          VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(MutedWordDuration.allCases, id: \.self) { duration in
              durationOption(duration)
            }
          }
        }

        ModerationToggleRow(
          title: ModerationCopy.excludeFollowingLabel,
          isOn: Binding(
            get: { draft.excludeFollowing },
            set: { draft.excludeFollowing = $0 }))

        if let validationMessage {
          ModerationErrorLine(
            message: validationMessage,
            identifier: ModerationAccessibility.mutedWordValidation)
        }
        if let submitError {
          ModerationErrorLine(message: submitError)
        }

        ModerationSubmitButton(
          title: ModerationCopy.saveMutedWordAction,
          isProcessing: isProcessing,
          identifier: ModerationAccessibility.mutedWordSubmit,
          action: submit)

        Button(ModerationCopy.cancelAction, action: onCancel)
          .buttonStyle(.alf(color: .secondary, size: .large, shape: .rectangular))
          .frame(maxWidth: .infinity)
      }
      .padding(.xl)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(ModerationAccessibility.mutedWordSheet)
  }

  private func durationOption(_ duration: MutedWordDuration) -> some View {
    Button {
      draft.duration = duration
    } label: {
      HStack(spacing: Spacing.sm) {
        Image(
          systemName: draft.duration == duration
            ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(
            draft.duration == duration
              ? theme.colors.primary500 : theme.atomColors.borderContrastHigh)
          .accessibilityHidden(true)
        AlfText(ModerationCopy.durationLabel(duration), scale: .sm)
        Spacer(minLength: 0)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(draft.duration == duration ? [.isSelected] : [])
  }

  private func submit() {
    guard !isProcessing else { return }
    // The logic layer owns both the guard and the message, so the sheet asks it
    // rather than re-deriving "is this value usable".
    guard MutedWordsEditor.canSubmit(draft) else {
      validationMessage = MutedWordsEditor.emptyValueMessage
      return
    }
    validationMessage = nil
    submitError = nil
    isProcessing = true
    Task {
      let error = await onSubmit(draft)
      isProcessing = false
      if let error {
        submitError = error
      }
    }
  }
}

#Preview {
  MutedWordsScreen(rows: ModerationFixtures.mutedWordRows())
}
