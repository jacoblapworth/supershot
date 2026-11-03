# Agent Instructions

## Project workflow

For project tasks, including refinement, implementation, and review handoffs, read
[project-workflow](.agents/skills/project-workflow/SKILL.md) before starting.
It owns Linear tracking, task ownership, and the authorization to publish task branches and draft PRs.

## Database schema

Supershot has not shipped, so `SupershotPackage/Sources/Database/Schema.swift` must define the complete current
database schema in its single `Create schema` migration. Update that migration directly
when changing the schema; do not add incremental migrations or migration tests.

Once the app ships, preserve migration history and use forward-only migrations for schema
changes. Update these instructions when that transition occurs.
