# Login — ported test manifest

Maps the RN source this package ports to the Swift tests that cover it.
Source repo: `~/bluesky/social-app` (read-only reference); paths below are
relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

Unlike Domain/RichText, the login feature has almost no dedicated RN unit
tests: the behaviour lives in the screens (`screens/Login/*.tsx`) and hooks
(`state/queries/pds-detection.ts`), which are covered by component tests.
The cases below are therefore **semantic** ports — each Swift test asserts the
same rule or branch the RN code implements — plus the one genuinely ported
suite, `lib/strings/__tests__/errors.test.ts`, whose subject
(`ErrorStrings.cleanError`) already lives in Domain and is reused here.

## Ported behaviour

| RN source | RN behaviour / test | Swift test |
|---|---|---|
| `screens/Login/LoginForm.tsx` (`attemptLogin`) | `Token is invalid` → "Invalid 2FA confirmation code." | `LoginErrorMappingTests.tokenIsInvalidMapsToInvalidAuthFactorToken` |
| `screens/Login/LoginForm.tsx` (`attemptLogin`) | `Authentication Required` / `Invalid identifier or password` → "Incorrect username or password" | `LoginErrorMappingTests.authenticationRequiredMapsToIncorrectCredentials`, `.invalidIdentifierOrPasswordMapsToIncorrectCredentials` |
| `screens/Login/LoginForm.tsx` (`attemptLogin`) | `isNetworkError(err)` → "Unable to contact your service…" | `LoginErrorMappingTests.networkFailureMapsToNetworkOffline`, `.plainStringNetworkFailureMapsToNetworkOffline` |
| `screens/Login/LoginForm.tsx` (`attemptLogin`) | fallthrough → `cleanError(err)` | `LoginErrorMappingTests.unknownFailureMapsToUnexpectedWithCleanMessage`, `.unknownFailureWithNoMessageFallsBackToTheCode`, `.upstreamFailureMapsToTheServerMessage` |
| `screens/Login/LoginForm.tsx` | `err instanceof LexAuthFactorError` sets the 2FA field | `LoginErrorMappingTests.authFactorRequiredCodeMapsToAuthFactorRequired`, `.aTypedAuthFactorErrorMapsThroughTheFlow` |
| `screens/Login/LoginForm.tsx` | empty username / password are rejected before any request | `LoginFlowStateTests.emptyIdentifierFailsValidationWithoutTouchingTheNetwork`, `.emptyPasswordFailsValidationWithoutTouchingTheNetwork` |
| `screens/Login/LoginForm.tsx` | `failedAttemptCountRef` counts attempts across a session | `LoginFlowStateTests.aNewSubmissionClearsTheShownErrorWhileKeepingTheCount`, `.retryingAfterAFailureSucceeds` |
| `screens/Login/LoginForm.tsx` | 2FA retry re-sends the same credentials with `authFactorToken` | `LoginFlowStateTests.retryWithAuthFactorResendsTheStoredCredentialsAndClearsOnSuccess`, `.retryWithWrongCodeReportsAnInvalidCodeAndStaysRecoverable` |
| `screens/Login/LoginForm.tsx` | a fresh submission clears the displayed error | `LoginFlowStateTests.aFailureIsStickyUntilTheNextSubmission`, `.aNewSubmissionClearsTheShownErrorWhileKeepingTheCount` |
| `screens/Login/LoginForm.tsx` (`createFullHandle`) | a bare username gains the first advertised handle domain | `IdentifierNormalizationTests.aBareUsernameGetsTheFirstAdvertisedDomain`, `.anIdentifierAlreadyEndingInAnAdvertisedDomainIsLeftAlone`, `.anEmailIsNeverCompletedWithADomain`, `.aDidIsNeverCompletedWithADomain`, `.withNoAdvertisedDomainsTheIdentifierIsUnchanged` |
| `screens/Login/index.tsx` | `Forms` transitions between sign-in steps | `LoginFlowStateTests.startsInTheCredentialStepAgainstTheDefaultService`, `.pickingAServiceAndReturningKeepsTheDefault`, `.resetRestoresEveryField`, `.listenersSeeEveryTransition` |
| `screens/Login/index.tsx` | service-description failure surfaces "Unable to contact your service" | `ServiceResolutionTests.aFailedDescriptionRefreshClearsTheAdvertisedDomains`, `.aDeadHostIsReportedAsUnreachable`, `.aHostThatIsNotAPdsIsReportedAsSuch` |
| `screens/Login/ChooseAccountForm.tsx` | no `accessJwt` → fall back to the login form | `StoredAccountTests.resumeDecisionTable`, `.anAccountWithoutTokensGoesBackToTheCredentialStep` |
| `screens/Login/ChooseAccountForm.tsx` | a stored account resumes and becomes current | `StoredAccountTests.aResumableAccountIsSwitchedToAndBecomesCurrent` |
| `screens/Login/ForgotPasswordForm.tsx` | invalid email is rejected locally; network vs server error copy | `PasswordResetFlowTests.anInvalidEmailFailsLocallyWithoutCallingTheService`, `.aNetworkFailureReportingTheResetEmailIsReportedAsOffline`, `.aServerRejectionReportingTheResetEmailUsesTheCleanMessage`, `.aValidEmailRequestsAResetAndMovesOn` |
| `screens/Login/SetNewPasswordForm.tsx` | reset code and password submitted to `resetPassword` | `PasswordResetFlowTests.aValidCodeAndPasswordSetTheNewPassword`, `.anInvalidCodeFailsLocally`, `.anEmptyPasswordFailsLocally`, `.aRejectedResetCodeUsesTheCleanServerMessage` |
| `lib/strings/password.ts` | `checkAndFormatResetCode` (base32 `XXXXX-XXXXX`, dash inserted for 10 chars) | `ResetCodeTests.formattingTable`, `.invalidCodesAreRejected` |
| `state/queries/pds-detection.ts` (`normalizeIdentifier`) | trim, lowercase, strip one leading `@` | `IdentifierNormalizationTests.normalizationTable`, `.aLeadingAtIsStrippedSoHandlesDoNotLookLikeEmails` |
| `state/queries/pds-detection.ts` (`isPlausibleHandle`) | detection only for dotted handles and DIDs | `IdentifierNormalizationTests.plausibleHandleTable` |
| `state/queries/pds-detection.ts` (`useHostingProvider`) | state machine: idle/email/detecting/detected/overridden/unresolved/error | `ServiceSelectionTests.anEmailSelectsTheDefaultService`, `.aBareUsernameIsIdleAndUsesTheDefaultService`, `.anUnsettledDebounceReportsDetectingNotTheStaleResult`, `.aResolvedHandleSelectsItsPds`, `.aResolvedDidWithNoPdsEndpointIsUnresolved`, `.aNetworkFailureIsAnErrorNotAnUnresolvedHandle`, `.anUnknownHandleIsUnresolved`, `.anOverrideBypassesDetectionEntirely` |
| `state/queries/pds-detection.ts` (`resolveService`) | override wins; email/bare username use the default; network errors rethrow | `ServiceSelectionTests.resolvingAnOverrideNeverLooksUpTheHandle`, `.resolvingAnEmailSkipsTheLookup`, `.resolvingAPlausibleHandleUsesTheLookupResult`, `.aNetworkErrorDuringResolutionPropagates`, `.signInUsesTheLookedUpServiceAndFailsOnANetworkError`, `.signInTargetsTheLookedUpPds` |
| `state/queries/service.ts` (`useServiceQuery`) | `describeServer` against the typed host, unauthenticated | `ServiceResolutionTests.describeServerReturnsTheDomainsAndDid`, `.resolutionCanSkipThePreflight` |
| `state/queries/pds-detection.ts` | a non-Bluesky auto-detected host needs a confirmation dialog | `ServiceSelectionTests.theHostingProviderConfirmationRule` |
| `screens/Login/LoginForm.tsx` | unknown account + known DID skips the confirmation | `ServiceSelectionTests.theHostingProviderConfirmationRule` |
| `components/dialogs/ServerInput.tsx` (`getFormState`) | trim, lowercase, `http://` for localhost else `https://` | `ServiceNormalizationTests.normalizationTable`, `.unusableAddressesAreRejected`, `.requestBaseDropsTheTrailingSlash` |
| `components/dialogs/ServerInput.tsx` | a custom address is persisted/normalized as a URL | `ServiceNormalizationTests.aBareHostValidatesToItsNormalizedForm`, `.requestURLsNeverContainADoubleSlash` |
| `lib/strings/url-helpers.ts` (`isBlueskyHostedUrl`) | `bsky.social` or `*.host.bsky.network` | `ServiceNormalizationTests.blueskyHostedAddressesAreRecognised`, `.nonBlueskyAddressesAreNotRecognised` |
| `lib/strings/url-helpers.ts` (`toNiceHostingUrl`) | `*.host.bsky.network` renders as "Bluesky" | `ServiceSelectionTests.niceHostRendering` |
| `state/session` (`login`) | a successful sign-in records the account and makes it current | `LoginFlowStateTests.successfulSignInRecordsTheAccountAndCountsNoFailure`, `StoredAccountTests.aSuccessfulSignInIsRecordedInTheStore` |
| `state/session` (account list) | most-recently-used first; forget removes the entry | `StoredAccountTests.accountsAreListedMostRecentlyUsedFirst`, `.forgettingAnAccountRemovesItEntirely`, `.forgettingAnUnknownAccountThrows` |
| `lib/strings/__tests__/errors.test.ts` | `cleanError` suite (10 cases) | Ported in `Packages/Domain` (`ErrorStringsTests`); reused here through `LoginErrorMapper` |

## Deviations from the RN flow

1. **No debounce.** `useHostingProvider` debounces identifier detection (500 ms)
   in React state. ``ServiceSelection`` takes `isDebounceSettled` as an input
   instead, so the debounce stays a view concern and the decision rule is
   testable without a clock.
2. **Hosting-provider preflight distinguishes dead host from non-PDS.** RN
   collapses every `describeServer` failure into one message.
   ``ServiceResolutionError`` separates `unreachable` from `notAPDS` so the
   form can point at the right fix.
3. **Rate limiting and app-password scope are first-class `LoginError`
   cases.** RN's `attemptLogin` has no branch for either and would render the
   server message through `cleanError`. The check order still follows RN's
   (invalid-code, invalid-credentials, then the added cases, then network).
4. **A sticky failure step.** RN keeps the error in `useState` until the next
   submission, and the form's step never moves. ``LoginFlow`` models that with
   a `.failed(error)` step that persists until the next `signIn` call, which
   clears it via ``LoginState/clearError()`` — so the count carries across
   attempts (as RN's ref does) while the shown error does not.
5. **Reset-code alphabet.** `ResetCode` is a hand-rolled port of the RN regex
   `^[A-Z2-7]{5}-[A-Z2-7]{5}$` rather than the NSRegularExpression, because the
   Swift regex facilities differ across Linux and Darwin. `1`, `8`, and `9` are
   rejected exactly as in the RN pattern.
6. **No analytics.** RN emits `signin:*` metrics throughout. `LoginFlow`
   exposes the data they would use (`failedAttemptCount`, `serviceOverride`,
   the account) and leaves emission to the app layer.
