# Release lines and channels

Plastic is developed on a light trunk: `alpha` is the one line that all work merges into, and
a beta is a snapshot of it.

A push to `alpha`, `beta`, or `main` is the release: `.github/workflows/publish.yml` creates
the tag and the GitHub release for a version that has no tag yet. `install.sh` and
`plastic update` install from those releases.

| Branch | Channel | Version | What it is |
| --- | --- | --- | --- |
| `alpha` | `alpha` | `-alpha.N` | The trunk. Every change and every fix merges here once CI passes. |
| `beta` | `beta` | `-beta.N` | A snapshot of `alpha`, cut on the owner's word. It takes no changes of its own. |
| `main` | `latest` | no suffix | Stable. Frozen while Plastic is being shaped. |

`bin/release-check` enforces the branch-to-suffix pairing.

## The four rules

1. **One trunk.** A change merges to `alpha` by its own pull request as soon as CI passes.
2. **Fixes land on the trunk.** A bug found in a beta is fixed on `alpha`, and the next beta
   carries the fix. No commit lands on `beta` except the cut itself.
3. **Switches only where they pay off.** A change that alters stored data, the storage
   layer or the lock, or one that may be dropped, ships behind a config switch that is off by
   default. Every other change goes straight in.
4. **Stable waits.** `main` takes no release until the shaping ends and the owner opens it.

## Cut a beta

1. On `alpha`, by its own pull request, move the entries under `## Unreleased` in
   `CHANGELOG.md` to a heading for the next `-beta.N` version.
2. Branch from `alpha`. Set `package.json` to that version and commit
   `chore: release X.Y.Z-beta.N`.
3. Merge that commit into `beta` as `chore: beta follows alpha at X.Y.Z-beta.N`, and push
   `beta`. The push publishes the beta.

The release commit stays off `alpha`, which keeps its own `-alpha.N` version. Raise that
version on `alpha` when an alpha release is wanted: the push that carries it publishes it.

The owner decides when a beta is cut. A switched-off change rides along in every cut, and
turning its switch on in a later commit is what releases it.

## Stable-line guarantees

What a user on the `latest` channel can rely on:

1. `main` is always green and releasable. No pending revert awaiting re-land sits on `main`.
2. A stable release carries no pre-release suffix, releases on the `latest` channel, and the
   newest stable release always carries the GitHub "Latest" badge.
3. The release tag always matches the version in `package.json`. `bin/lib/release_guard.rb`
   checks it.
4. A stable release collects only work that a beta carried in real use, with the owner's
   sign-off.
5. The channels keep their meaning: `latest` is stable, `beta` is the verification line,
   published but expected to move, and `alpha` is the trunk.

## After the shaping

When Plastic settles, it moves to full trunk-based development: `alpha` becomes `main`, the
channels become tags instead of branches, a feature-switch module gives each switch a stage
(off, beta, on), and a release branch exists only to patch a published release.
