# Domain — ported test manifest

Maps ported RN test cases to the Swift Testing tests that reproduce them.
Source repo: `~/bluesky/social-app` (read-only reference). Paths below are
relative to its `src/`.

| RN source | RN test | Swift test |
|---|---|---|
| `lib/api/feed-manip.ts` | `lib/api/feed-manip.test.ts` — `createFeedViewPostsSlices` > "preserves selected numbering and infers hydrated parent and root numbering" | `FeedManipTests.preservesSelectedNumberingAndInfersHydratedParentAndRootNumbering` |
| `lib/api/feed-manip.ts` | (none — supplementary) | `FeedManipTests.rejectsInvalidNumbering` |
| `lib/strings/errors.ts` | `lib/strings/__tests__/errors.test.ts` — `cleanError` > "surfaces the clean message of a lex error" | `ErrorStringsTests.surfacesTheCleanMessageOfALexError` |
| `lib/strings/errors.ts` | `cleanError` > "falls back to the lexicon code when a lex error has no message" | `ErrorStringsTests.fallsBackToTheLexiconCodeWhenALexErrorHasNoMessage` |
| `lib/strings/errors.ts` | `cleanError` > "matches the upstream-failure branch on a lex error code" | `ErrorStringsTests.matchesTheUpstreamFailureBranchOnALexErrorCode` |
| `lib/strings/errors.ts` | `cleanError` > "matches NotEnoughResources" | `ErrorStringsTests.matchesNotEnoughResources` |
| `lib/strings/errors.ts` | `cleanError` > "matches the app-password branch on a lex error message" | `ErrorStringsTests.matchesTheAppPasswordBranchOnALexErrorMessage` |
| `lib/strings/errors.ts` | `cleanError` > "matches the network-error branch on a lex error message" | `ErrorStringsTests.matchesTheNetworkErrorBranchOnALexErrorMessage` |
| `lib/strings/errors.ts` | `cleanError` > "matches Expo fetch network errors" | `ErrorStringsTests.matchesExpoFetchNetworkErrors` |
| `lib/strings/errors.ts` | `cleanError` > "surfaces the authentication-required code of a lex error" | `ErrorStringsTests.surfacesTheAuthenticationRequiredCodeOfALexError` |
| `lib/strings/errors.ts` | `cleanError` > "strips a leading \"Error: \" from a plain error" | `ErrorStringsTests.stripsALeadingErrorFromAPlainError` |
| `lib/strings/errors.ts` | `cleanError` > "passes strings through" | `ErrorStringsTests.passesStringsThrough` |
| `lib/hooks/useTimeAgo.ts` (`dateDiff`) | `lib/hooks/__tests__/useTimeAgo.test.ts` — `dateDiff` > "works with numbers" | `DateDiffTests.worksWithNumbers` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "works with strings" | `DateDiffTests.worksWithStrings` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "works with dates" | `DateDiffTests.worksWithDates` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "equal values return now" | `DateDiffTests.equalValuesReturnNow` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "future dates return now" | `DateDiffTests.futureDatesReturnNow` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values < 5 seconds ago return now" | `DateDiffTests.valuesUnder5SecondsAgoReturnNow` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values >= 5 seconds ago return seconds" | `DateDiffTests.valuesAtLeast5SecondsAgoReturnSeconds` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values < 1 min return seconds" | `DateDiffTests.valuesUnder1MinReturnSeconds` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values >= 1 min return minutes" | `DateDiffTests.valuesAtLeast1MinReturnMinutes` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "minutes round down" | `DateDiffTests.minutesRoundDown` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values < 1 hour return minutes" | `DateDiffTests.valuesUnder1HourReturnMinutes` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values >= 1 hour return hours" | `DateDiffTests.valuesAtLeast1HourReturnHours` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "hours round down" | `DateDiffTests.hoursRoundDown` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values < 1 day return hours" | `DateDiffTests.valuesUnder1DayReturnHours` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values >= 1 day return days" | `DateDiffTests.valuesAtLeast1DayReturnDays` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "days round down" | `DateDiffTests.daysRoundDown` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values < 30 days return days" | `DateDiffTests.valuesUnder30DaysReturnDays` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values >= 30 days return months" | `DateDiffTests.valuesAtLeast30DaysReturnMonths` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "months round down" | `DateDiffTests.monthsRoundDown` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values are rounded by increments of 30" | `DateDiffTests.valuesAreRoundedByIncrementsOf30` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values < 360 days return months" | `DateDiffTests.valuesUnder360DaysReturnMonths` |
| `lib/hooks/useTimeAgo.ts` | `dateDiff` > "values >= 360 days return the earlier value" | `DateDiffTests.valuesAtLeast360DaysReturnTheEarlierValue` |
| `lib/hooks/useTimeAgo.ts` (`formatDateDiff`) | (none — supplementary) | `DateDiffTests.formatShortForms`, `formatLongForms`, `twelveMonthsRenderTheDate` |

## Sources with no sibling TS tests

These RN modules have no `*.test.ts`. The Swift tests assert outputs captured
from the JS implementation (run under Node) or from the source's documented
behaviour.

| RN source | Swift suite |
|---|---|
| `lib/strings/url-helpers.ts` | `URLHelpersTests` ("url-helpers") |
| `lib/link-meta/link-meta.ts` | `LinkMetaTests` ("link-meta") |
| `view/com/util/numeric/format.ts` (`formatCount`) | `FormatCountTests` ("formatCount") |
| `lib/numbers.ts` (`clamp`) | `ClampTests` ("clamp") |
| `lib/strings/time.ts` | `DateDiffTests` (date helpers) |
