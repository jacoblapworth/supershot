# Tower branch metadata and review

When the installed `gittower` CLI supports branch metadata, record the parent after branching:

```sh
gittower branch parent <branch> --set <parent>
gittower branch parent <branch>
```

Enable stacking only for dependent work, after setting its parent:

```sh
gittower branch stacked <branch> --set
```

A normal branch from `main` has a parent without being stacked. Use the CLI rather than
editing Tower configuration directly. Check the installed CLI's capabilities; older
launchers and cloud environments may lack these commands.

Tower metadata is local and does not travel with pushed branches. When unavailable,
record the intended parent and stacking in the Linear issue and final handoff so it
can be applied locally. Keep this metadata out of repository files.

For a requested visual review, use supported Tower commands such as `working-copy`,
`history <branch>`, or `branches-review --branch <branch> --base <parent>`.
Use Git for branch creation, staging, commits, fetching, and pushing. Missing Tower
support leaves a metadata handoff, not a blocked task.
