# Screenshot evidence for PRs

Capture and upload are separate capabilities. A local screenshot is evidence in the chat;
GitHub needs an uploaded image URL accessible to reviewers to render it in a PR.

## Capture the implementation

Use device-interaction for app verification and the available simulator or device tools.
Capture the changed workflow with representative data, inspect each image, and label the
state it demonstrates. Include before/after evidence when useful and safe to obtain.
Exclude private information. Save durable local artifacts and show them in the handoff.
For a capture failure, name the exact environment or interaction blocker and the unverified behavior.

## Choose a supported upload route

1. Inspect the available GitHub connector tools. Use a native attachment action if exposed.
   A PR body field alone accepts Markdown; it does not upload a local file. MCP itself can
   carry upload tools, so a missing action is a connector capability gap, not a protocol ban.
2. If the connector lacks uploading, check `gh pr create --help` and `gh pr edit --help`
   for `--attach`. When supported, use GitHub's native CLI attachment path:

   ```sh
   gh pr create --draft --base <parent> --head <branch> \
     --title '<title>' --body-file <body-file> \
     --attach '/absolute/path/after.png#Updated game screen'
   ```

   For an existing PR, use `gh pr edit <pr-url> --attach '<path>#<caption>'`.
   Uploading requires push access and compatible authentication. On failure, report the
   exact error without exposing credentials. Check whether the PR or some uploads succeeded
   before retrying, because partial success can still produce a nonzero command result.
3. If installed tools lack attachments, use an available authenticated browser upload when
   it supports local files, or an existing repository-approved media host. Keep publication
   scoped to this PR; obtain authorization before introducing a new host or committing images
   solely for hosting. Otherwise hand off the local images for manual attachment and
   explicitly mark the PR evidence as pending.

After upload, read back the PR body and inspect the resulting rendered images when possible.
Record any remaining inability to verify reviewer access. Local paths and chat attachment
references must be replaced with the actual uploaded URLs in a published PR.

## Capability references

Check installed tools rather than assuming the latest online documentation matches them.
Treat these as lookup references, not a reason to skip capability detection:

- [GitHub: attaching files with the CLI](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli)
- [GitHub CLI: creating PRs](https://cli.github.com/manual/gh_pr_create)
- [GitHub CLI: editing PRs](https://cli.github.com/manual/gh_pr_edit)
