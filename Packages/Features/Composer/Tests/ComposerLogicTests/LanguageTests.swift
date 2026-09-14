import Foundation
import Testing

@testable import ComposerLogic

/// Post-language selection.
///
/// Ported from the language handling in `select-language/PostLanguageSelect.tsx`,
/// `SuggestedLanguage.tsx`, and the `langs.slice(0, 3)` in `lib/api/index.ts`.
@Suite("Languages")
struct LanguageTests {

  @Test("a preference string splits on commas")
  func preferenceStringSplits() {
    let selection = LanguageSelection(preferenceString: "en,pt-BR,ja")
    #expect(selection.codes == ["en", "pt-BR", "ja"])
    #expect(selection.mode == .automatic)
  }

  @Test("blank and repeated separators are dropped")
  func blankEntriesDropped() {
    let selection = LanguageSelection(preferenceString: "en,, ja ,")
    #expect(selection.codes == ["en", "ja"])
  }

  @Test("more than three languages are capped")
  func cappedAtThree() {
    let selection = LanguageSelection(preferenceString: "en,ja,fr,de")
    #expect(selection.codes == ["en", "ja", "fr"])
    #expect(selection.codes.count == ComposerConstants.maxLanguages)
  }

  @Test("an empty preference yields an empty selection")
  func emptyPreference() {
    #expect(LanguageSelection(preferenceString: "").isEmpty)
  }

  @Test("setting an empty list falls back to the primary language")
  func emptySetFallsBack() {
    var selection = LanguageSelection(preferenceString: "en")
    selection.set([], fallback: "de")
    #expect(selection.codes == ["de"])
    #expect(selection.mode == .manual)
  }

  @Test("an explicit set marks the selection manual")
  func explicitSetIsManual() {
    var selection = LanguageSelection(preferenceString: "en")
    selection.set(["fr"])
    #expect(selection.mode == .manual)
    #expect(selection.codes == ["fr"])
  }

  @Test("adding a language appends it and marks the selection manual")
  func addLanguage() {
    var selection = LanguageSelection(preferenceString: "en")
    let added = selection.add("ja")
    #expect(added)
    #expect(selection.codes == ["en", "ja"])
    #expect(selection.mode == .manual)
  }

  @Test("adding a duplicate is refused")
  func duplicateRefused() {
    var selection = LanguageSelection(preferenceString: "en")
    let added = selection.add("en")
    #expect(!added)
    #expect(selection.codes == ["en"])
  }

  @Test("adding a fourth language is refused")
  func fourthRefused() {
    var selection = LanguageSelection(preferenceString: "en,ja,fr")
    let added = selection.add("de")
    #expect(!added)
    #expect(selection.codes.count == 3)
  }

  @Test("removing a language marks the selection manual")
  func removeLanguage() {
    var selection = LanguageSelection(preferenceString: "en,ja")
    selection.remove("en")
    #expect(selection.codes == ["ja"])
    #expect(selection.mode == .manual)
  }

  @Test("adopting a reply target's languages replaces the list")
  func adoptReplyLanguages() {
    var selection = LanguageSelection(preferenceString: "en")
    selection.adopt(languagesOfReplyTarget: ["ja"])
    #expect(selection.codes == ["ja"])
  }

  @Test("adopting is a no-op when the target's languages are already selected")
  func adoptAlreadySelected() {
    var selection = LanguageSelection(preferenceString: "en")
    selection.adopt(languagesOfReplyTarget: ["en"])
    #expect(selection.codes == ["en"])
    #expect(selection.mode == .automatic)
  }

  @Test("plausible BCP-47 tags are accepted and junk is rejected")
  func plausibility() {
    #expect(PostLanguage("en").isPlausible)
    #expect(PostLanguage("pt-BR").isPlausible)
    #expect(PostLanguage("zh-Hans-CN").isPlausible)
    #expect(!PostLanguage("").isPlausible)
    #expect(!PostLanguage("e").isPlausible)
    #expect(!PostLanguage("not a tag").isPlausible)
  }
}

/// Self-labels.
///
/// Ported from `src/lib/moderation.ts` and the `labels` construction in
/// `lib/api/index.ts`.
@Suite("SelfLabels")
struct SelfLabelTests {

  @Test("the composer's label set matches the RN constants")
  func labelSet() {
    #expect(SelfLabels.adultContent == ["sexual", "nudity", "porn"])
    #expect(SelfLabels.other == ["graphic-media"])
    #expect(SelfLabels.all == ["sexual", "nudity", "porn", "graphic-media"])
  }

  @Test("the label set is recognised")
  func recognised() {
    #expect(SelfLabels.isComposerLabel("sexual"))
    #expect(SelfLabels.isComposerLabel("graphic-media"))
    #expect(!SelfLabels.isComposerLabel("spam"))
  }

  @Test("inserting a duplicate label is refused")
  func duplicateRefused() {
    var set = SelfLabelSet()
    set.insert("sexual")
    set.insert("sexual")
    #expect(set.values == ["sexual"])
  }

  @Test("an empty set produces no record value")
  func emptySetNoRecord() {
    #expect(SelfLabelSet().recordValue == nil)
  }

  @Test("a populated set produces the selfLabels shape")
  func populatedSetRecord() {
    let set = SelfLabelSet(values: ["sexual", "graphic-media"])
    #expect(set.recordValue?.values.map(\.val) == ["sexual", "graphic-media"])
  }
}
