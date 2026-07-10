---
name: plastic-fail_user_invocable
description: Deliberately trips the frontmatter-validity user-invocable sub-check (field missing).
---

# Fail User Invocable Fixture

The frontmatter above has no `user-invocable:` key at all, which must trip the
sub-check requiring it to be present and boolean.
