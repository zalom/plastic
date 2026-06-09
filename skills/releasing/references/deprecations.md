# Deprecation Process

When removing a feature, changing a convention, or making a breaking change:

1. Add entry to `deprecations.yml` in the Plastic source root
2. Set appropriate severity: `info` (awareness), `warning` (action needed), `critical` (urgent)
3. Provide clear migration steps — never deprecate without telling the user what to do
4. Set `removal` version at least 2 minor versions ahead (warning) or 1 minor (info)
5. The SessionStart hook displays active deprecations automatically
6. Remove the feature AND the deprecation entry together in the removal version

## Severity Levels

| Severity | When to use | Dismissable? |
|----------|-------------|--------------|
| `info` | Awareness of upcoming change | Yes |
| `warning` | Action needed before removal | Yes (re-shown at removal version) |
| `critical` | Urgent/security-related removal | Never |

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

Users dismiss deprecations by adding the id to `deprecations_dismissed` in `config.yml`:

```yaml
deprecations_dismissed:
  - some-deprecated-feature
```

Critical deprecations and final-version warnings ignore dismissal.
