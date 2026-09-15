import DesignSystem
import DesignSystemCore
import SwiftUI

import NotificationsLogic

/**
 The notifications surface, as the app shell mounts it.

 One entry point, mirroring `AppShell`'s other hooks (`LoginDebugSheet`,
 `ComponentGalleryScreen`): the shell adds a dependency line and a debug control,
 and this file stays the only place that knows how to present the notifications
 screen.

 The surface renders ``NotificationsFixtures`` until the shell has a session to
 hand it real rows, so it can be mounted and screenshot today. The unread
 badge, the filter and the empty state all exercise the same code path the real
 feed will.
 */
public enum NotificationsSurfaces {
  /**
   The notifications list, ready to mount.

   ```swift
   NotificationsSurfaces.notificationsScreen(theme: .dark)
   ```

   - Parameters:
     - theme: the theme the surface renders in. `.system` follows the OS.
     - rows: the rows to draw. Defaults to the fixture set; pass `[]` with
       `isInitialLoading: true` to see the loading state, or `rows: []` alone for
       the empty state.
     - isInitialLoading: true while the first page is in flight.
   */
  public static func notificationsScreen(
    theme: ThemePreference = .system,
    rows: [FeedNotification] = NotificationsFixtures.rows,
    isInitialLoading: Bool = false
  ) -> some View {
    NotificationsSurface(
      theme: theme, rows: rows, isInitialLoading: isInitialLoading)
  }

  /**
   The fixture surface: the screen in a `NavigationStack` with its title, the
   shape the shell mounts behind a debug control.
   */
  public static func fixtureSurface(
    theme: ThemePreference = .system,
    rows: [FeedNotification] = NotificationsFixtures.rows,
    isInitialLoading: Bool = false
  ) -> some View {
    NotificationsSurface(
      theme: theme, rows: rows, isInitialLoading: isInitialLoading, showsTitle: true)
  }
}

/**
 The concrete surface view, kept private so the public entry points are the two
 functions above and the theme handling lives in one place.
 */
private struct NotificationsSurface: View {
  let theme: ThemePreference
  let rows: [FeedNotification]
  let isInitialLoading: Bool
  var showsTitle = false

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Group {
      if showsTitle {
        NavigationStack {
          NotificationsScreen(rows: rows, isInitialLoading: isInitialLoading)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
        }
      } else {
        NotificationsScreen(rows: rows, isInitialLoading: isInitialLoading)
      }
    }
    .theme(theme)
    .accessibilityIdentifier(NotificationsAccessibility.screen)
  }
}

#Preview("Notifications - fixture") {
  NotificationsSurfaces.fixtureSurface()
}

#Preview("Notifications - empty") {
  NotificationsSurfaces.fixtureSurface(rows: [])
}

#Preview("Notifications - loading") {
  NotificationsSurfaces.fixtureSurface(rows: [], isInitialLoading: true)
}

#Preview("Notifications - dark") {
  NotificationsSurfaces.fixtureSurface(theme: .dark)
}
