import Foundation
import Testing

@testable import ModerationUILogic

/// Port of `src/components/moderation/ReportDialog/state.test.ts`.
@Suite("Report dialog state")
struct ReportStateTests {

  private let nciiReason = ReportReason(
    reason: ReportReasons.sexualNCII, title: "Non-consensual intimate imagery")
  private let otherReason = ReportReason(
    reason: ReportReasons.sexualUnlabeled, title: "Unlabeled adult content")

  private func selectNcii(_ state: ReportState = .initial) -> ReportState {
    reportReducer(state, .selectReason(nciiReason))
  }

  private func selectOther(_ state: ReportState = .initial) -> ReportState {
    reportReducer(state, .selectReason(otherReason))
  }

  // MARK: - NCII qualification

  @Test("getNciiQualificationOutcome is undefined when not an NCII report")
  func outcomeUndefinedWithoutNcii() {
    #expect(getNciiQualificationOutcome(nil) == nil)
  }

  @Test("getNciiQualificationOutcome is pending until the question is answered")
  func outcomePending() {
    #expect(getNciiQualificationOutcome(NciiQualification()) == .pending)
  }

  @Test("getNciiQualificationOutcome sends the depicted person to the external form")
  func outcomeExternalForm() {
    #expect(getNciiQualificationOutcome(NciiQualification(isDepicted: true)) == .externalForm)
  }

  @Test("getNciiQualificationOutcome sends everyone else in-app")
  func outcomeInApp() {
    #expect(getNciiQualificationOutcome(NciiQualification(isDepicted: false)) == .inApp)
  }

  @Test("selecting the NCII reason holds the flow at step 2")
  func nciiReasonHoldsAtStepTwo() {
    let state = selectNcii()
    #expect(state.activeStepIndex1 == 2)
    #expect(state.ncii == NciiQualification())
  }

  @Test("a non-NCII reason does not gate")
  func nonNciiReasonAdvances() {
    let state = selectOther()
    #expect(state.activeStepIndex1 == 3)
    #expect(state.ncii == nil)
  }

  @Test("answering yes holds at step 2 for the external form")
  func nciiDepictedHoldsAtTwo() {
    var state = selectNcii()
    state = reportReducer(state, .answerNciiQuestion(isDepicted: true))
    #expect(getNciiQualificationOutcome(state.ncii) == .externalForm)
    #expect(state.activeStepIndex1 == 2)
  }

  @Test("answering no advances to step 3")
  func nciiNotDepictedAdvances() {
    var state = selectNcii()
    state = reportReducer(state, .answerNciiQuestion(isDepicted: false))
    #expect(state.activeStepIndex1 == 3)
  }

  @Test("an auto-selected labeler does not advance past a pending NCII question")
  func labelerDoesNotSkipPendingNcii() {
    var state = selectNcii()
    state = reportReducer(state, .selectLabeler(did: bskyModerationDid))
    #expect(state.activeStepIndex1 == 2)
  }

  @Test("an answered question advances to step 4 once a labeler is set")
  func nciiResolvesToStepFourWithLabeler() {
    var state = selectNcii()
    state = reportReducer(state, .selectLabeler(did: bskyModerationDid))
    state = reportReducer(state, .answerNciiQuestion(isDepicted: false))
    #expect(state.activeStepIndex1 == 4)
  }

  @Test("answering no with no labeler advances only to step 3")
  func nciiResolvesToStepThreeWithoutLabeler() {
    var state = selectNcii()
    state = reportReducer(state, .answerNciiQuestion(isDepicted: false))
    #expect(state.activeStepIndex1 == 3)
  }

  @Test("clearing the reason clears the NCII state")
  func clearReasonClearsNcii() {
    let state = selectNcii()
    #expect(reportReducer(state, .clearReason).ncii == nil)
  }

  @Test("clearing the category clears the NCII state")
  func clearCategoryClearsNcii() {
    let state = selectNcii()
    #expect(reportReducer(state, .clearCategory).ncii == nil)
  }

  // MARK: - Category selection

  @Test("selecting a non-other category advances to step 2 with no reason yet")
  func selectCategoryAdvancesToTwo() {
    let state = reportReducer(
      .initial,
      .selectCategory(
        category: ReportReasonCatalog.category(.violencePhysicalHarm),
        otherReason: ReportReason(reason: ReportReasons.other, title: "Other")))
    #expect(state.activeStepIndex1 == 2)
    #expect(state.selectedReason == nil)
  }

  @Test("selecting the other category jumps to step 3 with the other reason set")
  func selectOtherCategoryJumpsToThree() {
    let other = ReportReason(reason: ReportReasons.other, title: "Other")
    let state = reportReducer(
      .initial, .selectCategory(category: ReportReasonCatalog.category(.other), otherReason: other))
    #expect(state.activeStepIndex1 == 3)
    #expect(state.selectedReason == other)
  }

  @Test("clearing the category resets the dialog")
  func clearCategoryResets() {
    var state = selectOther()
    state = reportReducer(state, .clearLabeler)
    state = reportReducer(state, .clearCategory)
    #expect(state.selectedCategory == nil)
    #expect(state.selectedReason == nil)
    #expect(state.selectedLabelerDid == nil)
    #expect(state.activeStepIndex1 == 1)
    #expect(!state.detailsOpen)
    #expect(state.ncii == nil)
    #expect(!state.includeVideoTimestamp)
  }

  @Test("clearing the reason returns to step 2")
  func clearReasonReturnsToTwo() {
    let state = reportReducer(selectOther(), .clearReason)
    #expect(state.selectedReason == nil)
    #expect(state.activeStepIndex1 == 2)
    #expect(!state.detailsOpen)
  }

  // MARK: - Details field

  @Test("an 'other'-style reason opens the details field")
  func otherReasonOpensDetails() {
    let reason = ReportReason(reason: ReportReasons.harassmentOther, title: "Other harassing")
    #expect(reportReducer(.initial, .selectReason(reason)).detailsOpen)
  }

  @Test("a non-other reason leaves the details field closed")
  func nonOtherReasonKeepsDetailsClosed() {
    #expect(!selectOther().detailsOpen)
  }

  @Test("showDetails opens the field explicitly")
  func showDetails() {
    #expect(reportReducer(.initial, .showDetails).detailsOpen)
  }

  // MARK: - Labeler selection

  @Test("selecting a labeler advances to step 4")
  func selectLabelerAdvances() {
    var state = selectOther()
    state = reportReducer(state, .selectLabeler(did: "did:plc:labeler"))
    #expect(state.activeStepIndex1 == 4)
    #expect(state.selectedLabelerDid == "did:plc:labeler")
  }

  @Test("clearing the labeler returns to step 3")
  func clearLabelerReturnsToThree() {
    var state = selectOther()
    state = reportReducer(state, .selectLabeler(did: "did:plc:labeler"))
    state = reportReducer(state, .clearLabeler)
    #expect(state.selectedLabelerDid == nil)
    #expect(state.activeStepIndex1 == 3)
  }

  @Test("selecting a labeler restores detailsOpen from the selected reason")
  func selectLabelerRecomputesDetails() {
    let reason = ReportReason(reason: ReportReasons.ruleOther, title: "Other network rule-breaking")
    var state = reportReducer(.initial, .selectReason(reason))
    state = reportReducer(state, .selectLabeler(did: "did:plc:labeler"))
    #expect(state.detailsOpen)
  }

  // MARK: - Video timestamp

  @Test("the video timestamp is off by default")
  func videoTimestampOffByDefault() {
    #expect(!ReportState.initial.includeVideoTimestamp)
  }

  @Test("the video timestamp toggles on and back off")
  func videoTimestampToggles() {
    var state = reportReducer(.initial, .setIncludeVideoTimestamp(true))
    #expect(state.includeVideoTimestamp)
    state = reportReducer(state, .setIncludeVideoTimestamp(false))
    #expect(!state.includeVideoTimestamp)
  }

  @Test("clearing the labeler clears the video timestamp")
  func clearLabelerClearsVideoTimestamp() {
    let opted = ReportState(includeVideoTimestamp: true)
    #expect(!reportReducer(opted, .clearLabeler).includeVideoTimestamp)
  }

  @Test("selecting a labeler clears the video timestamp")
  func selectLabelerClearsVideoTimestamp() {
    let opted = ReportState(includeVideoTimestamp: true)
    #expect(
      !reportReducer(opted, .selectLabeler(did: "did:plc:labeler")).includeVideoTimestamp)
  }

  @Test("clearing the reason clears the video timestamp")
  func clearReasonClearsVideoTimestamp() {
    let opted = ReportState(includeVideoTimestamp: true)
    #expect(!reportReducer(opted, .clearReason).includeVideoTimestamp)
  }

  @Test("clearing the category clears the video timestamp")
  func clearCategoryClearsVideoTimestamp() {
    let opted = ReportState(includeVideoTimestamp: true)
    #expect(!reportReducer(opted, .clearCategory).includeVideoTimestamp)
  }

  // MARK: - Details / error

  @Test("setDetails stores the comment")
  func setDetails() {
    #expect(reportReducer(.initial, .setDetails("why")).details == "why")
  }

  @Test("setError and clearError round-trip")
  func errorRoundTrip() {
    let withError = reportReducer(.initial, .setError("boom"))
    #expect(withError.error == "boom")
    #expect(reportReducer(withError, .clearError).error == nil)
  }
}
