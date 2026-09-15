import DesignSystem
import DesignTokens
import Moderation
import ModerationUILogic
import SwiftUI
import UIComponents

/// The data the content-label screen renders.
///
/// The screen is a pure function of this model: the app derives it (labeler
/// subscriptions + label definitions + the viewer's preferences) and hands it
/// down. Keeping it a value type rather than view state means a preference
/// change round-trips through the caller and the screen never disagrees with
/// what the store holds.
public struct ContentLabelsModel: Equatable, Sendable {
  /// The global (app-defined) adult content rows, shown only while adult content
  /// is on.
  public var globalRows: [ContentLabelRow]
  /// One section per labeler with configurable labels.
  public var sections: [ContentLabelSection]
  /// Whether `globalRows` render at all.
  public var showsGlobalRows: Bool
  /// The viewer's adult-content switch.
  public var isAdultContentEnabled: Bool

  public init(
    globalRows: [ContentLabelRow] = [],
    sections: [ContentLabelSection] = [],
    showsGlobalRows: Bool = false,
    isAdultContentEnabled: Bool = false
  ) {
    self.globalRows = globalRows
    self.sections = sections
    self.showsGlobalRows = showsGlobalRows
    self.isAdultContentEnabled = isAdultContentEnabled
  }

  /// Builds the model from the parts the app already has.
  ///
  /// Every list here is produced by ``ContentLabels``; this initializer only
  /// assembles, so the screen and the tests share the derivation.
  public static func build(
    labelers: [(did: String, title: String, handle: String?, isSubscribed: Bool, labelValues: [String], customDefinitions: [LabelValueDefinition])],
    prefs: ModerationPrefs
  ) -> ContentLabelsModel {
    let sections = labelers.map { labeler in
      ContentLabelSection(
        labelerDid: labeler.did,
        title: labeler.title,
        handle: labeler.handle,
        isSubscribed: labeler.isSubscribed,
        customDefinitions: labeler.customDefinitions,
        rows: ContentLabels.rows(
          labelerDid: labeler.did,
          labelValues: labeler.labelValues,
          customDefinitions: labeler.customDefinitions,
          isSubscribed: labeler.isSubscribed,
          prefs: prefs))
    }
    return ContentLabelsModel(
      globalRows: ContentLabels.globalRows(prefs: prefs),
      sections: sections,
      showsGlobalRows: ContentLabels.showsGlobalRows(prefs: prefs),
      isAdultContentEnabled: prefs.adultContentEnabled)
  }
}

/// The content and media labels screen.
///
/// Per-labeler sections of label toggle rows, with the global adult content rows
/// above them. Everything about which rows exist and what each row's adjustable
/// value is comes from ``ContentLabels``; this view decides only how to draw a
/// row and where the notices go.
///
/// Ported from `screens/Profile/Sections/Labels.tsx` (the per-labeler list) and
/// the global label block in `screens/Moderation/index.tsx`; the row itself is
/// `components/moderation/LabelPreference.tsx`.
public struct ContentLabelsScreen: View {
  private let model: ContentLabelsModel
  private let onSetPreference: (ContentLabelRow, LabelPreference) -> Void
  private let onSetAdultContent: (Bool) -> Void

  /// Creates the content-label screen.
  ///
  /// - Parameters:
  ///   - model: the derived rows.
  ///   - onSetPreference: called with a row and its new value.
  ///   - onSetAdultContent: called when the adult content switch changes.
  public init(
    model: ContentLabelsModel = ContentLabelsModel(),
    onSetPreference: @escaping (ContentLabelRow, LabelPreference) -> Void = { _, _ in },
    onSetAdultContent: @escaping (Bool) -> Void = { _ in }
  ) {
    self.model = model
    self.onSetPreference = onSetPreference
    self.onSetAdultContent = onSetAdultContent
  }

  @Environment(\.alfTheme) private var theme

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        header
        adultContentSection
        globalLabelsSection

        ForEach(model.sections, id: \.labelerDid) { section in
          labelerSection(section)
        }
      }
      .padding(.xl)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .background(theme.atomColors.bg)
    .accessibilityIdentifier(ModerationAccessibility.contentLabelsScreen)
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      AlfText(
        ModerationCopy.contentLabelsTitle, scale: .xxl, weight: Scales.FontWeight.bold)
      AlfText(
        ModerationCopy.contentLabelsDescription, scale: .sm,
        color: theme.atomColors.textContrastMedium)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var adultContentSection: some View {
    ModerationToggleRow(
      title: ModerationCopy.globalLabelsHeading,
      subtitle: ModerationCopy.adultContentOffNotice,
      isOn: Binding(
        get: { model.isAdultContentEnabled },
        set: { onSetAdultContent($0) }))
  }

  @ViewBuilder
  private var globalLabelsSection: some View {
    if model.showsGlobalRows && !model.globalRows.isEmpty {
      ModerationSection {
        VStack(spacing: 0) {
          ForEach(model.globalRows, id: \.identifier) { row in
            labelRow(row, labelerDid: row.labelerDid ?? "app.bsky")
            ModerationDivider()
          }
        }
      }
    }
  }

  private func labelerSection(_ section: ContentLabelSection) -> some View {
    ModerationSection(
      title: ModerationCopy.labelerHeading(section.title),
      description: section.handle.map { "@\($0)" }
    ) {
      VStack(spacing: 0) {
        if !section.isSubscribed {
          ModerationNotice(message: ModerationCopy.notSubscribedNotice)
            .padding(.bottom, Spacing.xs)
        }
        ForEach(section.rows, id: \.identifier) { row in
          labelRow(row, labelerDid: section.labelerDid)
        }
      }
    }
  }

  // MARK: - Rows

  @ViewBuilder
  private func labelRow(_ row: ContentLabelRow, labelerDid: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .center, spacing: Spacing.md) {
        AlfText(
          ModerationCopy.labelTitle(row.identifier), scale: .md,
          weight: Scales.FontWeight.semiBold)
          .frame(maxWidth: .infinity, alignment: .leading)

        labelControl(row, labelerDid: labelerDid)
      }
      .padding(.md, .horizontal)
      .padding(.sm, .vertical)

      labelNotice(row)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      ModerationAccessibility.contentLabelRow(labelerDid, row.identifier))
  }

  /// The row's trailing control: the toggle group, or the static value when the
  /// row cannot be configured.
  ///
  /// Kept out of ``labelRow(_:labelerDid:)`` because the generic radio group plus
  /// the enclosing conditional is more than the type checker will solve in one
  /// expression.
  @ViewBuilder
  private func labelControl(_ row: ContentLabelRow, labelerDid: String) -> some View {
    if row.showsStaticValue {
      // A row that cannot be configured still shows its current value, the way
      // the RN component renders a static label instead of the group.
      AlfText(
        ModerationCopy.optionLabel(row.preference.rawValue), scale: .xs,
        color: theme.atomColors.textContrastMedium)
    } else {
      ModerationRadioGroup(
        options: row.options,
        label: { option in ModerationCopy.optionLabel(option.rawValue) },
        selection: preferenceBinding(row),
        identifier: { option in
          ModerationAccessibility.contentLabelOption(
            labelerDid, row.identifier, option.rawValue)
        }
      )
      .frame(maxWidth: 240)
    }
  }

  private func preferenceBinding(_ row: ContentLabelRow) -> Binding<LabelPreference> {
    Binding(
      get: { row.preference },
      set: { onSetPreference(row, $0) })
  }

  /// The explanation under a row that cannot be changed, when there is one.
  @ViewBuilder
  private func labelNotice(_ row: ContentLabelRow) -> some View {
    if row.adultDisabled {
      ModerationNotice(message: ModerationCopy.adultDisabledNotice)
        .padding(.horizontal, .md)
        .padding(.bottom, Spacing.xs)
    } else if row.showsStaticValue {
      ModerationNotice(message: ModerationCopy.staticValueNotice)
        .padding(.horizontal, .md)
        .padding(.bottom, Spacing.xs)
    }
  }
}

#Preview {
  ContentLabelsScreen(model: ModerationFixtures.contentLabelsModel())
}
