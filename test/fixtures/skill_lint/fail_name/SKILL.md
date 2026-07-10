---
name: fail_name
description: Deliberately trips the frontmatter-validity name sub-check (bug shape from intent 158).
user-invocable: true
---

# Fail Name Fixture

The frontmatter `name:` above is `fail_name`, the bare directory name, lacking
the required `plastic-` prefix. The corrected rule requires
`name == "plastic-#{directory}"`, i.e. `plastic-fail_name` here.
