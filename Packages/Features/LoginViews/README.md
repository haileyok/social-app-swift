# LoginViews

The SwiftUI half of the Login feature: the app's first real user-facing surface.

| Screen | Type | Logic it renders |
|---|---|---|
| `LoginScreen` | screen | `LoginFlow` |
| `ServicePickerSheet` | sheet | `LoginFlow.selectCustomService` / `ServiceResolver` |
| `AuthFactorSheet` | sheet | `LoginFlow.retryWithAuthFactor(_:)` |
| `ChooseAccountView` | section | `LoginFlow.storedAccounts()` / `signInWithStoredAccount(_:)` / `forgetAccount(_:)` |
| `ForgotPasswordFlowView` | flow | `PasswordResetFlow` |
| `ForgotPasswordScreen` | screen | `PasswordResetFlow` step `.enteringEmail` |
| `SetNewPasswordScreen` | screen | `PasswordResetFlow` step `.enteringNewPassword` / `.passwordUpdated` |

## Layout of the package

- `LoginViewModel` / `PasswordResetViewModel` - the only bridge to the logic
  packages. `LoginFlow` and `PasswordResetFlow` are `Sendable` value-state types
  observed through `addListener`, not `Observable`; the adapters register one
  listener each and republish on the main actor.
- `LoginFormControls.swift` - the form primitives the app does not have yet:
  `LoginTextField`, `LoginValidationLine`, `LoginErrorBanner`, `LoginLinkButton`.
  `UIComponents` ships no `TextField`, so the login form carries its own.
- `LoginAccessibility.swift` - every identifier the XCUITest addresses.
- `LoginStringCatalog.swift` (`LoginCopy`) - the localization seam.

## Localization seam

Every user-facing string is read through `LoginCopy` (or, for the failure copy,
through `LoginError.message` / `PasswordResetError.message`, which `LoginLogic`
already owns as the RN-sourced English). No view contains a scattered literal.
Replacing the statics with `String(localized:)` and adding a String Catalog is a
one-file change.

## Deviations from the React Native screens

Native-first choices, with the reason:

1. **The service picker is a sheet, not an inline form swap.** RN's `Login` screen
   swaps `Form.Login` for `Form.ConfigureServiceUrl` in place. A `presentationDetents`
   sheet keeps the credential form visible behind it and gets the platform's
   dismissal affordances for free.
2. **The stored-account chooser is a button, then a full section.** RN always
   renders `ChooseAccountForm` above the form when accounts exist. Here the form
   shows a one-line summary and expands the list on demand, so the common case
   (signing in with a password) is not pushed down the screen.
3. **The 2FA prompt is a sheet.** RN swaps the form body. The 2FA demand is
   modal by nature (nothing else can proceed), so a sheet matches.
4. **Validation is inline, not a disabled submit button.** An empty submit still
   reaches the flow and renders `LoginStrings.pleaseEnterUsername` /
   `pleaseEnterPassword` beside the fields. This is the RN behaviour, and it
   gives a specific reason instead of a dead control.
5. **Keyboard and focus flow are explicit.** The identifier field's return key
   moves focus to the password field, the password field's return key submits,
   both sheets focus their first field on appear, and every scroll view dismisses
   the keyboard interactively.
6. **Retry is offered only when `LoginError.isRecoverable`.** `appPasswordNotAllowed`
   and `unexpected` present no retry button, because retrying would fail
   identically.
7. **Dynamic Type**: all text goes through `AlfText`/`TypeScale` (which carries
   the font-scale multiplier), long copy uses `fixedSize(horizontal: false,
   vertical: true)` so it wraps rather than truncating, and the form is capped at
   `maxWidth: 480` inside a `ScrollView` so it stays readable at large sizes and
   on iPad.
8. **The hosting-provider security check uses a native alert.** The flow resolves
   the handle without sending the password, then pauses for explicit approval
   when an unfamiliar DID points at a non-Bluesky provider. Continue authenticates
   the retained resolved context; Go back returns to the editable form without a
   `createSession` request.

## Not implemented here

- No session/root takeover. `LoginScreen` reports a successful sign-in through
  its `onSignedIn` callback; deciding what the app root shows afterwards is the
  app shell's call, not this package's.
