# Fixture team resolution (L-152)

`FixtureTeamResolution` is a pure package target depending on `FixtureParser`,
`GameCore` and Ordo One's `FuzzyMatch` **1.4.0**. It has no database client and
never creates teams or games. Review UI and transactional import remain the
responsibility of L-153/L-154/L-155.

## Matching and tie rules

`FixtureTeamResolver(teams:)` captures a saved-team snapshot. `resolve(_:)` returns
an explicit `unique`, `ambiguous` or `unmatched` result.

1. Comparison keys collapse Unicode whitespace (including line breaks) to one
   space and fold case and diacritics with the fixed `en_US_POSIX` locale. Original
   names remain available for display. Punctuation is preserved: `&`, commas,
   apostrophes and hyphens are significant for exact identity.
2. Normalized exact candidates rank before all fuzzy candidates, regardless of
   fuzzy score. Exactly one exact candidate produces `unique` and may be selected
   automatically. Duplicate exact saved names remain ambiguous, even if their
   original spellings differ in case or accents.
3. Other candidates use FuzzyMatch's default Damerau-Levenshtein matching
   configuration with a minimum score of **0.7**. The extracted name is the query;
   the saved name is the candidate. Prefix, substring, subsequence and acronym
   behavior follows the pinned library configuration. The score is a ranking
   value, not a probability of identity or model confidence.
4. Fuzzy candidates rank by descending score, then normalized name ascending,
   then UUID string ascending. Equal scores are never broken into an automatic
   selection. Even one fuzzy candidate returns `ambiguous`, requiring review.
   No candidate produces `unmatched`, which proposes a new team.

## Batch review contract

Create `FixtureTeamReview(fixtures:savedTeams:)` from parsed drafts and one saved
snapshot. `references` links each fixture side to an `entries` comparison key.
Entries appear in first-occurrence order and preserve that occurrence's display
name. Repeated normalized names share one entry and selection, so Buzz Ballers
and Netball & Chill in the parent sample each yield one proposed identity.
Different keys never merge because of fuzzy similarity.

Unique exact entries select `.existing(id)`; unmatched entries select `.proposed`;
ambiguous entries have no selection. These choices remain transient. Confirmation
belongs to the caller, even when every entry has a default selection.

- `select(_:for:)` applies a reviewed choice to every occurrence of that key. It
  accepts any team from the saved snapshot, allowing manual correction outside
  the fuzzy suggestions. Unknown IDs and references are rejected.
- `editName(_:fixture:side:)` changes one occurrence, recomputes its matching entry
  and clears its selection, including edits that only change case/spacing. Other
  old-name references remain intact. If the edit joins another existing entry,
  that shared entry's choice is cleared for review. Unreferenced entries are removed.
- `validatedTeams(currentTeams:)` rejects missing names, unresolved selections,
  vanished saved IDs, renamed saved identities, and the same saved ID or proposed
  key on both sides. A color-only saved-team change does not invalidate identity.
  It returns existing IDs or shared proposal keys, never newly allocated team IDs.

The eventual commit command must call `validatedTeams` using a fresh saved-team
snapshot **inside its write transaction before performing writes**. Allocate one
new team ID per referenced proposal key, using the entry's display name, then use
that mapping for all fixtures in the transaction. Do not invoke `TeamEditorFeature`
while reviewing: it saves immediately. This issue supplies validation for that
future command, not an import persistence implementation.

Team validation is independent of extraction/metadata validation; callers must
also resolve the appropriate `FixtureDraft.issues`, schedule context and other
required game settings before import.

## Validation

`FixtureTeamResolutionTests` covers normalized exact variants, punctuation,
rank order, duplicate exact names, tied fuzzy scores, snapshot-order independence,
fuzzy review, unmatched names, shared batch proposals/selections, edit invalidation,
missing names, same-team conflicts and stale saved identities. It is registered
with both app schemes and the focused `FixtureParser` scheme.

```sh
xcodebuild test -workspace Supershot.xcworkspace -scheme FixtureParser \
  -destination 'platform=macOS' -skipMacroValidation \
  -only-testing:FixtureTeamResolutionTests
```

On 27 October 2026, all 12 tests (including four parameterized exact-name cases)
passed on macOS in an isolated Swift package using these repository sources,
FuzzyMatch 1.4.0 sources retrieved through the GitHub connector, and the cached
package dependencies. SwiftFormat and manifest validation also passed. The normal
Xcode workspace invocation was blocked by sandbox/workspace and simulator-service
access errors, so app-scheme integration has not been verified in this environment.
