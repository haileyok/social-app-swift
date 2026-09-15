import DesignSystem
import DesignTokens
import SwiftUI

/**
 One placeholder screen per tab.

 Every tab is a `NavigationStack` with a themed placeholder body, so the shell
 exercises navigation, theming and typography without depending on feature
 packages that have not landed. Each host tab's toolbar carries the account
 control (the signed-in account menu, or the debug login entry) and a debug
 button that pushes the DesignSystem token gallery, which keeps AC.7's
 screenshot surface reachable before there is a Settings screen.
 */
public struct TabPlaceholderScreen: View {
  private let tab: AppTab

  /**
   The session the account control reports, when the shell has one.

   The demo/screenshot path passes nil: it renders the shell exactly as the app
   did before the session gate, so its toolbar carries the debug login entry and
   nothing on that path consults a session store.
   */
  private let session: AppSession?

  @Environment(\.alfTheme) private var theme

  public init(tab: AppTab, session: AppSession?) {
    self.tab = tab
    self.session = session
  }

  public var body: some View {
    NavigationStack {
      content
        .navigationTitle(tab.title)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
              TokenGallery(theme: theme)
                .navigationTitle("Tokens")
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier(ShellAccessibility.tokenGallery)
            } label: {
              Image(systemName: "circle.lefthalf.filled")
            }
            .accessibilityLabel("Token gallery")
            .accessibilityIdentifier(ShellAccessibility.tokenGalleryButton)
          }
          ToolbarItem(placement: .topBarLeading) {
            ShellAccountControl(session: session)
          }
        }
    }
    .accessibilityIdentifier(ShellAccessibility.screen(tab.routeName))
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      Spacer(minLength: Spacing.lg)

      Image(systemName: tab.systemImage)
        .font(.system(size: 44, weight: .regular))
        .foregroundStyle(theme.atomColors.textContrastMedium)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: Spacing.xs) {
        AlfText(tab.title, scale: .xxl, weight: Scales.FontWeight.bold)
        AlfText(
          tab.placeholderDetail,
          scale: .md,
          color: theme.atomColors.textContrastMedium)
      }

      AlfText(
        "Route \(tab.routeName) — placeholder until Phase 5",
        scale: .xs,
        color: theme.atomColors.textContrastLow)

      Spacer(minLength: Spacing.xxl)
    }
    .padding(.horizontal, Spacing.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.atomColors.bg)
  }
}
