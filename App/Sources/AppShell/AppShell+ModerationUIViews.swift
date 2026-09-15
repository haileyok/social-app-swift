import DesignSystem
import DesignSystemCore
import ModerationUIViews
import SwiftUI

/**
 The moderation surfaces, mounted for the debug toolbar and the CI screenshot
 loop.

 Mirrors `AppShell+Login.swift` and `AppShell+Components.swift`: the hook lives in
 its own file so the shell agent's work on the root view and this debug surface do
 not conflict. Nothing here is referenced by the root view by default, so the
 5-tab shell and its smoke tests stay untouched while the moderation screens
 become reachable.

 ```swift
 // A tab's toolbar, alongside the token-gallery and login links:
 ModerationDebugButton()
 ```
 */
public enum ModerationUISurfaces {
  /**
   The moderation fixture screen for a theme.

   This is the single entry point the debug toolbar and the screenshot loop use:
   every moderation surface is reachable from it with deterministic fixture data,
   so a render never depends on a live session or a network read.

   - Parameter theme: the theme preference to resolve against. Passed in rather
     than read from storage so a caller can mount the fixture under a specific
     theme (which is what the screenshot loop does).
   */
  public static func moderationScreen(theme: ThemePreference = .system) -> some View {
    ModerationFixtureScreen(theme: theme)
  }
}

/// The debug toolbar button that presents the moderation fixture screen.
public struct ModerationDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "hand.raised")
    }
    .accessibilityLabel("Moderation")
    .accessibilityIdentifier(ModerationAccessibility.surface("debugButton"))
    .sheet(isPresented: $isPresented) {
      NavigationStack {
        ModerationFixtureScreen()
          .navigationTitle("Moderation")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("Close") { isPresented = false }
            }
          }
      }
    }
  }
}

/**
 Every moderation surface on one screen, backed by ``ModerationFixtures``.

 A segmented picker selects which surface renders, so one screenshot pass covers
 the content-label screen, the muted-words editor, both account lists, the labeler
 directory and the report dialog. The picker exists so the surfaces can be
 reviewed without navigating an app that has no moderation settings entry point
 yet.
 */
public struct ModerationFixtureScreen: View {
  /// The moderation surface being previewed.
  public enum Surface: String, CaseIterable, Identifiable, Sendable {
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
  }

  private let themePreference: ThemePreference

  @State private var surface: Surface = .contentLabels

  /// Creates the fixture screen.
  ///
  /// - Parameter theme: the theme preference to resolve against.
  public init(theme: ThemePreference = .system) {
    self.themePreference = theme
  }

  public var body: some View {
    VStack(spacing: 0) {
      Picker("Surface", selection: $surface) {
        ForEach(Surface.allCases) { surface in
          Text(surface.title).tag(surface)
        }
      }
      .pickerStyle(.segmented)
      .padding(.md)

      content
    }
    // Each surface paints its own themed background; this container only stacks
    // the picker above it.
    .theme(themePreference)
    .accessibilityIdentifier(ModerationAccessibility.surface(surface.rawValue))
  }

  @ViewBuilder
  private var content: some View {
    switch surface {
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

/// The unresolvable background colour a fixture screen falls back to before the
/// theme modifier is applied.
///
/// A whole-screen `Color` needs a value outside the environment, and the fixture
/// screen renders before `.theme(_:)` takes effect for its own background. Clear
/// is the honest answer: the themed child views paint the surface.
enum DesignSystemThemeColors {
  static let shared = Resolved()
  struct Resolved { let bg = Color.clear }
}

#Preview {
  ModerationUISurfaces.moderationScreen(theme: .system)
}
