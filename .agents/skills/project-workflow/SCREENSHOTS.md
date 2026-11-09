# Screenshot evidence for PRs

Capture and upload are separate capabilities. A local screenshot is evidence in the chat;
GitHub needs an uploaded image URL accessible to reviewers to render it in a PR.

## Capture the implementation

Use device-interaction for app verification and the available simulator or device tools.
Prepare the starting state using [launch-scenarios](../launch-scenarios/SKILL.md),
then exercise the changed interaction before capture. Record the scenario and launch
recipe with the evidence so another agent can reproduce it.
Capture the changed workflow with representative data, inspect each image, and label the
state it demonstrates. Include before/after evidence when useful and safe to obtain.
Exclude private information. Save durable local artifacts and show them in the handoff.
For a capture failure, name the exact environment or interaction blocker and the unverified behavior.

## Upload with GitHub CLI

Use `gh` to upload screenshots directly to GitHub and embed them in the PR description.
The GitHub connector can handle other PR operations; screenshot uploads use the CLI.

1. Check `gh --version`, `gh pr create --help`, and `gh pr edit --help` for `--attach`.
   If the installed CLI lacks the flag, use a newer approved installation when available.
   Otherwise report the installed version and missing flag as the upload blocker, retain
   the images for attachment after the CLI is updated, and complete other authorized PR work.
2. Attach screenshots when creating the draft PR:

   ```sh
   gh pr create --draft --base <parent> --head <branch> \
     --title '<title>' --body-file <body-file> \
     --attach '/absolute/path/after.png#Updated game screen'
   ```

   For an existing PR, preserve its description and append the screenshot:

   ```sh
   gh pr edit <pr-url> --attach '/absolute/path/after.png#Updated game screen'
   ```

   Repeat `--attach` for multiple images. For specific placement, reference the same local
   image in the body file and pass it with `--attach`; the CLI replaces that reference with
   the uploaded URL. Use captions that explain each state.
3. Verify the upload result.
   Uploading requires push access and compatible authentication. On failure, report the
   exact error without exposing credentials. Check whether the PR or some uploads succeeded
   before retrying, because partial success can still produce a nonzero command result.
   If upload remains blocked, show the local images in the handoff and explicitly mark
   the PR screenshot evidence as pending. Keep publication scoped to this PR; obtain
   authorization before introducing another host or committing images solely for hosting.

After upload, read back the PR body and inspect the resulting rendered images when possible.
Record any remaining inability to verify reviewer access. Local paths and chat attachment
references must be replaced with the actual uploaded URLs in a published PR.

## Capability references

Check installed tools rather than assuming the latest online documentation matches them.
Treat these as lookup references, not a reason to skip capability detection:

- [GitHub: attaching files with the CLI](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli)
- [GitHub CLI: creating PRs](https://cli.github.com/manual/gh_pr_create)
- [GitHub CLI: editing PRs](https://cli.github.com/manual/gh_pr_edit)
