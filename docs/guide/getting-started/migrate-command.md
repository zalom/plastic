# Migrate command

`plastic migrate stores` moves every store under one `stores/` directory. The global store
becomes `~/.plastic/stores/global/`, and each project store becomes `~/.plastic/stores/<slug>/`.
You run it once. Until you run it, Plastic keeps reading the old layout.

## Commands

The following table shows each command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic migrate` | Lists the migrate subcommands. |
| `plastic migrate stores --dry-run` | Prints the copy, every move and every rewrite, and changes nothing. |
| `plastic migrate stores` | Copies the home, moves the stores and rewrites the recorded paths. |

Every command takes `--json`.

## What moves

The following table shows where each entry goes:

| Before | After |
| ------ | ----- |
| `~/.plastic/store/` | `~/.plastic/stores/global/store/` |
| `~/.plastic/INDEX.md` | `~/.plastic/stores/global/INDEX.md` |
| `~/.plastic/roadmaps/` | `~/.plastic/stores/global/roadmaps/` |
| `~/.plastic/projects/<slug>/` | `~/.plastic/stores/<slug>/` |

Everything under `projects/` moves, including a directory that `projects.yml` does not list.
The command then removes the empty `projects/` directory.

## What is rewritten

The command rewrites the old paths in these files, when they exist:

- `~/.plastic/config.yml`, where `project_roots` names the projects directory.
- `~/.config/qmd/index.yml`, where each collection names its store.
- `knowledge_graph.db` and `references.db`, where each row names its file.

The command keeps the earlier `config.yml` and `index.yml` beside the new ones, with the suffix
`.before-stores-move`.

## The copy

Before anything moves, the command copies the whole home to `~/.plastic-before-stores-move`.
The output ends with the `rm -rf` command that removes the copy. Run `plastic doctor` first, and
remove the copy when the doctor passes.

To go back, remove `~/.plastic` and rename the copy to `~/.plastic`.

## When the command refuses

The command exits 3 and changes nothing in each of these cases:

- `~/.plastic/stores/` exists, so the home has moved already.
- An intent holds a fresh `delivery.lock`. A lock older than the lock lifetime does not block the move.
- `~/.plastic-before-stores-move` exists from an earlier run.
