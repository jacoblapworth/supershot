# Game parser (L-151)

`GameParser` is a package-scoped, injectable service, available through
`@Dependency(\.gameParser)`. `parse(_:context:)` returns ordered transient
`FixtureDraft` values. There are no database dependencies, writes, team identities,
game settings, inferred time zones, or clock/lifecycle effects.

The live implementation explicitly uses Apple's on-device
`SystemLanguageModel.default`, a fresh session per request, and guided `@Generable`
output for natural-language descriptions. Explicit time-prefixed matchup rows
(such as `19:10  The lodgers vs IMG & Friends`) use a deterministic extractor
before model availability is checked. It preserves whitespace, punctuation and
ampersands, and only handles an input when every nonempty line matches. Additional
metadata or ambiguous separators fall back to the model. Tests inject `ExtractedFixture`
responses at the generation boundary, so source grounding, ordering and validation
still run. No test requires Apple Intelligence.

## Contract

- Input is limited to 6,000 UTF-8 bytes, output to 12 fixtures and 3,000 generation
  tokens. An over-limit list must be split; nothing is persisted or partially imported.
- Team names, metadata and source excerpts must appear verbatim in the source.
  Ungrounded field values are removed and flagged. Invalid source excerpts fail the
  request. Non-overlapping source excerpts determine ordering and one-based source
  line numbers, including repeated fixtures.
- Missing team names and equal names (case/outer-whitespace insensitive) are flagged.
  Incomplete rows remain drafts with their source and validation issues for correction.
- Supported date components are unambiguous Gregorian `YYYY-MM-DD` dates, plus
  `today`, `tomorrow`, `yesterday` and weekday names (including `next Friday`)
  resolved using a caller-supplied calendar, reference date and time zone. Other date text stays available with an issue for
  later correction. No context is taken implicitly from the system clock or zone.
- Supported time components include 24-hour `H:mm` / `HH:mm` and 12-hour
  times such as `7pm` and `7:30 PM`. Invalid or unsupported
  time text remains available with a validation issue. Time-only fixtures have no
  date or zone. A valid clock time duplicated into the model's date slot is discarded.
- Date and time validity are checked independently. Invalid dates cannot silently
  roll into a different month. Draft components do not imply a scheduled instant.
- Empty/irrelevant input, unavailable model, unsupported input/refusal, generation
  failure, cancellation and input/output limits have explicit actionable errors.
  The pasted text is supplied as extraction data, separate from session instructions.
- Extraction is probabilistic: source grounding prevents invented field values but
  cannot prove that the model included every fixture or assigned every field correctly.
  New Game applies the resolved values automatically and lets users correct them
  in the setup controls before starting or saving.

## New Game integration

`DescribeGameFeature` parses immediately after the paste action and after a 500 ms
pause while typing. It populates teams and metadata directly; the highest-ranked
saved-team candidate is used automatically, and unmatched names become in-memory
teams with random colours. The existing team cards open the team picker and
configuration flow for corrections. Proposed teams seed the picker and its
Create new team editor with the parsed name and colour, without a separate
confirmation step before starting or saving the game.

Once there is text, the input replaces Paste with Clear. Clearing removes the
teams, schedule, court and division populated by the description. Manually set
fields that the parser never populated are preserved. Request revisions prevent
late parsing results from refilling the setup after clearing or changing the text.

Typing, parsing and closing this implicit setup do not create teams or games.
The existing Start or Save action writes any proposed teams and the game together
in one transaction. A failed write rolls everything back.

## Development harness

Open `Supershot.xcworkspace`, select the shared **GameParser** scheme
and **My Mac**, then Run. The command-line harness prints availability, elapsed
wall-clock time and the drafts/errors for both the single matchup and the complete
six-fixture parent sample. Its `--stdin` argument accepts another pasted text fixture.
It is also runnable with `swift run --package-path SupershotPackage GameParserHarness`.

For an eligible iOS development host, depend on the `GameParser` target and call
`await GameParserDevelopmentHarness.run()` from that package's development code.
It returns a typed report and does not require a production screen. The harness is
not linked into the production app. Run on physical hardware with Apple Intelligence
enabled and model assets ready; simulator tests do not establish inference quality.

Focused deterministic tests:

```sh
xcodebuild test -workspace Supershot.xcworkspace \
  -scheme GameParser -configuration Debug \
  -destination 'platform=macOS' -skipMacroValidation
```

`GameParserTests` is also registered with both existing app test schemes for CI.

## Evidence

On 19 October 2026, the final focused macOS Debug run passed all 21 test cases
(including parameterized invalid dates/times). These use stubbed generation and
verify validation, source ordering, punctuation, partial rows, limits, dependency
injection and cancellation. The same 21 cases also passed through the **Supershot Dev**
Debug app scheme on the iPhone 17 / iOS 27.2 simulator (zero failures or skips).
These tests do not establish live inference quality.

Separately, the live harness ran on the development Mac running macOS 27.2
(26B5112a), built with Xcode 27.2 (27B5028f). Model availability was `available`.
The final single-matchup run took **2.714 seconds** and returned the exact two names,
no date/time/metadata and no issues. The final six-fixture run took **8.909 seconds**:

| First team | Second team | Time | Division | Court |
| --- | --- | --- | --- | --- |
| Coles Hot Chooks | IMG & Friends | 18:30 | Division 1 | Court 1 |
| Mixed Bag | Buzz Ballers | 19:10 | Division 1 | Court 1 |
| Buzz Ballers | Clapham Ballers | 19:50 | Division 1 | Court 1 |
| Pole vaulters | Silence of the Lambeths | 18:30 | Division 2 | Court 2 |
| The lodgers | Netball & Chill | 19:10 | Division 2 | Court 2 |
| Netball & Chill | One Team, One Dream | 19:50 | Division 2 | Court 2 |

All six retained exact source excerpts in order, dates/date text were absent, and
there were no validation issues. An earlier live run exposed clock times being
repeated into the date slot; that observation led to the clock/date regression test
and independent validation fix. The single final run above is an observation, not a
benchmark or a guarantee across devices/models. Physical iPhone inference has not
been measured. The service adds no production UI.

Apple API references: [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel),
[generation and availability](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).
