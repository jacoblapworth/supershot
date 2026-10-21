# Development commands

Run `make` from the repository root to list the common commands. Building and
testing require Xcode 27.2 and the project's supported SDKs. Install xcbeautify and
SwiftFormat with `brew install xcbeautify swiftformat`.

| Command | Purpose |
| --- | --- |
| `make build` | Build the Debug iOS app for a generic simulator, without signing. |
| `make build-macos` | Build the Debug native macOS app, without signing. |
| `make test` | Run all tests in the `Supershot Dev` scheme on an iPhone 18 Pro simulator. |
| `make format` | Format project Swift files using the existing `.swiftformat` configuration. |
| `make lint` | Check formatting without changing files; fail if formatting is needed. |

Builds and tests use `Supershot.xcworkspace` and the committed dependency versions.
Xcode output is formatted with xcbeautify; failed builds and tests still fail the
Make target.
The test destination defaults to the latest installed iOS runtime for an iPhone 18 Pro.
List available simulators with `xcrun simctl list devices available`, then override
the destination when needed:

```sh
make test TEST_DESTINATION='platform=iOS Simulator,id=<simulator-id>'
make test XCODEBUILD_ARGS='-only-testing:ScoringFeatureTests'
make build SCHEME=Supershot CONFIGURATION=Release
```

`WORKSPACE`, `SCHEME`, `CONFIGURATION`, `BUILD_DESTINATION`, `TEST_DESTINATION`,
`MAC_DESTINATION`, `XCODEBUILD`, `XCBEAUTIFY`, and `SWIFTFORMAT` can be overridden on the command
line. Use `XCODEBUILD_ARGS` for extra Xcode options, such as `-derivedDataPath` or a
unique `-resultBundlePath` when collecting test results.

Formatting includes app, widget, shared, and test sources plus the package manifest,
sources, and tests. It excludes dependency checkouts and generated build output.

## CI performance

The iOS test and native macOS build jobs run independently. Both cache Swift
package downloads by Xcode build, runner architecture, and committed lockfiles;
a lockfile change can reuse older downloads while Xcode enforces the new versions.
Both enable Xcode compilation caching and persist its content-addressed cache,
with separate keys for iOS and macOS. Each successful run saves an updated cache
for the next run. Build records and source timestamps are not restored.

The simulator begins booting before cache restoration and compilation. All scheme
tests still run, with the scheme's existing parallelization settings. Raw build
logs include `-showBuildTimingSummary`; compare successful cold and warm CI runs,
including cache restore/save time, to measure the benefit. The first run for a new
Xcode build or runner architecture needs to populate the caches.
