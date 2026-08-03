# Agent Instructions

## Database schema

Supershot has not shipped, so `Supershot/Schema.swift` must define the complete current
database schema in its single `Create schema` migration. Update that migration directly
when changing the schema; do not add incremental migrations or migration tests.

Once the app ships, preserve migration history and use forward-only migrations for schema
changes. Update these instructions when that transition occurs.
