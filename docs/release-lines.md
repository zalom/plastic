# Release lines and channels

A push to `alpha`, `beta`, or `main` is the release: `.github/workflows/publish.yml` creates
the tag and the GitHub release for a version that has no tag yet. `install.sh` and
`plastic update` install from those releases.

| Branch | Channel | Version | What it is |
| --- | --- | --- | --- |
| `alpha` | `alpha` | `-alpha.N` | Development. Feature and stage pull requests stack on it. |
| `beta` | `beta` | `-beta.N` | Local testing. It is reset from `alpha` when a whole feature is merged there. |
| `main` | `latest` | no suffix | Everyday use, and what an external user should run. |

`scripts/release-check` enforces the branch-to-suffix pairing.

## The two lanes

**Default lane.** The change merges to `main` by its own pull request, the version is bumped,
and the push to `main` makes a release on the `latest` channel. `main` is merged into `alpha`
after. It is the path for additive, low-risk work that a green suite fully vouches for.

**Beta-verified lane.** The change reaches `beta`, releases on the `beta` channel, is verified
in real use, and then reaches `main` and a stable release.

## Routing rule

Work rides the beta-verified lane when it changes the operational substrate, carries data,
migration, lock or state-format risk, or cannot be fully validated by a hermetic suite alone.
A change to the database layer or the lock is the typical case: a green suite proves the code
correct, but it cannot prove the new substrate survives real use. Everything else takes the
default lane.

## Stable-line guarantees

What a user on the `latest` channel can rely on:

1. `main` is always green and releasable. No pending revert awaiting re-land sits on `main`.
   When something needs beta verification, it comes out of `main` the same day, never left
   half-landed.
2. A stable release carries no pre-release suffix, releases on the `latest` channel, and the
   newest stable release always carries the GitHub "Latest" badge.
3. The release tag always matches the version in `package.json`. `scripts/lib/release_guard.rb`
   checks it.
4. A stable release collects only intents that cleared their lane's bar: a default-lane intent
   by a green suite, a beta-lane intent by a green suite plus real-use verification and the
   owner's sign-off.
5. The channels keep their meaning: `latest` is stable, `beta` is the verification line,
   published but expected to move, and `alpha` is experimental.
