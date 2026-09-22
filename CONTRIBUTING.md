# Contribute to Plastic

[AGENTS.md](AGENTS.md) holds the rules for working on this repository: intents, worktrees,
commits and releases. This page points to the rest.

| Read | For |
| ---- | --- |
| [docs/contributing/ARCHITECTURE.md](docs/contributing/ARCHITECTURE.md) | How the `plastic` command is built, and where the system architecture lives. |
| [docs/contributing/CODING_PRACTICES.md](docs/contributing/CODING_PRACTICES.md) | How Ruby is written and tested here. |
| [docs/contributing/TECHNICAL.md](docs/contributing/TECHNICAL.md) | The gates, the byte budget and the test layout. |

## Add a command

1. Add one row to `scripts/lib/cli/table.rb`: the name, the file, the class and the help line.
2. Add one file under `scripts/lib/cli/commands/` with a `USAGE_LINE` and a public `call`.
3. Write the tests first and commit them red.
4. Run the gates once: `bundle exec ruby bin/verify-change <base commit>`.
5. Add the command to [README.md](README.md) and [docs/usage/FEATURES.md](docs/usage/FEATURES.md) in the same change.

## Cut a release

1. Bump the three version files: `package.json`, `.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json`.
2. Add or update the entry in `deprecations.yml` for anything this release removes or
   replaces.
3. Push the branch: `alpha`, `beta`, or `main`. The push is the release:
   `.github/workflows/publish.yml` creates the tag, the GitHub release, and the npm publish
   for a version with no tag yet.
4. Read [docs/release-lines.md](docs/release-lines.md) for the routing rule between the two
   lanes and the stable-line guarantees.
