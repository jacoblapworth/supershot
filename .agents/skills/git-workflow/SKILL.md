---
name: git-workflow
description: Instructions for using git to manage version control
---

# Git workflow

Use Git deliberately so that repository history explains the implementation and helps a reviewer understand the change.

Prefer small, coherent branches and logical commits over a single end-of-task commit.

## Principles

- Preserve existing work.
- Start from the correct parent branch.
- Commit proactively as logical units of work are completed.
- Make every commit useful to a future reviewer.
- Follow existing repository conventions when they conflict with defaults in this skill.
- Use Conventional Commits unless the repository specifies another format.
- Never add AI or agent attribution to commits unless the repository explicitly requires it.
- Treat rewriting published history as destructive.
- Keep unrelated changes out of the current task.

## Before changing anything

Inspect the repository before editing:

```sh
git status --short --branch
git branch --show-current
git remote -v
git log -10 --oneline
```

Also inspect relevant repository instructions such as:

```text
AGENTS.md
CONTRIBUTING.md
README.md
```

Determine:

1. the current branch;
2. whether the working tree already contains changes;
3. the repository's main/trunk branch;
4. existing branch naming conventions;
5. existing commit-message conventions;
6. whether the requested work depends on another feature branch.

Do not assume the current branch is the correct branch to build from.

Do not discard, overwrite, reset, clean, stash, or incorporate pre-existing user changes unless explicitly required.

If unrelated changes already exist, work around them and stage only files or hunks belonging to the current task.

## Choose the parent branch

The parent is the branch the new work logically depends on.

For an independent feature:

```text
main
└── feature/new-work
```

Use `main` as the parent unless the repository uses a different trunk branch.

For dependent work:

```text
main
└── feature/profile
    └── feature/profile-notes
```

`feature/profile-notes` has `feature/profile` as its parent because it depends on code introduced there.

Do not set `main` as the parent merely because it is the repository's trunk branch.

### Creating the branch

Where practical, fetch remote state before branching:

```sh
git fetch --prune
```

Create the branch directly from its intended parent:

```sh
git switch -c <new-branch> <parent-branch>
```

Do not create a branch from the current `HEAD` and later assume its parent.

Follow existing branch naming conventions. If none exist, prefer concise names such as:

```text
feat/profile-notes
fix/avatar-upload
refactor/image-pipeline
chore/update-dependencies
```

## Tower parent branches

The user uses Tower as the primary graphical Git client.

Tower 18's `gittower` CLI can record parent and stacked-branch metadata.

When `gittower` is available locally, record the parent immediately after creating a branch:

```sh
gittower branch parent <branch> --set <parent>
```

For example:

```sh
gittower branch parent feat/profile-notes --set feat/profile
```

Verify it when useful:

```sh
gittower branch parent <branch>
```

### Stacked branches

A branch having a parent does **not** automatically make it a stacked branch.

Only enable Tower's stacked-branch behaviour when the branch intentionally forms part of a stack:

```sh
gittower branch stacked <branch> --set
```

A branch must have a parent before it can be marked as stacked.

For a normal feature created directly from `main`, record its parent but do not mark it stacked unless the workflow actually requires stacking.

Example:

```sh
gittower branch parent feat/search --set main
```

For dependent work:

```sh
gittower branch parent feat/search-filters --set feat/search
gittower branch stacked feat/search-filters --set
```

Do not use `git config` directly to manipulate Tower's metadata when `gittower` is available.

### Cloud environments

Tower stores branch-parent and stacking information in the repository's local Git configuration. This metadata is not committed and does not travel when a branch is pushed.

Therefore, in a cloud environment:

1. create the branch from the correct Git parent;
2. do not treat inability to run `gittower` as an error;
3. remember the intended Tower parent;
4. report it in the final handoff.

Use wording such as:

```text
Tower parent: feat/profile
Stacked: yes
```

The user's local environment can then apply:

```sh
gittower branch parent <branch> --set <parent>
gittower branch stacked <branch> --set
```

Do not add files to the repository solely to persist Tower's local branch metadata.

## Make commits proactively

Do not wait until the entire task is complete before considering commits.

Create a commit whenever a coherent implementation step is complete and validated.

A useful commit should generally:

- have one primary purpose;
- be understandable without later commits;
- be independently reviewable;
- leave the repository in a valid state where practical;
- contain tests associated with the behaviour it introduces;
- be reasonably safe to revert independently.

Think in terms of **review units**, not number of files or number of lines.

### Good sequence

```text
refactor(profile): extract notes persistence
feat(profile): support notes on favourited profiles
test(profile): cover note validation edge cases
docs(profile): document notes behaviour
```

This tells a reviewer how the implementation evolved.

Another valid sequence might be:

```text
refactor(upload): isolate image encoding
fix(upload): preserve jpeg content type
test(upload): cover multipart jpeg uploads
```

### Avoid

```text
chore: changes
update files
wip
fix stuff
feat: task
```

Also avoid one giant commit containing:

- unrelated cleanup;
- mechanical renames;
- behaviour changes;
- dependency upgrades;
- tests for unrelated functionality.

Separate mechanical refactors from behavioural changes when doing so makes the diff easier to review.

Do not split changes artificially if that would produce broken or meaningless intermediate commits.

## Staging

Review what is about to be committed.

Use:

```sh
git status --short
git diff
git diff --cached
```

Prefer explicit staging:

```sh
git add path/to/file
```

or hunk-based staging when a file contains unrelated changes:

```sh
git add -p path/to/file
```

Avoid blindly running:

```sh
git add .
git add -A
```

when the working tree contains pre-existing or unrelated changes.

Never commit files merely because they happen to be modified.

## Commit messages

Use Conventional Commits:

```text
<type>(<scope>): <summary>
```

The scope is optional.

Common types:

- `feat` — new user-visible or developer-facing functionality
- `fix` — bug fix
- `refactor` — restructuring without intentional behaviour change
- `perf` — performance improvement
- `test` — tests only
- `docs` — documentation only
- `build` — build system or dependency changes
- `ci` — CI configuration
- `chore` — maintenance that does not fit another type
- `style` — formatting or stylistic code changes without behaviour changes

Examples:

```text
feat(profile): add private notes
fix(upload): preserve jpeg mime type
refactor(games): move tab state into GamesHome
test(auth): cover expired session refresh
chore(deps): update swift dependencies
```

### Subject rules

Prefer:

- imperative phrasing;
- lowercase after the colon;
- concise descriptions;
- the actual change rather than the activity performed.

Good:

```text
feat(profile): support editable notes
```

Less useful:

```text
feat(profile): added editable notes
```

Do not include phrases such as:

```text
generated by AI
created with Codex
co-authored-by AI
agent changes
```

unless specifically required.

### Commit bodies

Add a body when the reason, constraint, trade-off, or non-obvious behaviour will help a reviewer.

Explain **why**, not a prose repetition of the diff.

Example:

```text
fix(upload): preserve jpeg content type

Forward the original media type rather than inferring it from the
temporary filename because uploaded files may not retain an extension.
```

### Breaking changes

Use Conventional Commit breaking-change syntax when appropriate:

```text
feat(api)!: remove legacy profile endpoint
```

and describe migration requirements in the body/footer.

## Validation before each commit

Run the narrowest useful validation for the change.

Examples include:

```text
unit tests
type checking
linting
format validation
build
targeted integration tests
```

Prefer targeted checks while iterating and the repository's expected full validation before finishing.

Do not claim a check passed unless it was actually run.

If validation cannot be run, state that explicitly.

## Amending commits

Amend the most recent local commit when a small correction clearly belongs to that same logical change and the commit has not been published.

Otherwise, create another logical commit.

Do not routinely squash everything at the end. The goal is a useful review history, not the smallest possible number of commits.

Do not rewrite commits already pushed or used as a parent by other work unless explicitly asked.

## Rebasing and history rewriting

Do not automatically:

- rebase published branches;
- force-push;
- squash published commits;
- rewrite another contributor's commits;
- reset shared branches.

A local, unpublished branch may be rebased onto its parent when necessary and when doing so cannot destroy someone else's work.

For stacked work, remember that rewriting a parent can invalidate descendants. Treat restacking as an explicit history operation rather than routine cleanup.

## Pushing

### Local environments

Do not push unless the user explicitly asks.

Local agents may:

- create branches;
- stage changes;
- create commits;
- set Tower parent information;
- inspect remote state with fetch.

### Cloud environments

A cloud agent may push the branch it created for its own task after the work has been validated.

Push only the working branch:

```sh
git push -u origin <branch>
```

Never push directly to `main`, `master`, another trunk branch, or an unrelated contributor branch.

Do not force-push unless explicitly instructed.

Do not push unrelated local branches or tags.

If authentication or repository policy rejects the push, report the failure rather than weakening repository protections.

## Pull requests

Do not create, merge, close, or materially update a pull request unless explicitly requested.

When asked to create a PR, use the branch's actual parent as the PR base.

For a normal feature:

```text
main ← feat/search
```

PR:

```text
feat/search → main
```

For a stack:

```text
main
└── feat/search
    └── feat/search-filters
```

PRs:

```text
feat/search → main
feat/search-filters → feat/search
```

Do not target `main` for every PR in a stack.

Describe the dependency in the PR when it is not obvious.

## Reviewing with Tower

When running locally and `gittower` is available, use Tower as the preferred visual handoff for Git review.

Useful Tower 18 commands include:

```sh
gittower working-copy
gittower history
gittower history <branch>
gittower commit <revision>
gittower blame <file>
gittower branches-review --branch <branch> --base <parent>
gittower pull-requests
```

`gittower` is a Tower launcher and branch-metadata interface. It is not a replacement for Git itself.

Use normal `git` commands for staging, commits, branch creation, fetching, and pushing.

After making uncommitted changes, `gittower working-copy` is useful when the user wants to inspect the diff visually.

After creating logical commits, prefer:

```sh
gittower history <branch>
```

or:

```sh
gittower branches-review --branch <branch> --base <parent>
```

so the user can review the branch in its correct context.

Do not fail a task because Tower or `gittower` is unavailable.

## Completion check

Before declaring Git work complete, inspect:

```sh
git status --short --branch
git log --oneline <parent>..HEAD
```

Where useful:

```sh
git diff <parent>...HEAD
```

Confirm:

- the branch was created from the intended parent;
- Tower parent metadata was set locally when possible;
- stacking is enabled only when intentional;
- no unrelated changes were committed;
- logical work was committed proactively;
- commit messages follow Conventional Commits;
- validation was performed;
- the working tree contains no unexplained task changes;
- cloud work was pushed only to its own branch;
- no protected or shared history was rewritten.

## Final handoff

Report concisely:

```text
Branch: feat/profile-notes
Parent: feat/profile
Tower parent: feat/profile
Stacked: yes

Commits:
- refactor(profile): extract notes persistence
- feat(profile): add notes to favourited profiles
- test(profile): cover profile note validation

Validation:
- pnpm test profile
- pnpm typecheck

Push:
- origin/feat/profile-notes
```

Omit fields that do not apply.

Mention any remaining uncommitted user changes separately so they are not mistaken for part of the task.
