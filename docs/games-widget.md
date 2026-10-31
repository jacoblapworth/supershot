# Home Screen games widget

The first version selects games automatically. A completed game remains eligible for
seven rolling days after `endedAt`. Undated planned games are the final fallback.

Selection groups, in order:

1. Planned games scheduled in the future or overdue by **at most** 24 hours,
   scheduled time ascending.
2. Games in progress, start time ascending.
3. Completed games within seven days, completion time descending.
4. Planned games overdue by more than 24 hours, scheduled time ascending.
5. Undated planned games, creation time ascending.

Every group breaks ties by UUID ascending. Scheduling never changes persisted status.
At exactly 24 hours a plan remains in the first group. Timeline entries move it into
the older overdue group on the following second. Completed history expires the same
way. The provider precomputes up to 64 transitions and requests a continuation at the
last entry. With no pending transitions it requests a timeline after an hour.
WidgetKit controls actual delivery times; scores are snapshots, not continuously live.

## Layout

`GameCardView` in UI is shared with the app's games list. It preserves bib
colour gradients, initials, team names, compressed score hierarchy, period/final/planned
status and localised date/time. Planned games have no score. Completed losing scores
use secondary emphasis. VoiceOver reads each card as one result or scheduled fixture.

- Small: one game, stacked team identities with a vertical team-colour gradient,
  two-line names, and date/status/court metadata between the teams.
- Medium: up to two complete compact cards.
- Large: up to four complete compact cards.
- Extra-large on iPad: up to eight cards in two columns.

The larger families calculate capacity from available height, reserving at least 72
points per row, scaled with Dynamic Type. Tight sizes show fewer rows. The small
card caps visual text scaling at the default large size to fit the fixed widget
bounds; VoiceOver still reads the full names, scores, schedule and status.
The system handles full-colour, dark and tinted rendering. No timer controls are added
to the Home Screen widget; the existing Live Activity remains a separate widget.

## Data and navigation

The app retains `GamesWidgetObservation` for its process lifetime. GRDB observes the
same `GamesRequest` used by the list, including game, team, period and goal records.
It removes duplicate projections (so timer ticks alone do not request reloads), writes
an atomic JSON snapshot to an App Group container and then requests a games timeline
reload. This covers writes from every feature and any sync engine using that database.
The widget only reads this projection; it never opens or migrates the database.

Development and Release use separate App Groups and URL schemes. Both app and widget
entitlements must be provisioned for their configured `GAMES_WIDGET_APP_GROUP`:
`group.nz.lapworth.Supershot.dev` and `group.nz.lapworth.Supershot`.

Each card links to `game/<UUID>`. Navigation fetches the current persisted game,
then opens setup, scoring or analysis. Reused warm-app routes also check persisted
status first. Missing games show the existing unavailable alert. Empty/unavailable
snapshots link to `new-game`; onboarding queues this link until welcome completes.
A failed read shows an explicit open-app message, rather than pretending there are
no saved games. Widget snapshots are first populated when the app is launched.

## Verification

Automated coverage includes group ordering, UUID ties, the exact 24-hour boundary
and either side, time-based reordering, seven-day expiry, atomic snapshot round trips,
committed creation/team edits/scores/completion/deletion, stale-widget navigation and
new-game navigation through onboarding. The projection observer tests use real database
commits and verify the reload callback sees the already-written snapshot.

Before release, use Xcode on iPhone and iPad to check all families in the actual widget
host, tinted appearance, accessibility text sizes, localisation, cold and warm URL
launches, deletion while a widget is visible, and signed App Group access. Also check
the existing Live Activity's timer and scoring controls. SDK type-checking and card
image rendering do not replace these device checks.
