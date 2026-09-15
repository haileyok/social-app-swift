# Messages — ported test manifest

Maps the React Native messages source this package ports to the Swift tests that
cover it. Source repo: `~/bluesky/social-app` (read-only reference); paths below
are relative to its `src/`. Swift tests use Swift Testing (`import Testing`).

## Scope: the minimal 1:1 surface

This package implements the 1:1 messages scope. The RN messages feature is much
larger — group chats, join links, join requests, convo requests, locking, group
membership — and none of that is implemented here. What *is* implemented:

- the chat-routed XRPC client wiring (`LiveChatXrpc` over
  `atproto-proxy: did:web:api.bsky.chat#bsky_chat`),
- the inbox list and the unread badge counts,
- a single conversation's history, send outbox, reactions, read state, mute and
  delete,
- the incremental `getLog` sync engine and the log-to-cache reducer.

Group and unknown wire shapes are **decoded but never applied**: the generated
log union is projected through `ChatLogEvent`, which maps every group /
join-link / join-request variant to `.groupEvent` and anything unrecognized to
`.other`. Neither throws, and the data layer skips both. That tolerance is the
subject of the `ToleranceTests` suite.

## Endpoint coverage

| XRPC procedure | Swift entry point | Swift test |
|---|---|---|
| `chat.bsky.convo.listConvos` | `LiveChatXrpc.listConvos`, `InboxQuery` | `ChatClientWiringTests.listConvosEncodesQueryParams`, `InboxTests.loadsFirstPageInRevOrder` |
| `chat.bsky.convo.getConvo` | `LiveChatXrpc.getConvo`, `ConvoQuery` | `ChatClientWiringTests.chatProxyHeaderIsEmittedOnEveryCall`, `InboxTests.convoQueryPrecachesWithoutARequest` |
| `chat.bsky.convo.getMessages` | `LiveChatXrpc.getMessages` | `ChatClientWiringTests.getMessagesEncodesConvoIdLimitCursor`, `ConversationTests.fetchesInitialHistoryChronologically` |
| `chat.bsky.convo.getLog` | `LiveChatXrpc.getLog`, `LogSync` | `ChatClientWiringTests.getLogEncodesCursorOnly`, `LogSyncTests.initializeSeedsTheCursorWithoutEvents` |
| `chat.bsky.convo.sendMessage` | `LiveChatXrpc.sendMessage` | `ChatClientWiringTests.sendMessagePostsExactInputBody`, `ConversationTests.sendReconcilesViaTheResponse` |
| `chat.bsky.convo.sendMessageBatch` | `LiveChatXrpc.sendMessageBatch` | `ChatClientWiringTests.sendMessageBatchPostsItemsArray`, `ConversationTests.batchRetrySendsTheWholeQueue` |
| `chat.bsky.convo.addReaction` | `LiveChatXrpc.addReaction` | `ChatClientWiringTests.addReactionPostsConvoMessageValue`, `ConversationTests.addReactionIsOptimisticThenReconciled` |
| `chat.bsky.convo.removeReaction` | `LiveChatXrpc.removeReaction` | `ChatClientWiringTests.removeReactionPostsSameShape`, `ConversationTests.removeReactionIsOptimisticThenReconciled` |
| `chat.bsky.convo.updateRead` | `LiveChatXrpc.updateRead` | `ChatClientWiringTests.updateReadPostsConvoAndOptionalMessage`, `updateReadZeroesUnreadAndReturnsTheConvo` |
| `chat.bsky.convo.updateAllRead` | `LiveChatXrpc.updateAllRead` | `ChatClientWiringTests.updateAllReadPostsStatus` |
| `chat.bsky.convo.getUnreadCounts` | `LiveChatXrpc.getUnreadCounts`, `UnreadCountsQuery` | `ChatClientWiringTests.getUnreadCountsEncodesIncludeGroupChats`, `InboxTests.unreadCountsQueryHas15sStaleTime` |
| `chat.bsky.convo.muteConvo` / `unmuteConvo` | `LiveChatXrpc.muteConvo`, `setMuted` | `ChatClientWiringTests.muteAndUnmuteRouteToTheirProcedures`, `muteIsOptimisticAndRollsBackOnFailure` |
| `chat.bsky.convo.leaveConvo` | `LiveChatXrpc.leaveConvo` | `ChatClientWiringTests.leaveConvoReturnsIdAndRev`, `leaveClearsTheConvoAndRestoresOnFailure` |
| `chat.bsky.convo.deleteMessageForSelf` | `LiveChatXrpc.deleteMessageForSelf` | `ChatClientWiringTests.deleteMessageForSelfDecodesDeletedView`, `deleteIsOptimisticAndHidesTheMessage` |

## Ported behaviour

| RN source | RN behaviour / test | Swift test |
|---|---|---|
| `state/session/index.ts` (`useChatClient`) | chat calls are routed with `atproto-proxy: did:web:api.bsky.chat#bsky_chat`, not the appview proxy | `ChatClientWiringTests.chatProxyHeaderIsEmittedOnEveryCall`, `ChatClientWiringTests.chatProxyIsNotTheAppviewProxy` |
| `state/queries/messages/list-conversations.tsx` (`useListConvosQuery`) | `DEFAULT_LIMIT = 10`, `getNextPageParam: lastPage => lastPage.cursor` | `InboxTests.loadsFirstPageInRevOrder`, `InboxTests.pagesThroughCursors` |
| `state/queries/messages/list-conversations.tsx` (`RQKEY`) | the key is `['convo-list', status, readState, kind, lockStatus, limit]` | `InboxTests.keyRootsMatchRN`, `InboxTests.keyDistinguishesFilters`, `InboxTests.keyCarriesScope` |
| `state/queries/messages/list-conversations.tsx` (`useListConvosQuery`) | `readState: 'unread'` and `status` are sent as query params, other filters omitted | `InboxTests.unreadOnlyFilterIsSent`, `ChatClientWiringTests.listConvosOmitsNilFilters` |
| `state/queries/messages/get-unread-counts.ts` (`useUnreadCountsQuery`) | `staleTime: STALE.SECONDS.FIFTEEN`, `includeGroupChats` param | `InboxTests.unreadCountsQueryHas15sStaleTime`, `ChatClientWiringTests.getUnreadCountsEncodesIncludeGroupChats` |
| `state/queries/messages/get-unread-counts.ts` (`UNREAD_ACCEPTED_CAP`) | the counts are sentinel-capped at 100 and must not be clamped locally | `ChatClientWiringTests.getUnreadCountsEncodesIncludeGroupChats` |
| `state/queries/messages/conversation.ts` (`useConvoQuery`) | `staleTime: STALE.INFINITY`; the value is refreshed by invalidation | `InboxTests.convoQueryIsNeverTimeStale` |
| `state/queries/messages/conversation.ts` (`precacheConvoQuery`) | a convo can be written into the cache without a request | `InboxTests.convoQueryPrecachesWithoutARequest` |
| `state/queries/messages/conversation.ts` (`useMarkAsReadMutation.onSuccess`) | the convo row's `unreadCount` is reset to 0 | `updateReadZeroesUnreadAndReturnsTheConvo` |
| `state/queries/messages/utils/convo-cache.ts` (`updateConvoOptimistic`) | a mutation writes optimistically and rolls back on error | `muteIsOptimisticAndRollsBackOnFailure`, `InboxReducerTests.writeTouchesTheSingleConvoCache` |
| `state/messages/convo/agent.ts` (`fetchMessageHistory`) | `limit: 30`, cursor-walked; the cursor is trusted over page length | `ConversationTests.fetchesInitialHistoryChronologically`, `ConversationTests.fetchesAdditionalHistoryViaCursor`, `ConversationTests.trustsTheCursorOverAShortPage` |
| `state/messages/convo/agent.ts` (`fetchMessageHistory` error) | a failed history fetch renders a retry row | `ConversationTests.historyFailureSetsTheRetryState` |
| `state/messages/convo/agent.ts` (`sendMessage`) | an empty message with no embed is ignored | `ConversationTests.emptyMessagesAreIgnored` |
| `state/messages/convo/agent.ts` (`sendMessage`) | a send into a `request` convo flips it to `accepted` optimistically | `ConversationTests.sendIntoARequestConvoAcceptsItOptimistically` |
| `state/messages/convo/agent.ts` (`processPendingMessages`) | the outbox drains in order; the response reconciles the pending row | `ConversationTests.sendsAreProcessedInOrder`, `ConversationTests.sendReconcilesViaTheResponse` |
| `state/messages/convo/agent.ts` (`processPendingMessages`) | a successful send inserts into `newMessages` and the later log event replaces it in situ | `ConversationTests.successfulSendReordersWhenTheLogArrives` |
| `state/messages/convo/agent.ts` (`handleSendMessageFailure`) | `NETWORK_FAILURE_STATUSES` are recoverable, everything else unrecoverable | `ConversationTests.networkFailureIsRecoverable`, `ConversationTests.rejectionIsUnrecoverable` |
| `state/messages/convo/agent.ts` (`handleSendMessageFailure`) | a failure marks the whole pending queue failed | `ConversationTests.failedSendFailsAllSendingMessages` |
| `state/messages/convo/agent.ts` (`batchRetryPendingMessages`) | a recoverable queue is retried as one `sendMessageBatch` | `ConversationTests.batchRetrySendsTheWholeQueue`, `ConversationTests.batchRetryIsRefusedWhenNotRecoverable` |
| `state/messages/convo/agent.ts` (`addReaction`) | optimistic, reconciled by the response, rolled back on error | `ConversationTests.addReactionIsOptimisticThenReconciled`, `ConversationTests.reactionIsRolledBackOnFailure` |
| `state/messages/convo/agent.ts` (`addReaction`) | the emoji must be one grapheme; a duplicate is a no-op; max 5 per sender | `ConversationTests.multiScalarEmojiIsOneGrapheme`, `ConversationTests.addReactionRejectsNonSingleGrapheme`, `ConversationTests.duplicateReactionIsANoOp`, `ConversationTests.atMostFiveReactionsPerSender` |
| `state/messages/convo/agent.ts` (`removeReaction`) | optimistic removal, rolled back on error | `ConversationTests.removeReactionIsOptimisticThenReconciled` |
| `state/messages/convo/agent.ts` (`deleteMessage`) | the id goes into `deletedMessages` before the request, and stays gone | `deleteIsOptimisticAndHidesTheMessage` |
| `state/messages/convo/agent.ts` (`getItems`) | the list is past, then new, then pending, filtered through the deleted set | `itemsArePastThenNewThenPending` |
| `state/messages/convo/agent.ts` (`ingestFirehose`) | a `logCreateMessage` replaces a message already admitted by our own send | `ConversationTests.successfulSendReordersWhenTheLogArrives` |
| `state/messages/convo/agent.ts` (`ingestFirehose`) | a `logDeleteMessage` removes the message and tombstones it | `deleteViaLogRemovesAndTombstones` |
| `state/messages/convo/agent.ts` (`ingestFirehose`) | the convo rev advances to the newest event | `revAdvancesToTheNewestEvent` |
| `state/messages/events/agent.ts` (`MessagesEventBus.init`) | `getLog` with no cursor seeds the rev without replaying events | `LogSyncTests.initializeSeedsTheCursorWithoutEvents` |
| `state/messages/events/agent.ts` (`MessagesEventBus.init`) | the seed takes the max of the held rev and the server cursor, never rewinding | `LogSyncTests.reinitializeNeverRewindsTheCursor` |
| `state/messages/events/agent.ts` (`MessagesEventBus.poll`) | only events with a rev strictly greater than the cursor are emitted | `LogSyncTests.pollReturnsOnlyEventsPastTheCursor`, `LogSyncTests.repeatedPollsDoNotRedeliver` |
| `state/messages/events/agent.ts` (`MessagesEventBus.poll`) | a batch is emitted oldest-first | `LogSyncTests.batchesAreOrderedOldestFirst` |
| `state/messages/events/agent.ts` (`MessagesEventBus.poll`) | the rev advances for any rev-bearing event, cared about or not | `ToleranceTests.groupEventsAreEmittedButSkippedAtTheDataLayer` |
| `state/messages/events/agent.ts` (`MessagesEventBus.init` error) | `InitFailed` when there is no cursor to resume from | `LogSyncTests.initFailureReportsInitPhaseAndLeavesCursorUnset` |
| `state/messages/events/agent.ts` (`MessagesEventBus.poll` error) | `PollFailed` keeps the cursor | `LogSyncTests.pollFailureReportsPollPhaseAndKeepsTheCursor` |
| `state/messages/events/agent.ts` (`MessagesEventBus.recoverFromError`) | a seeded bus resumes from its cursor and does not skip events | `LogSyncTests.recoverResumesFromTheHeldCursorWithoutSkipping`, `LogSyncTests.recoverFromAnUnseededBusReseeds` |
| `state/messages/events/agent.ts` (`MessagesEventBus.on`) | a subscriber can be scoped to one `convoId` | `logEventsOnlyAffectThisConvo` |
| `state/queries/messages/list-conversations.tsx` (`logCreateMessage` arm) | the convo bumps to page one with the new last message | `InboxReducerTests.createMessageBumpsToTopAndCountsUnread` |
| `state/queries/messages/list-conversations.tsx` (`logCreateMessage` arm) | `unreadCount` increments unless the convo is open, and never for our own message | `InboxReducerTests.ownMessageDoesNotIncrementUnread`, `InboxReducerTests.createMessageForTheOpenConvoStaysRead` |
| `state/queries/messages/list-conversations.tsx` (`logCreateMessage` arm) | `relatedProfiles` are merged into members, deduped | `InboxReducerTests.createMessageMergesRelatedProfiles` |
| `state/queries/messages/list-conversations.tsx` (`logCreateMessage` arm) | an unknown convo triggers a refetch rather than a synthesized row | `InboxReducerTests.unknownConvoFlagsARefetch` |
| `state/queries/messages/list-conversations.tsx` (`logDeleteMessage` arm) | the deleted message replaces `lastMessage` only when it *is* the last message | `InboxReducerTests.deleteMessageRewritesLastMessageOnlyWhenItMatches` |
| `state/queries/messages/list-conversations.tsx` (`logReadConvo` arm) | the row's unread count resets and the rev advances | `InboxReducerTests.readEventsZeroUnreadWithRevGuard` |
| `state/queries/messages/list-conversations.tsx` (`logReadMessage` arm) | the deprecated event behaves like `logReadConvo` | `InboxReducerTests.readEventsZeroUnreadWithRevGuard` |
| `state/queries/messages/list-conversations.tsx` (`withRevGuard`) | an event at or below the cached rev is ignored | `InboxReducerTests.revGuardIgnoresStaleEvents` |
| `state/queries/messages/list-conversations.tsx` (`logMuteConvo`/`logUnmuteConvo` arms) | the muted flag flips | `InboxReducerTests.muteAndUnmuteFlipTheFlag` |
| `state/queries/messages/list-conversations.tsx` (`logLeaveConvo` arm) | the convo is dropped from every list | `InboxReducerTests.leaveRemovesTheConvoFromAllLists` |
| `state/queries/messages/list-conversations.tsx` (`logAcceptConvo` arm) | the convo moves from the request list to the head of the accepted list | `InboxReducerTests.acceptConvoMovesItFromRequestToAccepted` |
| `state/queries/messages/list-conversations.tsx` (`convoMatchesQueryKey`) | optimistic inserts honor the filters the key encodes | `InboxReducerTests.matchesEncodesTheListFilters` |
| `state/queries/messages/list-conversations.tsx` (`optimisticUpdate`/`optimisticDelete`) | a page-list rewrite preserves page boundaries and cursors | `InboxReducerTests.removingAndPrependingPreservePagination` |
| `state/messages/convo/agent.ts` (`isConvoItemMessage` filter) | a convo the 1:1 client does not own (a group) is skipped at the data layer | `InboxTests.groupConvosAreSkippedAtTheDataLayer` |
| `state/messages/convo/agent.ts` (`toDeletedMessageView`) | a deleted message keeps its id/rev/sender/sentAt as a tombstone | `InboxReducerTests.deleteMessageRewritesLastMessageOnlyWhenItMatches` |

## Tolerance (group / unknown wire shapes)

The 1:1 scope never *calls* a group procedure, but a `getLog` batch on a real
account can contain group events, and the log union is open. These tests pin the
"decode, don't throw, skip" contract.

| RN source | Behaviour | Swift test |
|---|---|---|
| `state/messages/convo/agent.ts` (the `isType(...)` ladder) | the 19 group/join-link/join-request log variants decode to a tolerated case | `ToleranceTests.groupEventsDecodeAsGroupEvents` |
| `state/messages/events/agent.ts` (`poll`) | an unrecognized `$type` decodes and is skipped, without advancing the cursor | `ToleranceTests.unknownLogTypeDecodesWithoutThrowing`, `LogSyncTests.eventsWithoutARevDoNotAdvanceTheCursor` |
| `state/messages/convo/agent.ts` (`ingestFirehose`) | tolerated events never touch the model | `ToleranceTests.modelSkipsToleratedEventsDirectly`, `ToleranceTests.groupEventsAreEmittedButSkippedAtTheDataLayer` |
| `state/messages/convo/agent.ts` (`updateGroupName` guard) | a `groupConvo` kind decodes and is rejected by the direct-convo filter | `ToleranceTests.groupConvoKindIsDecoded` |
| `state/messages/convo/agent.ts` (`ingestFirehose` type checks) | an unknown `messageView` variant inside a create/delete is tolerated | `ToleranceTests.unknownLogCreateMessagePayloadIsTolerated`, `ToleranceTests.unknownSystemMessageDataIsTolerated` |
| `state/messages/convo/agent.ts` (`fetchMessageHistory`) | an unknown union arm in `getMessages` does not break the page | `ToleranceTests.unknownMessageUnionInGetMessagesIsTolerated` |

## Deviations from RN

1. **The `Convo` agent is an actor, not a React store.** RN's `Convo` is a class
   with a `subscribe`/`getSnapshot` pair feeding `useSyncExternalStore`.
   `ConversationModel` keeps the same state machine (`pastMessages`,
   `newMessages`, `pendingMessages`, `deletedMessages`, the same item ordering)
   but exposes `state()` and mutating methods, with no Observation or UI.
2. **Item rendering is data, not JSX.** RN's `getItems` returns `ConvoItem`s
   carrying React `key`s and retry closures; here `ConvoItem` is a plain enum and
   the retry hooks are the model's own methods. The `error` rows keep RN's codes.
3. **History is a model field, not a query.** RN holds message history in the
   agent; this port keeps it there too, but exposes it through
   `MessagesKeys.messages` so a caller can persist or observe it uniformly.
4. **The inbox reducer enumerates keys instead of using prefix writes.**
   TanStack's `setQueriesData({queryKey: [RQKEY_ROOT]})` writes every matching
   cache in one call. `QueryStore` has no prefix write, so `InboxReducer`
   enumerates `store.keys(root:)`. Same effect, more round trips inside the actor.
5. **Refetch is a flag, not a throttled timer.** RN schedules a throttled
   `invalidateQueries` when a log event names an unknown convo. This port sets
   `RefetchFlag` and lets the caller schedule, because timers do not belong in a
   Linux-tested logic package.
6. **`lockStatus` and `kind` filters exist but are inert.** They are carried on
   the key so a persisted key round-trips and the reducer's filter check matches
   RN's shape, but the 1:1 scope never sends `lockStatus` and its
   `convoMatchesQueryKey` returns false for a `group`-filtered list.
7. **No moderation.** RN moderates convo members and message text through
   `moderateProfile`/`moderateChat`. This package does not; moderation is not in
   the 1:1 logic scope as specified.

## Coverage gaps (honest list)

These are things the RN source does that this package deliberately does not, or
does not test.

| Area | Status |
|---|---|
| `state/messages/convo/agent.ts` profile shadows (`applyProfileShadows`) | **not covered** - no test; the shadow overlay is not ported. |
| `state/messages/convo/agent.ts` inactivity rehydration (`wasChatInactive`) | **not covered** - the `it.todo`s in `__tests__/convo.test.ts` are unimplemented in RN too, and the policy is not ported. |
| `state/messages/convo/agent.ts` placeholder data (`setupPlaceholderData`) | **not covered** - a caller passes an initial convo view instead. |
| `state/messages/convo/agent.ts` suspended/disabled convo states | **not covered** - the state machine (background/suspend/resume) is not ported; only the ready path is. |
| `state/messages/convo/agent.ts` `updateGroupName`/`updateGroupMembers`/`updateJoinLink`/`updateLockStatus` | **not implemented** - group surface, out of the 1:1 scope. |
| `state/queries/messages/actor-declaration.ts` chat settings | **not implemented** - out of scope. |
| Everything under `state/queries/messages/*` for groups/requests/join links | **not implemented** - out of scope; the wire shapes are tolerated by design. |
| `screens/Messages/**` (UI) | **not covered** - this is a Logic package. |

## The ported RN test file

`state/messages/__tests__/convo.test.ts` is entirely `it.todo` in RN: 17 unimplemented
cases. This package implements the behaviour those `it.todo`s describe and covers
it, case for case:

| RN `it.todo` | Swift test |
|---|---|
| `init` / `fails if sender and recipients aren't found` | **not covered** - the Swift model is constructed with the sender DID; missing-recipient handling is the caller's. |
| `history fetching` / `fetches initial chat history` | `ConversationTests.fetchesInitialHistoryChronologically` |
| `history fetching` / `fetches additional chat history` | `ConversationTests.fetchesAdditionalHistoryViaCursor` |
| `history fetching` / `handles history fetch failure` | `ConversationTests.historyFailureSetsTheRetryState` |
| `history fetching` / `does not insert deleted messages` | `deleteViaLogRemovesAndTombstones` |
| `sending messages` / `optimistically adds sending messages` | `ConversationTests.optimisticallyAddsSendingMessages` |
| `sending messages` / `sends messages in order` | `ConversationTests.sendsAreProcessedInOrder` |
| `sending messages` / `failed message send fails all sending messages` | `ConversationTests.failedSendFailsAllSendingMessages` |
| `sending messages` / `can retry all failed messages via retry ConvoItem` | `ConversationTests.batchRetrySendsTheWholeQueue` |
| `sending messages` / `successfully sent messages are re-ordered, if needed, by events received from server` | `ConversationTests.successfulSendReordersWhenTheLogArrives` |
| `sending messages` / `pending messages are cleaned up from state after firehose event` | `ConversationTests.sendReconcilesViaTheResponse` |
| `deleting messages` / `messages are optimistically deleted from the chat` | `deleteIsOptimisticAndHidesTheMessage` |
| `deleting messages` / `messages are confirmed deleted via events from the server` | `deleteViaLogRemovesAndTombstones` |
| `deleting messages` / `deleted messages are cleaned up from state after firehose event` | `deleteViaLogRemovesAndTombstones` |
| `log handling` / `updates rev to latest message received` | `revAdvancesToTheNewestEvent` |
| `log handling` / `only handles log events for this convoId` | `logEventsOnlyAffectThisConvo` |
| `log handling` / `does not insert deleted messages` | `deleteIsOptimisticAndHidesTheMessage` |
| `item ordering` / `pending items are first, and in order` | `itemsArePastThenNewThenPending` |
| `item ordering` / `new message items are next, and in order` | `itemsArePastThenNewThenPending` |
| `item ordering` / `past message items are next, and in order` | `itemsArePastThenNewThenPending` |
| `read states` / `should mark messages as read as they come in` | `updateReadZeroesUnreadAndReturnsTheConvo` |
| `inactivity` / both cases | **not covered** - inactivity policy not ported (see gaps). |

## Test infrastructure

There is no chat service to talk to: `@atproto/dev-env`'s `TestNetwork` serves
no chat, and the repo's `dev-env-mock` is confirmed to serve none either. The
chat suites therefore run against `FakeChatServer` (see
`Tests/MessagesLogicTests/FakeChatServer.swift`), an `HTTPTransport` that routes
every `chat.bsky.convo.*` procedure to in-memory chat state and records each
request's method, params, headers and body.

That placement matters: it sits *below* `LiveChatXrpc`, so the suites exercise
real URL building, param encoding, the `atproto-proxy` header, request bodies and
lexicon decoding — none of which a protocol-level fake under `ChatXrpc` would
reach.
