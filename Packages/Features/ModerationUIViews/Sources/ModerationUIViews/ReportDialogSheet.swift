import DesignSystem
import DesignTokens
import ModerationUILogic
import SwiftUI
import UIComponents

/// The report dialog, as a reusable sheet.
///
/// The flow is a four-step machine owned by `ModerationUILogic`: pick a category,
/// pick a reason, pick a moderation service, then add details and submit. Every
/// transition is a ``reportReducer(_:_:)`` call and the step the dialog shows is
/// the reducer's `activeStepIndex1`, so the sheet never advances itself. Which
/// services may review the report is ``ReportFlow/supportedLabelers(_:subject:reason:)``,
/// the reason list is ``ReportReasonCatalog``, and a failure's user-facing copy is
/// picked from ``ReportErrorClassifier``'s bucket.
///
/// Ported from `components/moderation/ReportDialog/index.tsx` and `state.ts`. The
/// sheet stays free of the network: it hands the app the final ``ReportState``
/// and lets the app build the body with ``ReportFlow/submission(state:subject:labelerReasonTypes:modToolName:videoTimestampSeconds:apiModerationDid:)``
/// and send it, which keeps the wire shape in the logic package.
public struct ReportDialogSheet: View {
  private let subject: ParsedReportSubject
  private let labelers: [ReportLabeler]
  private let modToolName: String?
  private let videoTimestampSeconds: Int?
  private let onSubmitted: () -> Void
  private let onCancel: () -> Void
  private let onSubmit: (ReportState, ParsedReportSubject) async throws -> Void

  @State private var state: ReportState = .initial
  @State private var isSubmitting = false
  @State private var didSubmit = false
  @State private var errorMessage: String?

  /// Creates the report sheet.
  ///
  /// - Parameters:
  ///   - subject: the parsed subject being reported.
  ///   - labelers: the candidate moderation services. The eligible subset is
  ///     computed from these as the reason is chosen.
  ///   - modToolName: the client identifier, merged into `modTool` for an
  ///     opted-in video timestamp.
  ///   - videoTimestampSeconds: the watch position, when the caller has one.
  ///   - onSubmit: builds and sends the report. A thrown error is classified and
  ///     rendered.
  ///   - onSubmitted: called after a successful submit.
  ///   - onCancel: called when the viewer dismisses without reporting.
  public init(
    subject: ParsedReportSubject,
    labelers: [ReportLabeler] = [],
    modToolName: String? = nil,
    videoTimestampSeconds: Int? = nil,
    onSubmit: @escaping (ReportState, ParsedReportSubject) async throws -> Void = { _, _ in },
    onSubmitted: @escaping () -> Void = {},
    onCancel: @escaping () -> Void = {}
  ) {
    self.subject = subject
    self.labelers = labelers
    self.modToolName = modToolName
    self.videoTimestampSeconds = videoTimestampSeconds
    self.onSubmit = onSubmit
    self.onSubmitted = onSubmitted
    self.onCancel = onCancel
  }

  @Environment(\.alfTheme) private var theme
  @Environment(\.openURL) private var openURL

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
          if didSubmit {
            successState
          } else {
            header
            stepContent
            errorSection
          }
        }
        .padding(.xl)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
      }
      .background(theme.atomColors.bg)
      .navigationTitle(ModerationCopy.reportCopy(for: subject).title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(ModerationCopy.cancelAction, action: onCancel)
        }
        if state.activeStepIndex1 > 1 && !didSubmit {
          ToolbarItem(placement: .topBarTrailing) {
            Button(ModerationCopy.backAction, action: stepBack)
          }
        }
      }
    }
    .accessibilityIdentifier(ModerationAccessibility.reportSheet)
  }

  // MARK: - Chrome

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(
        ModerationCopy.reportCopy(for: subject).subtitle, scale: .sm,
        color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch state.activeStepIndex1 {
    case 1:
      categoryStep
    case 2:
      if state.ncii != nil {
        nciiStep
      } else {
        reasonStep
      }
    case 3:
      labelerStep
    default:
      detailsStep
    }
  }

  // MARK: - Steps

  private var categoryStep: some View {
    VStack(spacing: 0) {
      ForEach(ReportReasonCatalog.categories, id: \.key) { category in
        ModerationRow(
          title: category.title, subtitle: category.description,
          action: { dispatch(.selectCategory(category: category, otherReason: otherReason(for: category))) }
        ) {
          Image(systemName: "chevron.right")
            .foregroundStyle(theme.atomColors.textContrastLow)
            .accessibilityHidden(true)
        }
        ModerationDivider()
      }
    }
    .accessibilityIdentifier(ModerationAccessibility.reportStepCategory)
  }

  private var reasonStep: some View {
    VStack(spacing: 0) {
      ForEach(state.selectedCategory?.options ?? [], id: \.reason) { reason in
        ModerationRow(
          title: reason.title,
          action: { dispatch(.selectReason(reason)) }
        ) {
          Image(systemName: "chevron.right")
            .foregroundStyle(theme.atomColors.textContrastLow)
            .accessibilityHidden(true)
        }
        ModerationDivider()
      }
    }
    .accessibilityIdentifier(ModerationAccessibility.reportStepReason)
  }

  /// The NCII qualifying question, which holds the dialog at step 2 until it is
  /// answered. The reducer is what keeps it there, so this only renders the two
  /// answers and the external-form outcome.
  private var nciiStep: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      AlfText(
        "Are you the person depicted in this content?", scale: .md,
        weight: Scales.FontWeight.semiBold)
        .fixedSize(horizontal: false, vertical: true)

      if getNciiQualificationOutcome(state.ncii) == .externalForm {
        ModerationNotice(
          message:
            "Reports of this kind are handled through a dedicated form so they reach the right team.",
          kind: .info)
        AlfButton(
          "Open the form", color: .primary, size: .large, shape: .rectangular
        ) {
          if let url = URL(string: "https://forms.bsky.app/f/ncii") {
            openURL(url)
          }
        }
        .frame(maxWidth: .infinity)
      } else {
        Button("Yes, that is me") { dispatch(.answerNciiQuestion(isDepicted: true)) }
          .buttonStyle(.alf(color: .secondary, size: .large, shape: .rectangular))
          .frame(maxWidth: .infinity)
        Button("No") { dispatch(.answerNciiQuestion(isDepicted: false)) }
          .buttonStyle(.alf(color: .secondary, size: .large, shape: .rectangular))
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var labelerStep: some View {
    VStack(spacing: 0) {
      ForEach(eligibleLabelers, id: \.did) { labeler in
        ModerationRow(
          title: labeler.title, subtitle: "@\(labeler.handle)",
          action: { dispatch(.selectLabeler(did: labeler.did)) }
        ) {
          if state.selectedLabelerDid == labeler.did {
            Image(systemName: "checkmark")
              .foregroundStyle(theme.colors.primary500)
              .accessibilityHidden(true)
          }
        }
        ModerationDivider()
      }
    }
  }

  private var detailsStep: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      if state.detailsOpen {
        ModerationTextField(
          label: ModerationCopy.reportDetailsHeading,
          placeholder: ModerationCopy.reportDetailsPlaceholder,
          text: Binding(
            get: { state.details ?? "" },
            set: { dispatch(.setDetails($0)) }),
          identifier: ModerationAccessibility.reportDetailsField,
          isMultiline: true)
      }

      ModerationSubmitButton(
        title: ModerationCopy.submitReportAction,
        isProcessing: isSubmitting,
        identifier: ModerationAccessibility.reportSubmit,
        action: submit)
    }
  }

  private var successState: some View {
    EmptyStateView(
      icon: "checkmark.circle",
      title: ModerationCopy.reportSuccessTitle,
      message: ModerationCopy.reportSuccessMessage,
      actionLabel: ModerationCopy.cancelAction,
      action: onSubmitted)
      .accessibilityIdentifier(ModerationAccessibility.reportSuccess)
  }

  @ViewBuilder
  private var errorSection: some View {
    if let errorMessage {
      ModerationErrorLine(
        message: errorMessage, identifier: ModerationAccessibility.reportError)
    }
  }

  // MARK: - Derivation

  /// The services that can review this subject with this reason.
  ///
  /// Port of the three filter passes in the RN dialog; the passes themselves live
  /// in ``ReportFlow/supportedLabelers(_:subject:reason:)``.
  private var eligibleLabelers: [ReportLabeler] {
    guard let reason = state.selectedReason else { return [] }
    let capabilities = labelers.map(\.capabilities)
    let supported = Set(
      ReportFlow.supportedLabelers(capabilities, subject: subject, reason: reason.reason)
        .map(\.did))
    return labelers.filter { supported.contains($0.did) }
  }

  /// The option the "other" category jumps to, which is its single entry.
  private func otherReason(for category: ReportCategory) -> ReportReason {
    category.options.first ?? ReportReason(reason: ReportReasons.other, title: "Other")
  }

  // MARK: - Actions

  private func dispatch(_ action: ReportAction) {
    state = reportReducer(state, action)
    // A fresh selection invalidates the previous failure, which belonged to it.
    errorMessage = nil
    // A sole eligible service is selected automatically, exactly as the RN
    // dialog does: with one option a picker is a pointless tap.
    autoSelectSoleLabeler()
  }

  private func autoSelectSoleLabeler() {
    // A pending NCII question outranks the picker, and the reducer keeps the
    // dialog at step 2 in that case, so there is nothing to advance here.
    guard state.ncii == nil || getNciiQualificationOutcome(state.ncii) == .inApp else { return }
    let eligible = eligibleLabelers
    guard eligible.count == 1, state.selectedLabelerDid != eligible[0].did else { return }
    state = reportReducer(state, .selectLabeler(did: eligible[0].did))
  }

  /// Steps back one screen.
  ///
  /// The reducer owns the transitions, so going back re-enters the earlier step
  /// by clearing the selection that got us here: clearing the reason returns to
  /// the reason list, clearing the category returns to the start.
  private func stepBack() {
    errorMessage = nil
    switch state.activeStepIndex1 {
    case 4: dispatch(.clearLabeler)
    case 3: dispatch(.clearReason)
    default: dispatch(.clearCategory)
    }
  }

  private func submit() {
    guard !isSubmitting else { return }
    isSubmitting = true
    errorMessage = nil
    Task {
      do {
        try await onSubmit(state, subject)
        isSubmitting = false
        didSubmit = true
      } catch {
        isSubmitting = false
        // The failure copy is chosen from the classifier's bucket, so an
        // unexpected failure and a service outage read differently to the user
        // and carry the same bucket to telemetry.
        let classification = ReportErrorClassifier.classify(error)
        errorMessage = ModerationCopy.reportErrorMessage(classification)
        state = reportReducer(state, .setError(classification.bucket))
        // An unsupported reason is the service's answer about the selection, so
        // the viewer is sent back to pick another one.
        if classification.kind == .invalidReasonType {
          state = reportReducer(state, .clearLabeler)
        }
      }
    }
  }
}

/// The dialog's failure state for a subject that cannot be reported.
///
/// The RN dialog renders this when `parseReportSubject` returns undefined; the
/// Swift caller parses before presenting, so this is what it shows instead of a
/// flow that would have no subject to submit.
public struct ReportInvalidSubjectView: View {
  private let onDismiss: () -> Void

  public init(onDismiss: @escaping () -> Void = {}) {
    self.onDismiss = onDismiss
  }

  public var body: some View {
    EmptyStateView(
      icon: "exclamationmark.triangle",
      title: ModerationCopy.invalidReportSubjectTitle,
      message: ModerationCopy.invalidReportSubjectMessage,
      actionLabel: ModerationCopy.cancelAction,
      action: onDismiss)
      .accessibilityIdentifier(ModerationAccessibility.reportInvalidSubject)
  }
}

#Preview {
  ReportDialogSheet(
    subject: ModerationFixtures.reportSubject(),
    labelers: ModerationFixtures.reportLabelers())
}
