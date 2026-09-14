import Foundation
import QueryStore

/// Constants ported from the RN starter-pack surfaces.
///
/// Sources: `src/lib/constants.ts` (`STARTER_PACK_MAX_SIZE`,
/// `JOINED_THIS_WEEK`), `screens/StarterPack/Wizard/index.tsx` (the minimum
/// profile count and the three-feed cap) and
/// `src/state/queries/list-members.ts` (`getAllListMembers`'s page size and page
/// cap).
public enum StarterPackConstants {
  /// The maximum number of profiles a pack's backing list may hold.
  ///
  /// Port of `STARTER_PACK_MAX_SIZE` in `src/lib/constants.ts`.
  public static let maxSize = 150

  /// The number of profiles a pack must contain before the wizard will advance
  /// past the people step.
  ///
  /// RN's footer disables *Next* while `items.length < 8`
  /// (`screens/StarterPack/Wizard/index.tsx`), and the auto-generated pack
  /// refuses to build below seven followers plus the author
  /// (`src/lib/generate-starterpack.ts`).
  public static let minimumProfiles = 8

  /// The maximum number of feeds a pack may pin.
  ///
  /// Port of the `state.feeds.length >= 3` guard in the wizard reducer; the
  /// lexicon itself caps `feeds` at three as well.
  public static let maximumFeeds = 3

  /// A list-item write batch size.
  ///
  /// Port of `chunk(removedItems, 50)` / `chunk(addedProfiles, 50)` in
  /// `src/state/queries/starter-packs.ts`.
  public static let writeChunkSize = 50

  /// Items per page for the paged list-members read. RN: `PAGE_SIZE = 30`.
  public static let listMembersPageSize = 30

  /// Items per page for the exhaustive list-members walk. RN passes `limit: 50`.
  public static let listMembersAllPageSize = 50

  /// The page cap `getAllListMembers` applies. RN: `while (hasMore && i < 6)`.
  public static let listMembersAllPageCap = 6

  /// Items per page for a user's starter packs. RN:
  /// `getActorStarterPacks`/`getStarterPacksWithMembership` with `limit: 10`.
  public static let actorStarterPacksPageSize = 10

  /// The default page size for pack search. RN's hook default is `limit = 25`.
  public static let searchPageSize = 25

  /// The number of member avatars the wizard footer renders.
  public static let wizardFooterAvatarCount = 6

  /// The maximum length of a pack name the wizard accepts.
  ///
  /// RN slices the name field to 50 in the reducer and `StepDetails`.
  public static let maxNameLength = 50

  /// The estimated number of accounts that joined Bluesky through a pack this
  /// week, used by the landing screen's stat line.
  ///
  /// Port of `JOINED_THIS_WEEK`, "estimate as of 12/18/24".
  public static let joinedThisWeek = 560_000

  /// The number of joined accounts below which the pack screen hides its
  /// "people have joined" line.
  ///
  /// Port of the `joinedAllTimeCount >= 25` gates in
  /// `screens/StarterPack/StarterPackScreen.tsx`.
  public static let joinedCountDisplayThreshold = 25

  /// The number of joined accounts below which the landing screen's copy reads
  /// "You'll follow these people right away" instead of naming a remainder.
  ///
  /// Port of the `listItemsCount <= 8` branch in
  /// `screens/StarterPack/StarterPackLandingScreen.tsx`.
  public static let landingSampleThreshold = 8
}

/// Staleness budgets used by the starter-pack queries.
///
/// Ports the `staleTime` each RN query declares.
public enum StarterPackStale {
  /// `useStarterPackQuery` -> `staleTime: STALE.MINUTES.FIVE`.
  public static let packView: TimeInterval = STALE.MINUTES.FIVE
  /// `useStarterPackSearch` -> `staleTime: STALE.MINUTES.FIVE`.
  public static let search: TimeInterval = STALE.MINUTES.FIVE
  /// `useListMembersQuery` / `useAllListMembersQuery` ->
  /// `staleTime: STALE.MINUTES.ONE`.
  public static let listMembers: TimeInterval = STALE.MINUTES.ONE
  /// `useActorStarterPacksQuery` declares no `staleTime`, so it takes the app
  /// default.
  public static let actorStarterPacks: TimeInterval = STALE.MINUTES.ONE
}
