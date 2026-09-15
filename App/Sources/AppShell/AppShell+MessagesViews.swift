import DesignSystem
import DesignSystemCore
import DesignTokens
import SwiftUI

// Re-exported so the app and its test targets reach the messages surfaces
// through `import AppShell` alone, the same way they reach the login and shell
// surfaces. XCUITest bundles are built by the project rather than by a package,
// so they link only the AppShell product; the `@_exported` form is what makes a
// second `import MessagesViews` unnecessary.
@_exported import MessagesViews

/**
 The messages entry point for the app shell.

 Mirrors `AppShell+Login.swift` and `AppShell+Components.swift`: the hook lives in
 its own file so the shell agent's work on the root view and this surface do not
 conflict. Nothing here is referenced by the root view by default - the messages
 screens are reachable from a tab toolbar, which keeps the 5-tab root and its
 smoke tests untouched while the real screens are mountable.

 ```swift
 // A tab's toolbar, alongside the login and gallery links:
 MessagesDebugButton()
 ```
 */
public enum MessagesSurfaces {
  /**
   The inbox screen, over the scripted fixture conversation.

   This is the fixture surface: it renders the production `InboxScreen` through
   the production `InboxViewModel`, backed by `MessagesFixtureSurfaces`' scripted
   client instead of a session. That is deliberate - the point of the fixture is
   that the inbox row treatment (avatar, name, preview, unread badge, muted
   indicator) is visible and drivable before the session and chat transport are
   wired, and it renders through exactly the same views the live path uses.

   - Parameter theme: the resolved theme to render under. Passing it explicitly
     lets a caller (a screenshot loop, a preview) pin light/dark without relying
     on the environment above the surface.
   */
  @MainActor
  public static func inboxScreen(theme: DesignTokens.Theme) -> some View {
    NavigationStack {
      MessagesFixtureSurfaces.inboxScreen()
        .navigationTitle(MessagesCopy.surfacesTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
    .theme(theme)
    .accessibilityIdentifier(MessagesAccessibility.inbox)
  }

  /**
   The scripted conversation screen, over the same fixture.

   Split from ``inboxScreen(theme:)`` so a caller can mount the conversation
   directly (the fixture conversation carries a pending message, a failed send
   with retry and a reaction, which are the treatments worth looking at).
   */
  @MainActor
  public static func conversationScreen(theme: DesignTokens.Theme) -> some View {
    NavigationStack {
      MessagesFixtureSurfaces.conversationScreen()
    }
    .theme(theme)
    .accessibilityIdentifier(MessagesAccessibility.conversation)
  }
}

/// A tab toolbar button that presents the messages fixture gallery.
public struct MessagesDebugButton: View {
  @State private var isPresented = false

  public init() {}

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "bubble.left.and.bubble.right")
    }
    .accessibilityLabel("Chat")
    .accessibilityIdentifier("app.debug.messages")
    .sheet(isPresented: $isPresented) {
      MessagesDebugSheet()
    }
  }
}

/// The presented fixture gallery, wrapped in its own navigation stack.
public struct MessagesDebugSheet: View {
  @AppStorage("alfTheme") private var themePreference = ThemePreference.system.rawValue

  @Environment(\.dismiss) private var dismiss

  public init() {}

  public var body: some View {
    NavigationStack {
      MessagesFixtureGallery()
        .navigationTitle(MessagesCopy.surfacesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .theme(ThemePreference(rawValue: themePreference) ?? .system)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close") { dismiss() }
              .accessibilityIdentifier("app.messages.close")
          }
        }
    }
    .accessibilityIdentifier("app.messages")
  }
}

#Preview {
  MessagesDebugSheet()
}
