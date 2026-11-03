---
name: git-workflow
description: Manages project branches, parent relationships, and meaningful commits. Use when starting a branch, committing work, publishing changes, or handing off a stacked branch.
---

# Git workflow

For task ownership and publication authorization, follow [project-workflow](../project-workflow/SKILL.md).
This skill owns Git mechanics; the project workflow owns the task lifecycle.

## Inspect and branch

1. Inspect repository instructions, `git status --short --branch`, remotes, and recent commits.
   Identify existing changes, the trunk branch, and any dependency branch before editing.
2. Preserve pre-existing work. Stage only task files or hunks; use a separate worktree when
   overlapping changes prevent isolation. Leave unrelated changes with their owner.
3. Fetch remote state when available. Create independent work from current `main`;
   create dependent work from its actual feature parent. If fetching fails, record the stale-base risk.
4. Create `codex/<issue-id>-<short-description>` from that explicit parent, or continue the
   existing branch for the same task. Example: `codex/l-169-agent-workflow` from `origin/main`.
5. For Tower metadata or visual Git handoff, read [TOWER.md](TOWER.md).

Branching is complete when the intended parent is recorded in the Linear issue and the
branch diff contains only the task and its declared dependencies.

## Commit as work progresses

Commit each coherent, validated review unit as it becomes ready. Keep associated tests
with the behavior they verify. Separate mechanical changes when that helps review;
keep coupled changes together so intermediate commits remain useful.

Before each commit:

1. Run the narrowest meaningful checks for the change. Record unavailable checks honestly.
2. Inspect the diff and stage explicit files or hunks.
3. Inspect `git diff --cached` for unrelated changes and sensitive data.
4. Commit using Conventional Commits, with an imperative summary and optional scope.
   Example: `docs(workflow): define Linear task handoffs`. Add a body for non-obvious reasons.
   Keep commit authorship factual; omit AI attribution unless explicitly required.

A commit is complete when its staged diff matches its stated purpose and validation is recorded.

## Preserve history

Amend a small correction into the latest unpublished commit when it belongs to that review unit.
Use another meaningful commit for published changes. Obtain explicit authorization before
rewriting published or shared history, force-pushing, or restacking published descendants.
Keep pre-existing changes intact; destructive cleanup requires explicit authorization.

## Publish and verify

Publish under the project workflow's authorization. Push only the task branch with an
explicit remote and branch, such as `git push -u origin codex/l-169-agent-workflow`.
Preserve repository protections and report authentication or policy failures.

Set the PR base to the actual parent:

```text
Independent: codex/l-169-agent-workflow -> main
Dependent:   codex/l-171-filters -> codex/l-170-search
```

Explain stacked dependencies in the PR. If a parent merges, inspect how it merged and
the resulting diff before changing the child's base; get authorization if restacking rewrites history.

Before handoff, inspect status, commits since the parent, and the full PR diff. Confirm
the remote task branch contains the intended commits, the base is correct, and all
remaining local changes have an identified owner. Report the branch, parent, PR,
validation, and any unresolved publication or Tower metadata step.
