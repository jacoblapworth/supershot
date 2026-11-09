---
name: project-workflow
description: Coordinates Supershot tasks from Linear refinement through implementation and draft PR handoff. Use when refining project work, starting a task, updating progress, or preparing work for review.
---

# Project workflow

Linear is the source of truth for task scope, ownership, progress, and review links.
Use the connected Linear tools and the Linear skill for service operations. Use
[git-workflow](../git-workflow/SKILL.md) for branch and commit mechanics.

## 1. Refine the task

- Read the supplied issue, its comments, and linked dependencies. Otherwise search the
  Supershot project for an existing match; create an issue in that project if none matches.
  Verify the connected workspace and team before creating or changing records.
- Inspect the relevant code and instructions, then record the problem, intended behavior,
  scope boundaries, checkable acceptance criteria, technical approach, dependencies, and
  validation plan. For visible features, use
  [launch-scenarios](../launch-scenarios/SKILL.md) to choose the initial navigation,
  fixture state, interaction to verify, and focused checks. Preserve existing issue
  content when refining it.
- Ask the user focused questions when unresolved scope or technical choices materially
  change the solution. Record answers in Linear. Proceed with independent investigation
  while waiting; record reasonable assumptions for routine implementation choices.
- Keep refinement in the team's backlog or ready state. Discover the team's actual statuses
  rather than inventing names. Record dependency links when they exist.

Refinement is complete when acceptance criteria and an approach are recorded, and every
material question is answered or explicitly blocks only the dependent work. A refinement-only
request ends with this handoff; implementation starts when requested or already authorized.

## 2. Start implementation

- Assign the issue to Jacob Lapworth when work starts. Resolve his workspace user ID;
  use `me` only after verifying that it identifies Jacob. Retain an existing executing-agent
  delegation, or set the current agent as delegate when its identity and the tools support it.
  Agent delegation can start execution: use only the agent doing this task or a user-requested
  delegate. Fall back to Jacob when agent ownership is unavailable and record that limitation.
- Move the issue to the team's active state, then create the task branch using git-workflow.
  Record the branch, parent, and whether the work is stacked in the issue.

Implementation starts with an owned active issue and an isolated branch from the intended parent.

## 3. Implement and keep Linear current

For visible features, follow [launch-scenarios](../launch-scenarios/SKILL.md) to reuse
or add a repeatable state-driven starting point and validate from it. Record the
working launch recipe and observed behavior with the validation results.

- Make meaningful commits as validated review units become ready, following git-workflow.
- Update the issue at milestones: approach or scope changes, completed acceptance criteria,
  blockers, validation results, and review handoff. Include decisions and evidence, not a
  command transcript. Read current state before changing it so concurrent updates survive.
- For a blocker, record the cause, affected work, and next action. Use a suitable existing
  blocked state if present; otherwise retain the active state and explain the blocker.
  Resume the active state when work resumes. Surface unavailable Linear operations to the user
  and reconcile the missing updates when access returns.

Implementation is ready for review when acceptance criteria are accounted for, applicable
checks have run, and any remaining gaps are explicit.

## 4. Prepare and publish a draft PR

Project implementation work authorizes committing, pushing the task branch, and creating
or updating its draft PR in local and cloud environments. Follow an explicit user request
to keep work local or stop at a plan. Merging, closing PRs, marking them ready for review,
and rewriting published history require separate authorization.

- Use the pull-requests skill for review preparation and the pr skill when writing the body.
  Inspect the full diff against the actual parent, describe the final behavior and validation,
  and link the Linear issue. Use the dependency branch as the base for stacked work.
- For visible changes, capture the running implementation and use GitHub CLI to attach
  screenshots following [SCREENSHOTS.md](SCREENSHOTS.md). Record capture and upload failures
  separately; finish other authorized work.
- Push the task branch and create a draft PR, or update the task's existing PR without
  changing its draft/review state. Verify title, base, diff, draft state, and any image links.
  Attach the PR to the chat when the environment provides an artifact attachment tool.
- Link the PR in Linear and add a concise handoff with completed criteria, checks, gaps,
  and remaining actions. Move to an existing review state when one fits. If the team lacks
  a review state, keep the issue active and state that the draft PR awaits review.

Review handoff is complete when the verified draft PR and Linear issue link to each other,
or a concrete publication blocker and prepared review material are reported. Keep the issue
open through review; move it to Done only after merge and satisfaction of the acceptance criteria,
or an explicit user instruction establishing completion. Check existing automation before
duplicating status changes. Finish with the issue, PR, validation, and unresolved next actions.
