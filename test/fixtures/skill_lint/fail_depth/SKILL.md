---
name: plastic-fail_depth
description: Deliberately trips the references-depth check with a nested file.
user-invocable: true
---

# Fail Depth Fixture

This fixture's `references/` directory nests a file one level too deep, at
`references/sub/deep.md`, when it read `references/sub/deep.md` for the detail.
