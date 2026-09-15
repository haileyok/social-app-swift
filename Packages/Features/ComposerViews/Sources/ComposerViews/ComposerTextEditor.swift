#if canImport(SwiftUI)
import ComposerLogic
import DesignSystem
import DesignTokens
import SwiftUI

/// The composer's text editor.
///
/// The counterpart of the RN `TextInput` (`view/com/composer/text-input/`): a
/// growing multiline field bound to the active post's rich text, with a hint
/// line beneath it that reports what facet detection found. The facets
/// themselves are the logic layer's; this view only *shows* that links and
/// mentions were recognised, which is the feedback the RN editor gives by
/// styling the ranges in place.
///
/// The field is bound (rather than `defaultValue`) because the reducer owns the
/// post's rich text and the counter, the publish gate and the draft saver all
/// have to see every keystroke. The AGENTS.md `defaultValue` guidance is about
/// uncontrolled inputs on the old architecture; here there is no other source of
/// truth for the text.
struct ComposerTextEditor: View {
  /// The active post's rich text, as the reducer holds it.
  @Binding var richText: RichTextValue
  /// The text the editor shows before the user types.
  let placeholder: String
  /// The accessibility identifier, so the UI test can address the field.
  let identifier: String
  /// Focus binding, so the screen can move focus between posts.
  @FocusState.Binding var isFocused: Bool

  @Environment(\.alfTheme) private var theme
  @Environment(\.alfFontFamily) private var family
  @Environment(\.alfFontScale) private var fontScale

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      TextField(placeholder, text: binding, axis: .vertical)
        .font(TypeScale.lg.font(fontScale: fontScale, family: family, weight: Scales.FontWeight.normal))
        .foregroundStyle(theme.atomColors.text)
        .tint(theme.colors.primary500)
        .lineLimit(3...12)
        .textInputAutocapitalization(.sentences)
        .focused($isFocused)
        .accessibilityLabel(ComposerCopy.textPlaceholder)
        .accessibilityIdentifier(identifier)

      facetHint
    }
  }

  /// A plain `Binding<String>` over the rich text.
  ///
  /// Writing the text resets the facets, because they belong to the old
  /// string's byte offsets. Detection runs on ``ComposerTextEditor/detected``
  /// below, which is what the hint reads.
  private var binding: Binding<String> {
    Binding(
      get: { richText.text },
      set: { newValue in
        guard newValue != richText.text else { return }
        richText = RichTextValue(text: newValue).detectingFacetsWithoutResolution()
      })
  }

  /// What facet detection found, summarised for the hint line.
  @ViewBuilder
  private var facetHint: some View {
    let uris = ComposerReducer.detectLinkUris(in: richText)
    let mentionCount = mentionFacetCount
    if !uris.isEmpty || mentionCount > 0 {
      HStack(spacing: Spacing.xs) {
        if uris.postUris.count + uris.externalUris.count > 0 {
          facetChip(
            "\(uris.postUris.count + uris.externalUris.count) link"
              + (uris.postUris.count + uris.externalUris.count == 1 ? "" : "s"),
            systemImage: "link")
        }
        if mentionCount > 0 {
          facetChip(
            "\(mentionCount) mention" + (mentionCount == 1 ? "" : "s"),
            systemImage: "at")
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(ComposerAccessibility.validationMessage + ".facets")
    }
  }

  /// The number of distinct mention facets in the text.
  private var mentionFacetCount: Int {
    var handles = Set<String>()
    for facet in richText.facets ?? [] {
      for feature in facet.features {
        if case .mention(let did) = feature { handles.insert(did) }
      }
    }
    return handles.count
  }

  private func facetChip(_ label: String, systemImage: String) -> some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: systemImage)
        .font(.caption2)
      AlfText(label, scale: .xs, color: theme.atomColors.textContrastMedium)
    }
    .padding(.horizontal, Spacing.xs)
    .padding(.vertical, Spacing.xxs)
    .background(theme.atomColors.bgContrast50)
    .cornerRadius(.full)
  }
}

/// The grapheme counter.
///
/// Ported from `char-progress/CharProgress.tsx`. The number is the *shortened*
/// grapheme length - what the publish limit actually applies to - which is why
/// it comes from `PostDraft.shortenedGraphemeLength` rather than from the raw
/// string.
struct ComposerCharacterCounter: View {
  /// The post being counted.
  let post: PostDraft

  @Environment(\.alfTheme) private var theme

  var body: some View {
    let remaining = ComposerConstants.maxGraphemeLength - post.shortenedGraphemeLength
    AlfText(
      "\(remaining)",
      scale: .sm,
      weight: remaining <= 20 ? Scales.FontWeight.semiBold : Scales.FontWeight.normal,
      color: color(remaining: remaining)
    )
    .accessibilityIdentifier(ComposerAccessibility.characterCounter)
    .accessibilityLabel("\(ComposerCopy.characterCountLabel): \(remaining)")
  }

  private func color(remaining: Int) -> Color {
    if remaining < 0 { return theme.colors.negative500 }
    if remaining <= 20 { return theme.colors.negative400 }
    return theme.atomColors.textContrastMedium
  }
}
#endif
