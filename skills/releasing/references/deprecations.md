# Deprecation Process

When removing a feature, changing a convention, or making a breaking change:

1. Add entry to `deprecations.yml` in the Plastic source root
2. Set severity: `info` (awareness), `warning` (action needed), `critical` (urgent)
3. Provide clear migration steps
4. Set `removal` version at least 2 minor versions ahead
5. SessionStart hook displays active deprecations automatically
6. Remove the feature AND the deprecation entry together

## Pre-1.0 removal policy

The numbered process above is the steady-state rule: a deprecation rides until its `removal`
version, which step 4 sets at least two minors ahead. While Plastic is still pre-1.0 (any
version below `1.0.0`), one exception applies:

- **Pre-1.0 exception.** Before `1.0.0`, a *satisfied* deprecation (the migration it
  announced is complete on installed machines) may be removed immediately, rather than waiting
  for its declared `removal` major. Delete the entry from `deprecations.yml` (leaving
  `deprecations: []` if it was the last one) the moment the migration is done.

This exception only holds below `1.0.0`. From `1.0.0` onward, the steady-state grace rule
(step 4, removal at least two minors ahead) governs again, unchanged. The exception narrows
*when* a satisfied entry may be pulled early during the pre-release line; it does not loosen
the grace window for the released-product contract.

## Severity Levels

| Severity | When to use | Dismissable? |
|----------|-------------|--------------|
| `info` | Upcoming change | Yes |
| `warning` | Action needed | Yes (re-shown at removal) |
| `critical` | Urgent/security | Never |

## deprecations.yml Schema

```yaml
deprecations:
  - id: unique-slug
    severity: info | warning | critical
    summary: "One-line description"
    migration_steps:
      - "Step 1"
      - "Step 2"
    introduced: "0.9.0"
    removal: "1.0.0"
    link: "optional URL"
```

## Dismissal

Users dismiss by adding the id to `deprecations_dismissed` in `config.yml`:

```yaml
deprecations_dismissed:
  - some-deprecated-feature
```

Critical deprecations and final-version warnings ignore dismissal.
