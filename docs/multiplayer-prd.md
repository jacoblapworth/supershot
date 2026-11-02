# Multiplayer and shared games

Status: Product draft, ready for review  
Date: 2 November 2026

## Product direction

Make a Supershot game something people can follow together. An umpire shares a game, an audience follows its progress in the app, and players return to the same game afterwards to review the result and analysis.

The first release is read-only for everyone except the owner. Design the game identity, permissions, and scoring records so that a later release can support multiple umpires keeping independent scores, comparing them, and explicitly reconciling differences.

### Confirmed decisions

- Everyone views games in the Supershot app. A browser scoreboard is outside the first release.
- Viewers do not need an account. The owner signs in to publish and manage sharing.
- Anyone with the viewing link can access the shared game. The owner can revoke or replace the link.
- Sharing and viewing are free initially. Creating and maintaining shares is intended to become a Pro capability later; viewing remains free.
- Live and completed game viewing are the first release priorities.
- Scoring continues offline. Viewers see the last received state with a freshness warning, then catch up when the scorer reconnects.
- Future contributing umpires keep independent scores. Their inputs must not be automatically added together.

### Proposed defaults requiring product review

These make the draft concrete but are not yet confirmed decisions:

- Sharing is off by default and enabled per game.
- A shared game includes the existing play-by-play and team analysis available in the app, with no viewer subscription requirement.
- Exact location, court, division, and scheduled time have a preview before publication. Exact location starts excluded.
- Completed shares remain available until the owner withdraws them, deletes the shared game, or deletes their account. Retention limits and operating costs need review before launch.
- Viewers can save a reference in a “Following” area on their device. This is not a permanent exported copy or cross-device account feature.
- Push notifications, public discovery, and team-wide sharing are deferred.

## Problem and outcomes

Today the active game's scoring and timing commands operate against the local database. Completed games already provide play-by-play and team statistics. The app entry point has sync setup commented out; there is no active multiplayer flow in the inspected app code. This proposal adds shared access without assuming that enabling database sync alone provides publishing, anonymous viewing, permissions, or score reconciliation.

The intended outcomes are:

1. A family member or supporter follows a live score without creating an account.
2. A player opens the same link after the game to see the completed result and analysis.
3. The umpire continues scoring reliably when venue connectivity fails.
4. A later contributor feature can add independent score records without replacing the shared game's identity or invalidating viewing links.

Sharing must never prevent local scoring, timing, or finishing a game.

## People and permissions

| Role | First release | Future contribution release |
| --- | --- | --- |
| Owner | Signs in; owns the game; scores; publishes; manages access; finishes the game | Also invites contributors, selects the published record, and resolves discrepancies |
| Viewer | Opens a link without signing in; follows live or completed game; saves/removes a local reference | Same permissions; cannot become a contributor through a viewing link |
| Contributing umpire | Not available | Accepts a separate invitation after signing in; keeps an independent scoring record; compares records |

The first release has one publishing owner and one active scoring device for each shared game. Opening the game on another device does not silently create a second publisher. Device handoff and owner transfer are deferred; any recovery design must prevent two devices from unintentionally publishing competing records.

Possession of the viewing link grants read access to the selected published information. It never grants score, timer, editing, deletion, or sharing-management permissions. Enforce this outside the viewer UI as well as within it.

## Primary journeys

### 1. Share a game before or during play

1. The owner chooses “Share game” from a planned or active game.
2. If necessary, they sign in. Dismissing sign-in returns to the game without affecting scoring.
3. A preview shows what recipients will see, the permission “Anyone with the link can view,” and optional metadata controls.
4. The owner publishes. Only confirm that sharing is ready after a share and its initial game state are available remotely.
5. The owner sends the viewing link through the system share sheet or displays a QR code containing the same link.
6. The game displays sharing status and offers “Copy link,” “Show QR code,” “Replace link,” and “Stop sharing.”

Allow an already completed game to be published through the same flow. Before a game starts, viewers see its planned details and “Not started”; a scheduled time is not evidence that play has begun.

### 2. Audience follows live

1. A spectator taps the link or scans the QR code.
2. If Supershot is installed, it opens a game preview directly. No sign-in or subscription prompt blocks viewing.
3. The preview shows the teams and status. The spectator can view immediately or save the game to Following.
4. The live view shows team names and colours, score, period, clock state, and available play-by-play and statistics.
5. Updates arrive without manual refresh. A visible “Last updated” indicator explains whether the information is current.
6. On completion, the same screen and link become the completed report.

If the app is not installed, the link opens a minimal installation page. This page contains installation instructions and a way to copy or reopen the original link; it is not a browser scoreboard. The flow must work when a person installs the app and taps the original link again. Automatic restoration of the link after installation is an enhancement, not a launch dependency.

### 3. Player reviews a completed game

A player receives the original game link or a link shared after completion. They open Supershot without signing in and see the final score, period breakdown, play-by-play, and available team analysis. Statistics unavailable from the recorded data remain unavailable; sharing must not imply player-level statistics or player attribution that Supershot does not record.

Completed means the owner explicitly finished the game. A stopped clock, elapsed scheduled duration, or disconnected scorer must not be presented as a final result.

### 4. Scorer loses connection

The owner continues scoring and using the timer locally. Their app distinguishes local changes waiting to publish from changes already published. Viewers retain the last received score, see when it was updated, and are warned that the game may have progressed.

On reconnection, publishing catches up automatically. A game finished offline remains “Awaiting update” to viewers until completion is received. Repeated delivery does not duplicate goals or revert newer state.

### 5. Owner ends access

- **Stop sharing:** withdraw remote viewing access, including existing viewer sessions after their next access check. Preserve the owner's local game.
- **Replace link:** invalidate the old viewing link and access derived from it; issue a new link for the same game. Old viewers must open the replacement link to regain access.
- **Remove from Following:** remove only that viewer's local reference; leave the game and other viewers unaffected.
- **Delete game:** if the game is shared, explain that deletion also withdraws the shared report. An offline deletion queues withdrawal and clearly states that remote access continues until it succeeds.

Link replacement and withdrawal require connectivity and show completion only after remote confirmation. No promise can be made to erase screenshots or data already seen. Cached shared content must stop appearing through ordinary app navigation once withdrawal is known; an offline device may retain its last cached state until it can check access.

## First release requirements

### Shared identity and lifecycle

- One stable shared game identity spans planned, live, and completed states.
- Keep game identity separate from the revocable viewing credential. Replacing a link does not create another game or duplicate a valid saved reference after re-authorisation.
- Sharing an existing local game preserves its goals, period identities, and analysis.
- Viewers receive a published projection of one game, not access to the owner's database, team collection, other games, or account details.
- Shared team names and colours are consistent across the scoreboard, events, and analysis. Later local team edits must not silently rewrite a completed shared report.
- First-release completed reports are read-only. Reopening or correcting a finished game is deferred, consistent with the current command rules rejecting changes to finished games.

### Viewer experience

- Provide clear states for not started, live, paused, break, awaiting update, completed, unavailable, and offline cached view.
- A viewer opening a saved game must have access rechecked when connected. A saved reference is not a permanent access grant.
- Keep followed games distinguishable from games the user owns and can score.
- Show no score, timer, undo, edit, or delete-game controls to viewers.
- Support accessible score announcements without announcing every clock tick. Colour is never the only identifier for a team or connection state.
- Support the app's existing iOS and macOS surfaces. Do not require simultaneous expansion to other platforms.

### Clock and freshness

- Share period identity, running/paused state, and timing anchors so the viewer can render a clock between updates. Do not require a network message every second.
- A locally projected clock is an estimate of the last published state. It cannot establish that a period ended or that the game finished.
- Distinguish loss of the viewer's own connection from lack of updates from the scorer. When the cause is unknown, say “Updates delayed,” not “Scorer offline.”
- Use a heartbeat or equivalent freshness signal so a game with no recent goals is not incorrectly marked stale.
- Proposed launch target: accepted local changes appear to connected foreground viewers within 3 seconds at the 95th percentile under healthy connectivity. Treat this as a target to validate, not a measured capability.
- Proposed freshness behaviour: show an update warning after 15 seconds without a freshness signal during live play. Retain the last published state and mark the clock as potentially inaccurate.
- On foregrounding or reconnecting, refresh access and fetch a consistent latest snapshot before displaying the game as current.

### Publishing reliability

- Publishing is asynchronous and cannot block the scoring transaction or timer controls.
- Persist pending publication across app restart. Show whether the owner's latest changes have reached viewers.
- Give each published change a stable identity and an ordered revision. Retries are idempotent; older revisions cannot overwrite newer state.
- Publish coherent score, event history, period, centre-pass, and lifecycle state. A viewer must not see a score from one revision with analysis from another.
- Permit catch-up through a current snapshot when replaying every intermediate update would be slow. Preserve the full recorded event history for analysis.
- Handle expired owner authentication by continuing local scoring and requesting sign-in to resume publishing. Keep viewers' stale-state messaging truthful.
- Do not promise continuous background broadcasting. Explain when the app must be active to resume updates; automatic period transitions need a defined authoritative publication path.

### Sharing and privacy

- Use separate, unguessable viewing credentials. A game identifier alone is insufficient for access.
- Viewing links are forwardable. Explain this at publication; they do not identify or verify a viewer.
- Anonymous viewers must be able to fetch updates only while their viewing grant remains valid. Knowing a previous content address must not bypass withdrawal.
- Avoid exposing link credentials in analytics, diagnostic logs, or unnecessary link previews. Do not embed private game metadata in the installation page.
- Viewing requires no contact access, email address, or viewer account.
- Changes to shared metadata use the same preview and publication rules. The owner can remove optional metadata already published to connected viewers.
- Account deletion must withdraw the owner's shares. Define remote-data deletion timing before launch.

### Pricing transition

Launch sharing behind a capability policy even while enabled for free. Later Pro eligibility must be checked when creating or maintaining a share without adding a payment requirement for recipients.

Proposed future policy: a subscription expiring during a live game does not interrupt its existing broadcast. Previously shared completed reports remain viewable; starting a new share requires Pro. Grandfathering, renewal checks, and treatment of unstarted shared games require a separate pricing decision before the transition. Do not display these proposed rules as a current customer promise.

## Future: independent umpire contributions

This section defines compatibility requirements, not first-release scope.

### Independent score records

One shared game can have several scoring records. Each belongs to an identified contributor, contains its own scoring events and revisions, and refers to the same game and period identities. The first-release owner record becomes the first of these records; it is not a special data shape that cannot coexist with others.

Two umpires recording the same goal produce observations in separate records. They do not produce two goals in the published total. Never sum contributors' scores, use last-write-wins across their records, or silently edit one umpire's record to match another.

### Invitations and authority

The owner issues a separate, expiring contributor invitation. Acceptance requires sign-in and explicit assignment of contributor rights. A viewing link cannot be upgraded into scoring permission. Revoking contribution rights prevents future publication from that contributor while preserving the provenance of already accepted observations.

Initially, contributors control their own scoring observations. One designated controller owns the shared clock, period transitions, centre-pass reference, and Finish. Independent scoring does not imply competing clocks. Future design must specify how contributors attach observations when they are offline or their period context differs from the controller's.

### Comparison and reconciliation

1. Umpires score independently, including offline.
2. When records are available, compare per-team totals and period totals. Indicate missing or stale records before declaring agreement.
3. Highlight disagreements and provide event timelines to investigate them. Equal totals alone do not prove that the event records agree.
4. The owner reviews and explicitly selects or corrects the published result. Every reconciliation retains the source observations, reviewer identity, and decision history.
5. Viewers see the designated published record or reconciled result. They do not have to choose among umpire records.

Keep separate concepts for **finished**, **records agree**, and **reviewed/reconciled**. Finishing a game does not prove that its umpires agree. The future release may introduce post-game reconciliation even though first-release completed games are immutable.

Unresolved records must never be auto-merged based only on timestamps: different devices can record the same goal at different times. Suggestions may help a person review discrepancies, but acceptance remains explicit.

### Foundations required now

- Separate game, scoring record, publisher, and viewer identities.
- Record event identity and provenance, including stable period attribution.
- Separate viewing grants from contribution and ownership grants.
- Version published state so it can later reference an owner record or a reconciled revision.
- Keep an authoritative command boundary for lifecycle and scoring validation; publishing must not bypass the existing local game rules.
- Avoid building contributor invitations, comparison screens, or a reconciliation engine in the read-only release.

## Scope and delivery

### First release

Owner sign-in; per-game publishing; links and QR codes; account-free app viewing; Following; live score, clock and analysis; completed reports; publication status and catch-up; link withdrawal/replacement; metadata preview; capability policy for future Pro gating.

Build and validate a single owner-to-viewer path first, then complete offline recovery, privacy controls, and platform coverage before release. This is a product sequence, not an implementation plan.

### Later

Independent umpire records, contributor invitations, comparison and reconciliation, device handoff, team or season subscriptions, notifications, and optional exports. Each needs its own scope decision.

### Outside this proposal

Video streaming, chat, reactions, public game discovery, league administration, player rosters and individual player statistics, browser scoreboards, and multiple people editing a single shared scoring record.

## Acceptance scenarios

| Scenario | Required outcome |
| --- | --- |
| Owner declines sign-in or publication fails | Local game remains usable; no false confirmation that a share is ready |
| Anonymous viewer opens a valid link | Correct game opens in the app without sign-in or payment |
| Recipient installs after receiving a link | Tapping the original link after installation opens the intended game |
| Owner shares a planned game | Viewer sees “Not started”; the same link later becomes live and completed |
| Owner records and undoes a goal while connected | Viewer score, play-by-play and analysis converge to one coherent revision |
| A local command is rejected by existing game rules | It does not appear as an accepted change to viewers |
| No goals are scored for several minutes | A healthy freshness signal keeps the broadcast current |
| Owner loses connection, continues scoring, restarts, then reconnects | Local history survives; viewers see delay; publication catches up without duplication |
| Owner finishes offline | Viewers do not infer a final result; they see completion after it publishes |
| Viewer disconnects or backgrounds the app | Cached information is labelled; access and latest state refresh on return |
| Old changes arrive after newer ones | Viewer state does not regress |
| Viewer attempts a write outside the UI | The operation is denied |
| Owner replaces a link | Old link and derived access stop working; new link opens the same game |
| Owner withdraws or deletes a shared game | Connected viewers lose access after confirmation; local owner history follows the chosen action |
| Shared game opens on a second owner device | It does not become a competing publisher |
| Future second record contains the same goals | Published totals are not doubled; original observations remain separate |

## Success measures and launch gates

Measure publication completion, valid-link-to-first-view completion, live update latency, stale-session duration, recovery time after reconnection, and repeat opening of completed reports. Anonymous measurement should use minimal session data; avoid recording viewing credentials or game content.

Evaluate whether sharing brings people back for the completed report and whether owners share another game. Set adoption targets after a pilot establishes a baseline.

Release requires demonstrated permission enforcement, link withdrawal, coherent updates, restart-safe offline catch-up, and successful app-opening flows on supported platforms. Validate the proposed latency and freshness targets in realistic venue conditions and with a provisional load of 100 simultaneous viewers per game. Confirm expected audience size during pilot planning and revise capacity accordingly.

## Remaining decisions

1. Confirm the proposed defaults for shared analysis, metadata visibility, Following, and completed-report retention.
2. Choose owner authentication and account recovery. The first release needs reliable re-entry without broadening into social profiles.
3. Define remote-data deletion timing, viewer cache limits, and behaviour after prolonged owner inactivity.
4. Validate background/foreground publication behaviour and choose infrastructure against these requirements. No backend or sync provider is selected by this PRD.
5. Before contributor work, define reconciliation authority, disputes, offline period mismatch handling, and controller handoff.

## Existing app references

- `SupershotPackage/Sources/GameServices/GameSessionClient.swift` and `docs/game-domains.md`: command validation, atomic local changes, and game lifecycle invariants.
- `SupershotPackage/Sources/GameCore/RecordGoalCommand.swift`: goal identity and expected scoring context.
- `SupershotPackage/Sources/GameAnalysis/GameDetailContentView.swift` and `GameAnalysisControl.swift`: existing report and analysis surfaces.
- `SupershotPackage/Sources/Database/Schema.swift`: existing games, periods, teams, and goals.
- `Supershot/SupershotApp.swift`: database setup and currently commented sync configuration.

This document changes no app behaviour or schema. If implementation changes the database before launch, update the existing single “Create schema” migration directly, in accordance with `AGENTS.md`.
