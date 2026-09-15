import Foundation
import Moderation
import Testing

@testable import VideoFeedLogic

/// One row of the autoplay gating table: settings plus moderation in, decision out.
///
/// Declared at file scope rather than inside the suite so the manifest checker,
/// which attributes tests to the most recently seen type declaration, keeps
/// attributing this suite's `@Test`s to the suite itself.
struct AutoplayRow: Sendable, CustomStringConvertible {
  let name: String
  let autoplayDisabled: Bool
  let isWithinMessage: Bool
  let moderation: ModerationDecision?
  let expected: VideoAutoplayDecision

  var description: String { name }
}

/// The autoplay policy: preference + moderation gating, as a decision table.
///
/// Ports `autoplay = !autoplayDisabled && !isWithinMessage` in
/// `VideoEmbedInner/VideoEmbedInnerNative.tsx`, the `beginMuted` expression
/// beside it, and the `contentView`/`contentMedia` blur pause in
/// `updateVideoState` (`src/screens/VideoFeed/index.tsx`).
@Suite("Video autoplay policy")
struct VideoAutoplayTests {
  // MARK: - Decision table

  static let table: [AutoplayRow] = [
    AutoplayRow(
      name: "default settings autoplay",
      autoplayDisabled: false,
      isWithinMessage: false,
      moderation: nil,
      expected: .play),
    AutoplayRow(
      name: "autoplay disabled plays on demand",
      autoplayDisabled: true,
      isWithinMessage: false,
      moderation: nil,
      expected: .playOnDemand),
    AutoplayRow(
      name: "a message thread suppresses playback",
      autoplayDisabled: false,
      isWithinMessage: true,
      moderation: nil,
      expected: .suppressedInMessage),
    AutoplayRow(
      name: "a message thread with autoplay disabled is still suppressed",
      autoplayDisabled: true,
      isWithinMessage: true,
      moderation: nil,
      expected: .suppressedInMessage),
    AutoplayRow(
      name: "a contentView blur blocks playback",
      autoplayDisabled: false,
      isWithinMessage: false,
      moderation: Fixtures.contentViewBlurDecision(),
      expected: .blockedByModeration),
    AutoplayRow(
      name: "a contentMedia blur blocks playback",
      autoplayDisabled: false,
      isWithinMessage: false,
      moderation: Fixtures.mediaBlurDecision(),
      expected: .blockedByModeration),
    AutoplayRow(
      name: "moderation wins over the autoplay preference",
      autoplayDisabled: true,
      isWithinMessage: false,
      moderation: Fixtures.mediaBlurDecision(),
      expected: .blockedByModeration),
    AutoplayRow(
      name: "moderation wins over the message-thread suppression",
      autoplayDisabled: false,
      isWithinMessage: true,
      moderation: Fixtures.mediaBlurDecision(),
      expected: .blockedByModeration),
    AutoplayRow(
      name: "an inform-only label does not block",
      autoplayDisabled: false,
      isWithinMessage: false,
      moderation: Fixtures.informingDecision(),
      expected: .play),
  ]

  @Test("the autoplay gating table", arguments: table)
  func gatingTable(row: AutoplayRow) {
    let decision = videoAutoplayDecision(
      settings: VideoAutoplaySettings(
        autoplayDisabled: row.autoplayDisabled,
        isWithinMessage: row.isWithinMessage),
      moderation: row.moderation)
    #expect(decision == row.expected, "row: \(row.name)")
  }

  @Test("a decision's derived flags agree with its case")
  func decisionFlags() {
    #expect(VideoAutoplayDecision.play.autoplays)
    #expect(VideoAutoplayDecision.play.isPlayable)
    #expect(!VideoAutoplayDecision.play.requiresTapToPlay)
    #expect(!VideoAutoplayDecision.play.isModerationBlocked)

    #expect(!VideoAutoplayDecision.playOnDemand.autoplays)
    #expect(VideoAutoplayDecision.playOnDemand.isPlayable)
    #expect(VideoAutoplayDecision.playOnDemand.requiresTapToPlay)

    #expect(!VideoAutoplayDecision.suppressedInMessage.isPlayable)
    #expect(!VideoAutoplayDecision.blockedByModeration.isPlayable)
    #expect(VideoAutoplayDecision.blockedByModeration.isModerationBlocked)
  }

  // MARK: - Blur detection

  @Test("no moderation decision is never a blur")
  func noDecisionIsNotBlurred() {
    #expect(!isBlurredByModeration(nil))
  }

  @Test("a decision with no causes is not blurred")
  func emptyDecisionIsNotBlurred() {
    #expect(!isBlurredByModeration(ModerationDecision()))
  }

  @Test("either the contentView or the contentMedia blur counts")
  func eitherBlurCounts() {
    #expect(isBlurredByModeration(Fixtures.contentViewBlurDecision()))
    #expect(isBlurredByModeration(Fixtures.mediaBlurDecision()))
    #expect(!isBlurredByModeration(Fixtures.informingDecision()))
  }

  @Test("an alert-only label is not a blur")
  func alertOnlyIsNotBlurred() {
    var decision = ModerationDecision()
    decision.setDid("did:plc:alice")
    decision.causes.append(
      ModerationCause(
        type: .label,
        source: .user,
        priority: 8,
        label: Label(src: "did:plc:labeler", uri: "at://x", val: "spam"),
        target: .content,
        setting: .warn,
        behavior: ModerationBehavior(contentView: .alert)))
    #expect(!isBlurredByModeration(decision))
  }

  // MARK: - Mute

  @Test("a GIF always begins muted")
  func gifBeginsMuted() {
    // Even with autoplay disabled and the viewer unmuted, a GIF has no audio.
    #expect(
      videoBeginMuted(
        settings: VideoAutoplaySettings(autoplayDisabled: true, muted: false), isGif: true))
  }

  @Test("with autoplay on, the viewer's mute state is honoured")
  func autoplayHonoursMute() {
    #expect(
      videoBeginMuted(
        settings: VideoAutoplaySettings(autoplayDisabled: false, muted: true), isGif: false))
    #expect(
      !videoBeginMuted(
        settings: VideoAutoplaySettings(autoplayDisabled: false, muted: false), isGif: false))
  }

  @Test("with autoplay disabled, a video begins unmuted")
  func noAutoplayBeginsUnmuted() {
    // RN: `beginMuted={isGif || (autoplayDisabled ? false : muted)}`. When the
    // viewer had to tap, they expect sound even though the global mute is on.
    #expect(
      !videoBeginMuted(
        settings: VideoAutoplaySettings(autoplayDisabled: true, muted: true), isGif: false))
  }

  @Test("the default settings are autoplay-on and muted")
  func defaultSettings() {
    let settings = VideoAutoplaySettings()
    #expect(!settings.autoplayDisabled)
    #expect(settings.muted)
    #expect(!settings.isWithinMessage)
    #expect(
      videoAutoplayDecision(settings: settings, moderation: nil) == .play)
  }
}
