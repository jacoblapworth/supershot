---
name: launch-scenarios
description: Prepare repeatable Supershot UI validation using preconfigured TCA state, navigation stacks, fixture data, and dependencies. Use when implementing visible features, adding debug launch scenarios, or capturing UI evidence.
---

# State-driven launch scenarios

Launch the real app directly into a named scenario using Point-Free's TCA and
Swift Navigation approach: navigation is state. Populate the selected tab, typed
stack paths, presentation state, and child feature state before creating the root
store. Use normal production reducers and views to render and interact with it.

## Choose the starting state

1. Identify the behavior being checked and the nearest useful starting state.
   Reuse an existing scenario or extend one narrowly when implementing a visible
   feature. A documentation-only task needs no app launch or new scenario.
2. Inspect the current launch entry point and feature state declarations. Reuse a
   debug scenario selector if present. When adding one, let launch arguments or
   environment select a named, typed state factory; keep parsing at the composition
   boundary. A scenario name selects state, rather than replaying taps or actions.
3. Model stack navigation with TCA `StackState` and the existing path enum cases;
   model sheets, alerts, and other destinations with the feature's `@Presents`
   state. Populate child state and the selected tab together so the complete route
   is valid. Use the existing Swift Navigation enum/case bindings where applicable.
   Preserve production navigation modeling rather than adding a second router.

Current integration points (inspect before changing):

- `Supershot/SupershotApp.swift` prepares live dependencies and debug example data.
- `SupershotPackage/Sources/AppFeature/SupershotRootView.swift` creates the root store.
- `AppFeature.State` owns `selectedTab`, child features, and its presented destination.
- `GamesFeature.State.path` and `TeamsFeature.State.path` hold typed stacks; their
  presentation properties hold sheets and alerts. Follow their actual declarations.
- `SupershotPackage/Sources/PreviewSupport` provides reusable fixtures and seeding.

Inspect these integration points for existing scenario support before documenting
a runnable launch command; record only commands verified against the implementation.

## Prepare data and dependencies before state

- Gate scenario selection and fixture wiring behind `#if DEBUG` and explicit opt-in.
  A normal launch retains the normal initialization path, including onboarding.
  An unknown requested scenario should produce a clear diagnostic.
- Create an isolated in-memory or temporary database and isolated shared preferences.
  Seed related records before constructing state that fetches or references their
  IDs. Use consistent IDs for fixtures and navigation destinations. Configure the
  dependencies before state initialization, including `@Shared` and `@Fetch` access.
- Reuse fixture builders across previews, tests, and launch scenarios where useful.
  Put feature-specific state factories beside their owning feature; keep shared
  fixtures in PreviewSupport and root composition in AppFeature. Respect package
  dependency direction and access control rather than making internals public.
- Control dates, UUIDs, subscriptions, permissions, and external services through
  existing dependency clients. Use deterministic responses for unrelated effects;
  keep the behavior being tested active. For timers, choose a known time baseline
  and a controllable clock that can advance when validating timing behavior.
- Account for app initialization, `.task`, scene activation, database observation,
  and service responses that could overwrite the prepared state. Install scenario
  dependencies before live bootstrap and root-store creation as needed. Keep the
  store stable across SwiftUI body updates; do not reapply the scenario on each render.
- Scenario setup must leave personal databases, iCloud data, preferences, purchases,
  alarms, and Live Activities untouched. Use isolated stores and controlled clients
  for unrelated side effects; identify integrations requiring a live check.

Completion: selecting the same scenario on a fresh launch reproduces the intended
state without manual setup, and launching without a selector uses normal app behavior.

## Validate from the scenario

Launch into the prerequisites, then perform the interaction under test through the
real UI. For a navigation change, start at its source and exercise the push,
presentation, dismissal, or back action; preloading its destination proves only that
it renders. A screenshot is visual evidence, not proof of persistence, transitions,
or background timing. Verify those behaviors separately when required by the task.

- Run the smallest relevant test target; `test` builds what it needs. Reuse stable
  build caches and simulator destinations per checkout, isolating concurrent writers.
- Save full build/test logs and show concise outcomes or relevant failures. Wait in
  bounded intervals of roughly 30–60 seconds while a long-running check is unchanged.
- After checks pass, repeat only for subsequent edits or unresolved criteria. Use
  CI for broad regression coverage unless shared changes require broader local checks.
- Capture the actual running implementation following the project workflow's
  [screenshot guidance](../project-workflow/SCREENSHOTS.md). Reuse the prepared state
  for repeat captures instead of recreating it through setup screens.
- Record the scenario name, exact working launch command or Xcode scheme settings,
  device, fixture/dependency assumptions, interaction, result, and evidence paths.
  State any live-service or normal-entry-path checks that remain unverified.
- If direct launch is unavailable, report the concrete gap and use the shortest
  existing setup path. Add reusable scenario support when within implementation scope;
  keep unrelated scenario infrastructure out of a narrowly scoped change.

## Point-Free references

Consult the available `pfw-composable-architecture`, `pfw-swift-navigation`, and
`pfw-dependencies` skills when implementing their respective state, navigation, and
dependency code. Check APIs against the project's pinned library versions.

- [TCA documentation](https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/)
- [Swift Navigation](https://github.com/pointfreeco/swift-navigation)
