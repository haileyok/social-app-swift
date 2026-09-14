import Moderation
import Testing

@testable import UIComponentsCore

@Suite("Moderation surfaces")
struct ModerationSurfaceTests {
  @Test("An empty UI renders the content")
  func none() {
    #expect(moderationSurface(ModerationUI()) == .none)
    #expect(moderationSurface(nil) == .none)
  }

  @Test("A blur becomes a revealable mask, or a locked one when noOverride")
  func blur() {
    let cause = ModerationCause(type: .hidden, source: .user, priority: 1, downgraded: false)
    var ui = ModerationUI()
    ui.blurs = [cause]
    guard case .blur(let description, let allowOverride) = moderationSurface(ui) else {
      Issue.record("expected a blur")
      return
    }
    #expect(allowOverride == true)
    #expect(description.name == "Post Hidden by You")

    ui.noOverride = true
    guard case .blur(_, let lockedOverride) = moderationSurface(ui) else {
      Issue.record("expected a blur")
      return
    }
    #expect(lockedOverride == false)
  }

  @Test("A filter removes the content")
  func filter() {
    var ui = ModerationUI()
    ui.filters = [ModerationCause(type: .muteWord, source: .user, priority: 1)]
    guard case .filter(let description) = moderationSurface(ui) else {
      Issue.record("expected a filter")
      return
    }
    #expect(description.name == "Post Hidden by Muted Word")
    #expect(moderationSurface(ui).isVisible == false)
  }

  @Test("interpretFilterAsBlur turns a filter into a revealable blur")
  func filterAsBlur() {
    var ui = ModerationUI()
    ui.filters = [ModerationCause(type: .muted, source: .user, priority: 1)]
    guard case .blur(_, let allowOverride) = moderationSurface(ui, interpretFilterAsBlur: true) else {
      Issue.record("expected a blur")
      return
    }
    #expect(allowOverride == true)
  }

  @Test("A blur takes precedence over a filter")
  func blurBeatsFilter() {
    var ui = ModerationUI()
    ui.blurs = [ModerationCause(type: .hidden, source: .user, priority: 1)]
    ui.filters = [ModerationCause(type: .muted, source: .user, priority: 2)]
    if case .blur = moderationSurface(ui) {} else {
      Issue.record("expected the blur to win")
    }
  }

  @Test("Block causes describe themselves")
  func descriptions() {
    let blocking = ModerationCause(type: .blocking, source: .user, priority: 1)
    #expect(ModerationCauseDescription.describe(blocking).name == "User Blocked")

    let list = ListViewBasic(uri: "at://l", name: "Spam")
    let viaList = ModerationCause(type: .blocking, source: .list(list), priority: 1)
    #expect(ModerationCauseDescription.describe(viaList).source == "Spam")

    let blockedBy = ModerationCause(type: .blockedBy, source: .user, priority: 1)
    #expect(ModerationCauseDescription.describe(blockedBy).name == "User Blocking You")

    let none = ModerationCauseDescription.describe(nil)
    #expect(none.name == "Content Warning")
  }

  @Test("A label cause falls back to its identifier")
  func labelDescription() {
    let label = Label(src: "did:plc:labeler", uri: "at://x", val: "graphic-media")
    let definition = LabelValueDefinition(
      identifier: "graphic-media",
      severity: .none,
      blurs: .media,
      defaultSetting: .warn,
      flags: [],
      behaviors: LabelTargetBehaviors(),
      definedBy: "did:plc:labeler")
    let cause = ModerationCause(
      type: .label, source: .labeler(did: "did:plc:labeler"), priority: 1,
      label: label, labelDef: definition)
    let description = ModerationCauseDescription.describe(cause)
    #expect(description.description.contains("graphic-media"))
    #expect(description.source == "did:plc:labeler")
  }

  @Test("The four feed-item contexts project independently")
  func feedItemProjection() {
    // A media-only blur must not blur the content surface.
    let definition = LabelValueDefinition(
      identifier: "graphic-media",
      severity: .none,
      blurs: .media,
      defaultSetting: .warn,
      flags: [],
      behaviors: LabelTargetBehaviors(
        content: ModerationBehavior(contentList: .blur, contentView: .blur, contentMedia: .blur)),
      definedBy: "did:plc:labeler")
    let cause = ModerationCause(
      type: .label, source: .labeler(did: "did:plc:labeler"), priority: 1,
      labelDef: definition, target: .content, behavior: definition.behaviors[LabelTarget.content])

    var decision = ModerationDecision()
    decision.causes = [cause]
    let projected = FeedItemModeration.project(decision)

    // Both content and media blur, but the avatar and banner do not.
    if case .blur = projected.content {} else { Issue.record("content should blur") }
    if case .blur = projected.media {} else { Issue.record("media should blur") }
    #expect(projected.avatar == .none)
    #expect(projected.banner == .none)
  }

  @Test("An empty decision projects to all-none")
  func emptyProjection() {
    let projected = FeedItemModeration.project(ModerationDecision())
    #expect(projected.content == .none)
    #expect(projected.media == .none)
    #expect(projected.avatar == .none)
    #expect(projected.banner == .none)
  }
}
