import Foundation
import Lexicons
import SwiftAtproto
import Testing

@testable import StarterPacksLogic

/// Asserts membership detection, opt-out state and the follow-all target set.
@Suite("StarterPackMembership")
struct MembershipTests {
  // MARK: - Detection

  @Test("a row with a list item means the viewer is a member")
  func memberFromRow() {
    let membership = StarterPackMembershipDerivation.fromRow(
      Fixtures.membershipRow(member: true))
    #expect(membership.isMember)
    #expect(membership.listItemURI == "at://\(Fixtures.authorDID)/app.bsky.graph.listitem/m1")
  }

  @Test("a row without a list item means the viewer is not a member")
  func nonMemberFromRow() {
    let membership = StarterPackMembershipDerivation.fromRow(
      Fixtures.membershipRow(member: false))
    #expect(membership.isMember == false)
    #expect(membership.listItemURI == nil)
  }

  @Test("membership is found by pack URI across a page of rows")
  func membershipFromRows() {
    let rows = [
      Fixtures.membershipRow(packURI: Fixtures.packURI(rkey: "a"), member: true),
      Fixtures.membershipRow(packURI: Fixtures.packURI(rkey: "b"), member: false),
    ]
    #expect(
      StarterPackMembershipDerivation.fromRows(rows, packURI: Fixtures.packURI(rkey: "a"))?.isMember
        == true)
    #expect(
      StarterPackMembershipDerivation.fromRows(rows, packURI: Fixtures.packURI(rkey: "b"))?
        .isMember == false)
    // A pack with no row is unknown, not "not a member".
    #expect(StarterPackMembershipDerivation.fromRows(rows, packURI: Fixtures.packURI(rkey: "z")) == nil)
  }

  // MARK: - Opt-out

  @Test("an opt-out URI on the list viewer means the viewer opted out")
  func optOutDetected() {
    let view = Fixtures.packView(
      listViewer: App.Bsky.GraphDefs_ListViewerState(
        referenceListOptOut: FormatString<ATURI>(
          rawValue: "at://did:plc:viewer/app.bsky.graph.referencelistoptout/opt1")))
    let membership = StarterPackMembershipDerivation.fromPackView(view)
    #expect(membership.hasOptedOut)
    #expect(
      membership.referenceListOptOutURI
        == "at://did:plc:viewer/app.bsky.graph.referencelistoptout/opt1")
    // The viewer state says nothing about membership.
    #expect(membership.isMember == false)
  }

  @Test("no opt-out URI means the viewer has not opted out")
  func optOutAbsent() {
    let membership = StarterPackMembershipDerivation.fromPackView(Fixtures.packView())
    #expect(membership.hasOptedOut == false)
    #expect(membership.referenceListOptOutURI == nil)
  }

  @Test("the menu offers the inverse of the current opt-out state")
  func optOutMenuAction() {
    #expect(StarterPackMembershipDerivation.optOutMenuAction(hasOptedOut: false) == .optOut)
    #expect(StarterPackMembershipDerivation.optOutMenuAction(hasOptedOut: true) == .undo)
  }

  @Test("an opt-out record names the list, not the pack, as its subject")
  func optOutRecord() {
    let record = StarterPackOptOutPlanner.optOutRecord(
      listURI: Fixtures.listURI(), createdAt: "2026-08-31T00:00:00.000Z")
    #expect(
      Fixtures.canonical(record)
        == #"{"$type":"app.bsky.graph.referencelistoptout","createdAt":"2026-08-31T00:00:00.000Z","subject":"at://did:plc:author/app.bsky.graph.list/3l4posztwzy2e"}"#)
  }

  @Test("opting out plans a create; undoing plans a delete of the named record")
  func optOutPlans() {
    let optOut = StarterPackOptOutPlanner.plan(
      action: .optOut, listURI: Fixtures.listURI(), repo: Fixtures.otherDID,
      existingOptOutURI: nil, createdAt: "2026-08-31T00:00:00.000Z")
    guard case .create(let repo, _) = optOut else {
      Issue.record("expected a create")
      return
    }
    #expect(repo == Fixtures.otherDID)

    let undoURI = "at://\(Fixtures.otherDID)/app.bsky.graph.referencelistoptout/opt1"
    let undo = StarterPackOptOutPlanner.plan(
      action: .undo, listURI: Fixtures.listURI(), repo: Fixtures.otherDID,
      existingOptOutURI: undoURI, createdAt: "2026-08-31T00:00:00.000Z")
    #expect(undo == .delete(repo: Fixtures.otherDID, rkey: "opt1"))
  }

  @Test("undoing without a known record plans nothing")
  func undoWithoutRecord() {
    #expect(
      StarterPackOptOutPlanner.plan(
        action: .undo, listURI: Fixtures.listURI(), repo: Fixtures.otherDID,
        existingOptOutURI: nil, createdAt: "2026-08-31T00:00:00.000Z") == nil)
  }
}

/// Asserts the follow-all target derivation and the wizard's member seeding.
@Suite("StarterPackFollowAll")
struct FollowAllTests {
  @Test("the viewer is excluded from the follow-all targets")
  func excludesSelf() {
    let items = [
      Fixtures.listItem(Fixtures.authorDID, rkey: "self"),
      Fixtures.listItem(Fixtures.memberDID, rkey: "m"),
    ]
    #expect(
      StarterPackMembersQuery.followAllTargets(items: items, viewerDID: Fixtures.authorDID)
        == [Fixtures.memberDID])
  }

  @Test("an already-followed account is excluded")
  func excludesFollowing() {
    let items = [
      Fixtures.listItem(Fixtures.memberDID, rkey: "m", viewer: Fixtures.following(Fixtures.memberDID)),
      Fixtures.listItem(Fixtures.otherDID, rkey: "o"),
    ]
    #expect(
      StarterPackMembersQuery.followAllTargets(items: items, viewerDID: Fixtures.authorDID)
        == [Fixtures.otherDID])
  }

  @Test("blocked and muted accounts are excluded")
  func excludesBlockedAndMuted() {
    let items = [
      Fixtures.listItem("did:plc:blocked", rkey: "b", viewer: Fixtures.blocked()),
      Fixtures.listItem("did:plc:muted", rkey: "m", viewer: Fixtures.muted()),
      Fixtures.listItem(Fixtures.otherDID, rkey: "o"),
    ]
    #expect(
      StarterPackMembersQuery.followAllTargets(items: items, viewerDID: Fixtures.authorDID)
        == [Fixtures.otherDID])
  }

  @Test("targets keep list order")
  func preservesOrder() {
    let items = (0..<4).map { Fixtures.listItem("did:plc:m\($0)", rkey: "r\($0)") }
    #expect(
      StarterPackMembersQuery.followAllTargets(items: items, viewerDID: nil)
        == (0..<4).map { "did:plc:m\($0)" })
  }

  @Test("a logged-out viewer excludes nobody")
  func loggedOut() {
    let items = [Fixtures.listItem(Fixtures.authorDID, rkey: "self")]
    #expect(
      StarterPackMembersQuery.followAllTargets(items: items, viewerDID: nil)
        == [Fixtures.authorDID])
  }

  // MARK: - Wizard seeding

  @Test("the wizard seeds from members who did not opt out")
  func seedableMembers() {
    let items = [
      Fixtures.listItem("did:plc:a", rkey: "a"),
      Fixtures.listItem("did:plc:b", rkey: "b", subjectOptedOut: true),
      Fixtures.listItem("did:plc:c", rkey: "c", subjectOptedOut: false),
    ]
    #expect(
      StarterPackMemberSelection.seedableMembers(items).map { $0.did.rawValue }
        == ["did:plc:a", "did:plc:c"])
  }

  @Test("the opted-out set drives the wizard's badge")
  func optedOutDIDs() {
    let items = [
      Fixtures.listItem("did:plc:a", rkey: "a"),
      Fixtures.listItem("did:plc:b", rkey: "b", subjectOptedOut: true),
    ]
    #expect(StarterPackMemberSelection.optedOutDIDs(items) == ["did:plc:b"])
  }
}

/// Asserts the string sanitizers the default pack name depends on.
@Suite("StarterPackStrings")
struct StringTests {
  @Test("a display name drops check marks and control characters")
  func sanitizeDisplayName() {
    #expect(StarterPackStrings.sanitizeDisplayName("Al\u{2705}ice") == "Alice")
    #expect(StarterPackStrings.sanitizeDisplayName("Al\u{0007}ice") == "Alice")
  }

  @Test("a display name collapses repeated whitespace and trims")
  func collapseWhitespace() {
    #expect(StarterPackStrings.sanitizeDisplayName("  a   b  ") == "a b")
    #expect(StarterPackStrings.sanitizeDisplayName("a \u{200B} b") == "a b")
  }

  @Test("a handle is lowercased and prefixed")
  func sanitizeHandle() {
    #expect(StarterPackStrings.sanitizeHandle("Alice.Test") == "alice.test")
    #expect(StarterPackStrings.sanitizeHandle("Alice.Test", prefix: "@") == "@alice.test")
  }

  @Test("the invalid-handle sentinel is replaced with a warning")
  func invalidHandle() {
    #expect(StarterPackStrings.sanitizeHandle("handle.invalid") == "\u{26A0}Invalid Handle")
  }

  @Test("enforceLen slices and optionally marks the cut")
  func enforceLen() {
    #expect(StarterPackStrings.enforceLen("abcdef", 3) == "abc")
    #expect(StarterPackStrings.enforceLen("abcdef", 3, ellipsis: true) == "abc\u{2026}")
    #expect(StarterPackStrings.enforceLen("abc", 3) == "abc")
  }

  @Test("the default pack name uses the display name, apostrophe and 50-slice")
  func defaultPackName() {
    #expect(
      StarterPackStrings.defaultPackName(displayName: "Alice", handle: "alice.test")
        == "Alice\u{2019}s Starter Pack")
  }

  @Test("the default pack name falls back to the handle")
  func defaultPackNameFallback() {
    #expect(
      StarterPackStrings.defaultPackName(displayName: nil, handle: "alice.test")
        == "alice.test\u{2019}s Starter Pack")
    #expect(
      StarterPackStrings.defaultPackName(displayName: "", handle: "alice.test")
        == "alice.test\u{2019}s Starter Pack")
  }

  @Test("a very long default pack name is sliced to 50 characters")
  func defaultPackNameTruncation() {
    let name = StarterPackStrings.defaultPackName(
      displayName: String(repeating: "a", count: 80), handle: "alice.test")
    #expect(name.count == 50)
  }
}

/// Asserts the constants against the RN values.
@Suite("StarterPackConstants")
struct ConstantsTests {
  @Test("the caps match RN")
  func caps() {
    #expect(StarterPackConstants.maxSize == 150)
    #expect(StarterPackConstants.minimumProfiles == 8)
    #expect(StarterPackConstants.maximumFeeds == 3)
    #expect(StarterPackConstants.writeChunkSize == 50)
    #expect(StarterPackConstants.maxNameLength == 50)
  }

  @Test("the page sizes match RN")
  func pageSizes() {
    #expect(StarterPackConstants.listMembersPageSize == 30)
    #expect(StarterPackConstants.listMembersAllPageSize == 50)
    #expect(StarterPackConstants.listMembersAllPageCap == 6)
    #expect(StarterPackConstants.actorStarterPacksPageSize == 10)
    #expect(StarterPackConstants.searchPageSize == 25)
  }

  @Test("the display thresholds match RN")
  func thresholds() {
    #expect(StarterPackConstants.joinedCountDisplayThreshold == 25)
    #expect(StarterPackConstants.landingSampleThreshold == 8)
    #expect(StarterPackConstants.joinedThisWeek == 560_000)
    #expect(StarterPackConstants.wizardFooterAvatarCount == 6)
  }

  @Test("the staleness budgets match the RN queries")
  func staleTimes() {
    #expect(StarterPackStale.packView == 300)
    #expect(StarterPackStale.search == 300)
    #expect(StarterPackStale.listMembers == 60)
  }
}
