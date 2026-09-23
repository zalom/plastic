# Registering a project

`plastic project new` registers a directory under a slug. A slug is lowercase
letters, digits and hyphens, and starts with a letter or digit. `global` is
reserved. A directory registered under one slug is not registered again under
another. These scenarios run the public command in a disposable home. No model
is called and the harness plays no part.

Each row gives the slug, the path, the exit and the registered slugs:

| slug     | path       | exit | registered slugs |
| -------- | ---------- | ---: | ---------------- |
| repoa    | new        |    0 | repoa            |
| Bad Slug | new        |    2 | none             |
| global   | new        |    2 | none             |
| repob    | registered |    1 | repoa            |
