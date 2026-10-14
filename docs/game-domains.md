# Active game domains

Active-game timing, scoring, centre-pass, court-orientation, and Finish commands pass through `GameSessionClient`. The screen and intents use `GameTimerClient` and `GameScoringClient` as injectable command adapters; screen Finish and Swap sides call the session service directly. Recovery uses the same timer adapter and reconciliation path.

| Boundary | Owns |
| --- | --- |
| `GameTimeline`, `GameCountdown`, `GameTimingState` | Valid schedule, clock projection, start/pause/resume/correction, phase advancement, automatic/manual breaks, ordered transition facts |
| `GameScoringContext`, `ScoringOpportunity`, `GameScoringState` | Live/completed-period attribution, goal construction, centre-pass ownership, confirmation resolution, undo eligibility |
| `GameProgress` | Composition of timing and scoring state; completion/start facts open and close scoring windows and require confirmation |
| `GameSessionTransaction` | Current-state validation, lifecycle and cross-domain gates, atomic persistence, typed command outcomes |
| `GamePresentationClient` | Alarms, subscription gating, and Live Activity effects after commit |
| `ScoringFeature` | Screen state, UI timer ticks, cancellation, sheets, errors, sounds, haptics, and idle-timer lifecycle |

## Command sequence

1. Capture the operation's explicit date and any expected phase/scoring context.
2. Load authoritative game records inside one database write.
3. Reconcile timing when appropriate and apply ordered transition facts to composed progress.
4. Validate current lifecycle, phase, team, scoring context, and confirmation/undo conditions.
5. Delegate to timing/scoring rules, then persist coordinated changes atomically.
6. Return an applied, unchanged, or rejected outcome with the authoritative snapshot.
7. Run presentation work after the transaction returns.

The service retains no mutable game cache. Persisted fields remain on the existing `Game` row and map to separate timing/scoring values; no schema migration is needed. Score totals remain projections of goals.

## Time and rejection semantics

- Goal commands use their captured recording date, including when execution is delayed. They validate the requested live/completed-period context; a stale live goal never becomes a late goal.
- Accepted goal recording samples elapsed time for attribution without persisting incidental ticking progress. Genuine phase transitions are persisted, including when the requested goal is rejected.
- Start, pause, skip, recovery, and Finish reconcile deadlines before validation. A stale/no-op timing command can therefore still persist valid reconciliation.
- Clock correction validates the stored paused phase without reconciling a running clock first.
- Undo, centre-pass selection/confirmation, and court orientation intentionally leave the clock alone.
- Expected rejection is returned from the write as a value. Adapters that surface an error translate it after the transaction commits. Storage errors throw inside the transaction and roll back all changes.

## Cross-domain invariants

Playing-period completion opens a late-scoring window and requires centre-pass confirmation when another period follows. Break completion leaves the next playing period paused. Starting a playing period closes the previous window permanently, even if immediately paused. Late goals retain the completed period's stable identity and full-duration elapsed time (`0:00 remaining`) without altering an active break or pending confirmation. Final expiry permits late goals until explicit Finish; finished games reject further commands.

Live Activity source-specific eligibility remains the separate policy tracked in L-139. This refactor preserves existing behavior.

## Testing

`GameScoringTests`, `GameTimingTests`, `ScoringIsolationTests`, and `GameAdapterTests` run outside the database-backed suite. Pure rules need explicit value inputs only; adapter/reducer tests stub the command boundary. Default test clients report unexpected calls.

The existing `SupershotTestSuite` explicitly opts into live session, timer, scoring, and presentation adapters for persistence/workflow integration. `GameSessionTests` cover reconciliation on rejection, atomic start/window closure, confirmation, break policies, stale undo, finished-game commands, and storage rollback. Existing intent, recovery, timer, scoring, and late-scoring tests verify the shared path. System-service test doubles cannot prove physical-device alarm or Live Activity interactions.
