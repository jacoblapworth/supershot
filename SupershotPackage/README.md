# Supershot packages

Open **SupershotWorkspace.xcworkspace**, rather than the Xcode project, for app development.
The workspace connects the executable targets to this local package. Use the existing
`Supershot Dev` scheme for Debug builds and tests, and `Supershot` for Release builds.

The layout follows [isowords](https://github.com/pointfreeco/isowords): one package,
explicit target dependencies, and independently buildable features. The package preserves
the application's Swift 5 language mode, MainActor default isolation, approachable
concurrency settings, and iOS/macOS 27 deployment targets. Dependencies are pinned to the
versions used before extraction; update them deliberately in a separate change.

## Boundaries

- `SharedModels` contains lightweight values shared by the app and widgets.
- `WidgetSupport` contains the shared avatar, phase label and colour helpers. Widgets
  depend only on these two targets, without persistence, RevenueCat or TCA.
- `GameCore` owns persisted table models and pure timing/scoring rules.
- `Database` owns bootstrap, the single schema migration, query projections and export.
  Query results carry stored colour strings; `Styleguide` converts them to SwiftUI colours.
- `GameServices` owns transactional commands and their post-commit presentation effects.
- `AlarmClient`, `SubscriptionClient`, `LocationClient` and `SoundEffectsClient` own
  dependency clients. `AppSettings` owns the existing shared preference keys.
- `Styleguide` owns reusable controls and model colour presentation. `GameAnalysis`
  owns the analysis UI shared by live and completed games.
- `TeamEditingFeature` owns the reusable editor and picker, independently of Teams
  navigation. `NewGameFeature` can use it without importing `TeamsFeature`.
- Feature targets own their reducer, views and feature-specific preview scenarios.
  `GamesFeature` and `TeamsFeature` compose navigation; `AppFeature` composes the app.
- `PreviewSupport` contains shared fixtures and debug seeding, without importing features.
  `TestSupport` contains shared test helpers and is linked only by tests.

Prefer `package` access for collaboration inside this package. Use `public` for entry
points and values required by the app, widget or host tests. Keep implementation details
private and declare direct dependencies explicitly in `Package.swift`.

## Executable responsibilities

Xcode owns signing, capabilities, entitlements, icons, launch screen, app configuration,
widget entry points and App Intent declarations. The app configures RevenueCat and the
database, installs its live `AlarmClient`, and displays `SupershotRootView`.

The live alarm adapter stays in the app because it constructs `OpenGameIntent`. Package
services depend on the alarm interface; the adapter does not introduce a dependency back
from the package to the app. Intent declarations retain their existing app/widget
compilation conditions and execution targets.

The goal sound belongs to `SoundEffectsClient` and is loaded from `Bundle.module`.
App configuration continues to use `Bundle.main`. Database locations, preference keys,
URL schemes, bundle identifiers and schema SQL are unchanged.

## Testing and previews

The app schemes include the package test targets and the remaining app-hosted intent
suites. The Xcode test target compiles `TestSupport/DatabaseTestHelpers.swift` directly
to share helpers without linking a second copy of the app dependency graph. Each package test target retains its serialized suite and fresh dependency-backed
database setup. App Intent and Live Activity intent tests remain in `SupershotTests`.

For a full iOS test run, choose an installed simulator in Xcode and use Product > Test,
or replace `<simulator-id>` in:

```sh
xcodebuild -workspace SupershotWorkspace.xcworkspace \
  -scheme 'Supershot Dev' -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-id>' test
```

Use `-only-testing:ScoringFeatureTests` (or another package test target) for a focused run.
Package feature schemes can be built independently from the workspace, and their
`#Preview` declarations use the same reducers and scenario fixtures as before extraction.
Use Xcode for iOS testing; plain `swift test` runs against the host platform.

## Pull request CI

GitHub Actions runs every test enabled in the `Supershot Dev` scheme, including the
package suites and app-hosted App Intent/Live Activity suites. The workflow uses one
`xcode-27` macOS runner with Xcode 27.2 and an iPhone 17 simulator on iOS 27.0.
It runs when a pull request is opened, updated or reopened, and can also be started
manually from Actions. New runs cancel older runs for the same pull request.

CI caches package downloads using the runner architecture, Xcode version and committed
dependency lockfiles. Dependency versions remain pinned. Each run has a 45-minute
timeout and uploads its build log and `.xcresult` bundle for seven days, including
when tests fail.

To run the equivalent suite locally, select Xcode 27.2, use `xcrun simctl list devices
available` to find an iPhone simulator UUID, and run:

```sh
set -o pipefail
xcodebuild test \
  -workspace SupershotWorkspace.xcworkspace \
  -scheme 'Supershot Dev' -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-id>' \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipMacroValidation \
  -resultBundlePath /tmp/Supershot-CI-Tests.xcresult \
  2>&1 | tee /tmp/Supershot-CI-Tests.log
```

Run from the repository root and choose a new result-bundle path for each run.
CI specifically requires iOS 27.0; a newer installed iOS runtime can be used locally.

## Schema changes

The app has not shipped. Edit the single `Create schema` migration in
`Sources/Database/Schema.swift`; do not add incremental migrations or migration tests.
