import DesignSystem
import DesignSystemCore
import SwiftUI

/// Every moderation surface on one screen, backed by ``ModerationFixtures``.
///
/// Ported from nothing: this is the debugging/screenshot mount. A segmented
/// picker selects which surface renders, so one screenshot pass covers the
/// content-label screen, the muted-words editor, both account lists, the labeler
/// directory and the report dialog.
///
/// The switch over surfaces lives here rather than in the App shell on purpose:
/// each case passes fixture values whose types come from `ModerationUILogic` and
/// `Lexicons`, and keeping that work inside this package means the App layer
/// names no type outside it. The App hook returns
/// ``ModerationUISurface/fixtureView`` (an opaque `some View`) instead.
public struct ModerationFixtureScreen: View {
  private let themePreference: ThemePreference

  @State private var surface: ModerationUISurface = .contentLabels

  /// Creates the fixture screen.
  ///
  /// - Parameter theme: the theme preference to resolve against.
  public init(theme: ThemePreference = .system) {
    self.themePreference = theme
  }

  public var body: some View {
    VStack(spacing: 0) {
      Picker("Surface", selection: $surface) {
        ForEach(ModerationUISurface.allCases) { item in
          Text(item.title).tag(item)
        }
      }
      .pickerStyle(.segmented)
      .padding(.md)

      surface.fixtureView
    }
    // Each surface paints its own themed background; this container only stacks
    // the picker above it.
    .theme(themePreference)
    .accessibilityIdentifier(ModerationAccessibility.surface(surface.rawValue))
  }
}

/// The moderation surface being previewed.
public enum ModerationUISurface: String, CaseIterable, Identifiable, Sendable {
  case contentLabels
  case mutedWords
  case blockedAccounts
  case mutedAccounts
  case labelers
  case report

  public var id: String { rawValue }

  /// The picker's label for this surface.
  public var title: String {
    switch self {
    case .contentLabels: return "Labels"
    case .mutedWords: return "Muted words"
    case .blockedAccounts: return "Blocked"
    case .mutedAccounts: return "Muted"
    case .labelers: return "Labelers"
    case .report: return "Report"
    }
  }

  /// The fixture view for this surface.
  ///
  /// Opaque so a caller outside this package can mount a surface without naming
  /// the fixture types it is built from.
  @ViewBuilder
  public var fixtureView: some View {
    switch self {
    case .contentLabels:
      ContentLabelsScreen(model: ModerationFixtures.contentLabelsModel())
    case .mutedWords:
      MutedWordsScreen(rows: ModerationFixtures.mutedWordRows())
    case .blockedAccounts:
      BlockedMutedAccountsScreen(
        kind: AccountListKind.blocked, items: ModerationFixtures.profileViews(), hasMore: true)
    case .mutedAccounts:
      BlockedMutedAccountsScreen(
        kind: AccountListKind.muted, items: ModerationFixtures.profileViews(count: 2))
    case .labelers:
      LabelerServicesScreen(
        subscribed: ModerationFixtures.labelerRows(subscribed: true),
        available: ModerationFixtures.labelerRows(subscribed: false, startIndex: 10),
        unavailable: ModerationFixtures.labelerRows(subscribed: true, startIndex: 20, count: 1))
    case .report:
      ReportDialogSheet(
        subject: ModerationFixtures.reportSubject(),
        labelers: ModerationFixtures.reportLabelers())
    }
  }
}

#Preview {
  ModerationFixtureScreen(theme: .system)
}
