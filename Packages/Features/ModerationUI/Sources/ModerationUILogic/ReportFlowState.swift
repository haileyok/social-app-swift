import Foundation

/// The NCII qualifying question's state.
///
/// Port of `NciiQualification`. Present only while the selected reason is
/// `reasonSexualNCII`; the answer decides whether the reporter is sent to the
/// external NCII form or submits in-app.
public struct NciiQualification: Sendable, Hashable {
  /// Whether the reporter is the person depicted. `nil` = unanswered.
  public var isDepicted: Bool?

  public init(isDepicted: Bool? = nil) {
    self.isDepicted = isDepicted
  }
}

/// Where an NCII report should go.
public enum NciiQualificationOutcome: Sendable, Hashable {
  /// The qualifying question has not been answered.
  case pending
  /// The depicted person (or their representative) is sent to the external form.
  case externalForm
  /// Everyone else submits in-app.
  case inApp
}

/// Resolves the NCII question into an outcome.
///
/// Port of `getNciiQualificationOutcome`. `nil` state means "not an NCII
/// report", which is distinct from an unanswered question.
public func getNciiQualificationOutcome(
  _ ncii: NciiQualification?
) -> NciiQualificationOutcome? {
  guard let ncii else { return nil }
  switch ncii.isDepicted {
  case .some(true): return .externalForm
  case .some(false): return .inApp
  case .none: return .pending
  }
}

/// The report dialog's state.
///
/// Port of `ReportState` in
/// `src/components/moderation/ReportDialog/state.ts`.
public struct ReportState: Sendable, Hashable {
  public var selectedCategory: ReportCategory?
  public var selectedReason: ReportReason?
  public var selectedLabelerDid: String?
  /// True while the selected labeler's detail view is loaded, so the reducer
  /// can apply `selectLabeler` without carrying the whole view.
  public var details: String?
  public var detailsOpen: Bool
  public var activeStepIndex1: Int
  public var error: String?
  /// Whether to attach how far the viewer had watched. Only offered for posts
  /// with a video, and opted into per labeler.
  public var includeVideoTimestamp: Bool
  /// Present while the selected reason is NCII.
  public var ncii: NciiQualification?

  public init(
    selectedCategory: ReportCategory? = nil,
    selectedReason: ReportReason? = nil,
    selectedLabelerDid: String? = nil,
    details: String? = nil,
    detailsOpen: Bool = false,
    activeStepIndex1: Int = 1,
    error: String? = nil,
    includeVideoTimestamp: Bool = false,
    ncii: NciiQualification? = nil
  ) {
    self.selectedCategory = selectedCategory
    self.selectedReason = selectedReason
    self.selectedLabelerDid = selectedLabelerDid
    self.details = details
    self.detailsOpen = detailsOpen
    self.activeStepIndex1 = activeStepIndex1
    self.error = error
    self.includeVideoTimestamp = includeVideoTimestamp
    self.ncii = ncii
  }

  /// The RN `initialState`.
  public static let initial = ReportState()
}

/// One dialog interaction.
///
/// Port of `ReportAction`.
public enum ReportAction: Sendable {
  /// `otherOption` is the option a category's "other" entry resolves to; RN
  /// passes it in so selecting the "other" CATEGORY skips straight to step 3
  /// with the generic option already chosen.
  case selectCategory(category: ReportCategory, otherReason: ReportReason)
  case clearCategory
  case selectReason(ReportReason)
  case clearReason
  case answerNciiQuestion(isDepicted: Bool)
  case selectLabeler(did: String)
  case clearLabeler
  case setDetails(String)
  case setError(String)
  case clearError
  case showDetails
  case setIncludeVideoTimestamp(Bool)
}

/// Applies one action to the report state.
///
/// Port of the `reducer` in `state.ts`. Every step-index transition is
/// reproduced exactly, including the NCII gating that holds the dialog at step
/// 2 until the qualifying question is answered.
public func reportReducer(_ state: ReportState, _ action: ReportAction) -> ReportState {
  var next = state
  switch action {
  case .setDetails(let details):
    next.details = details
  case .setError(let error):
    next.error = error
  case .clearError:
    next.error = nil
  case .showDetails:
    next.detailsOpen = true
  case .setIncludeVideoTimestamp(let include):
    next.includeVideoTimestamp = include
  default:
    return reportReducerNavigation(state, action)
  }
  return next
}

/// The reducer's navigation-affecting actions: the ones that pick or clear a
/// category, reason or labeler and therefore reposition the dialog.
///
/// Split from ``reportReducer(_:_:)`` so neither function exceeds the
/// function-body-length budget.
func reportReducerNavigation(_ state: ReportState, _ action: ReportAction) -> ReportState {
  var next = state
  switch action {
  case .selectCategory(let category, let otherReason):
    next.selectedCategory = category
    next.activeStepIndex1 = category.key == .other ? 3 : 2
    next.selectedReason = category.key == .other ? otherReason : nil

  case .clearCategory:
    next = ReportState(activeStepIndex1: 1)

  case .selectReason(let reason):
    let isNcii = reason.reason == ReportReasons.sexualNCII
    next.selectedReason = reason
    // NCII requires the qualifying question before the flow advances.
    next.activeStepIndex1 = isNcii ? 2 : 3
    next.detailsOpen = otherReportReasons.contains(reason.reason)
    next.ncii = isNcii ? NciiQualification() : nil

  case .clearReason:
    next.selectedReason = nil
    next.selectedLabelerDid = nil
    next.activeStepIndex1 = 2
    next.detailsOpen = false
    next.ncii = nil
    next.includeVideoTimestamp = false

  case .answerNciiQuestion(let isDepicted):
    let ncii = NciiQualification(isDepicted: isDepicted)
    next.ncii = ncii
    next.activeStepIndex1 =
      getNciiQualificationOutcome(ncii) == .inApp
      ? (next.selectedLabelerDid != nil ? 4 : 3)
      : 2

  case .selectLabeler(let did):
    next.selectedLabelerDid = did
    // Labelers may be auto-selected, so a pending NCII question still wins.
    next.activeStepIndex1 =
      getNciiQualificationOutcome(next.ncii) == .inApp || next.ncii == nil ? 4 : 2
    if let reason = next.selectedReason {
      next.detailsOpen = otherReportReasons.contains(reason.reason)
    } else {
      next.detailsOpen = false
    }
    // Picking a service is a fresh consent decision: the video-timestamp opt-in
    // is scoped to Bluesky and must not survive a switch.
    next.includeVideoTimestamp = false

  case .clearLabeler:
    next.selectedLabelerDid = nil
    next.activeStepIndex1 = 3
    next.includeVideoTimestamp = false

  default:
    // The plain setters are handled by `reportReducer`; reaching here means a
    // new case was added to `ReportAction` without a handler.
    return state
  }
  return next
}
