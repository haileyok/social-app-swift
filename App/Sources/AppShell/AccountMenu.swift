import SwiftUI

/**
 The account control in the debug toolbar: who is signed in, and the way out.

 A small menu rather than a screen - the shell's job is to answer "which
 account am I in" and let the user leave, not to be a settings surface. When a
 real profile screen lands this is what it replaces.

 The menu renders from an ``AppSession`` (the shell owns it), never from its own
 copy of the session: sign-out is a call into the session and whatever state it
 reports is what the shell shows.
 */
public struct AccountMenuButton: View {
  private let session: AppSession

  public init(session: AppSession) {
    self.session = session
  }

  public var body: some View {
    Menu {
      Section(ShellCopy.accountMenuTitle) {
        if let handle = session.currentHandle {
          Text(ShellCopy.currentAccount(handle))
        } else {
          Text(ShellCopy.unknownAccount)
        }

        Button(role: .destructive) {
          Task { await session.signOut() }
        } label: {
          Text(ShellCopy.signOutAction)
        }
        .accessibilityIdentifier(ShellAccessibility.signOutButton)
      }
    } label: {
      Image(systemName: "person.crop.circle")
    }
    .accessibilityLabel(ShellCopy.accountMenuLabel)
    .accessibilityIdentifier(ShellAccessibility.accountButton)
  }
}

/**
 The toolbar's leading slot: the account menu when signed in, the debug login
 entry when not.

 Keeping the choice here rather than in each tab's toolbar means the shell has
 one rule about what the account slot shows, and the tab screens stay unaware of
 session state.
 */
public struct ShellAccountControl: View {
  private let session: AppSession?

  public init(session: AppSession?) {
    self.session = session
  }

  public var body: some View {
    // No session means the demo/screenshot shell: the debug login entry is the
    // only account affordance that does not need one.
    if let session, session.isSignedIn {
      AccountMenuButton(session: session)
    } else if let session {
      LoginDebugButton(session: session)
    } else {
      LoginDebugButton()
    }
  }
}

/**
 The account menu's content, without the toolbar chrome.

 Lives apart from ``AccountMenuButton`` so it can be previewed and so the shell
 can mount it somewhere other than a toolbar later (a profile header, say)
 without duplicating the rows.
 */
struct AccountMenuContents: View {
  let handle: String?
  let onSignOut: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(handle.map(ShellCopy.currentAccount) ?? ShellCopy.unknownAccount)
        .accessibilityIdentifier(ShellAccessibility.accountHandle)
      Button(role: .destructive, action: onSignOut) {
        Text(ShellCopy.signOutAction)
      }
      .accessibilityIdentifier(ShellAccessibility.signOutButton)
    }
    .accessibilityIdentifier(ShellAccessibility.accountMenu)
  }
}

#Preview {
  AccountMenuContents(
    handle: "alice.test",
    onSignOut: {})
}
