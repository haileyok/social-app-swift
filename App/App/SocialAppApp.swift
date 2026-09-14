import AppShell
import SwiftUI

/// The entire application target: everything else lives in the AppShell package.
@main
struct SocialAppApp: App {
  var body: some Scene {
    WindowGroup { AppRootView() }
  }
}
