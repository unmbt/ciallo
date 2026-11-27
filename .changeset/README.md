# Changesets

This workspace uses [`unmbt/moonset`](https://github.com/unmbt/moonset) to manage multi-module versioning, changelogs, and topological publishing to `mooncakes.io`.

- Record a change: `moonset add`
- Preview status & release plan: `moonset status --verbose` / `moonset publish-plan --pretty`
- Apply versions & changelogs: `moonset version`
- Dry-run publish: `moonset publish --dry-run`
