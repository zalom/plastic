---
name: plastic-fail_yaml
description: Use when doing X: like this, an unquoted colon that breaks strict YAML.safe_load.
user-invocable: true
---

# Fail YAML Fixture

Deliberately trips the frontmatter-validity YAML-safe sub-check: the
`description:` value above contains an unquoted colon-space sequence, the
exact intent-165 failure shape.
