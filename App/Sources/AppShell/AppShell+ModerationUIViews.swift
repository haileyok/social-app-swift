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

   The returned type is opaque on purpose. The surface switch inside the screen
   passes values whose types live in `ModerationUILogic` and `Lexicons`; an
   opaque result keeps those out of this module's interface, so the App shell
   needs no dependency on either package and cannot accidentally depend on a
   moderation fixture type.

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
        ModerationUISurfaces.moderationScreen()
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

#Preview {
  ModerationUISurfaces.moderationScreen(theme: .system)
}
