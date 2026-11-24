# Release lines and channels

Plastic has three release branches. `beta` holds the line being tested, `alpha` holds new work
that does not belong to that line yet, and `main` holds the stable release. The owner ruled this
flow on 24 November 2026. `main` has no freeze: it takes `beta` when the owner says a release is
coming.

A push to `alpha`, `beta`, or `main` is the release: `.github/workflows/publish.yml` creates
the tag and the GitHub release for a version that has no tag yet. A push whose version already
has a tag publishes nothing. `install.sh` and `plastic update` install from those releases.

| Branch | Channel | Version | What it holds |
| --- | --- | --- | --- |
| `alpha` | `alpha` | `-alpha.N` | New feature work that does not belong to the line on `beta`, such as connecting Plastic with another project. |
| `beta` | `beta` | `-beta.N` | The line being tested. The work on it is built and fixed there. |
| `main` | `latest` | no suffix | The stable release. It takes `beta` on the owner's word. |

`bin/release-check` enforces the branch-to-suffix pairing, and the test workflow runs the suite
on every push and every pull request to the three branches.

## The rules

1. **Every change has its own pull request.** A change lands on its branch once CI passes.
2. **The tested line lives on `beta`.** Once work moves from `alpha` to `beta`, building and
   fixing that work continue on `beta`. A bug found in a beta is fixed on `beta`.
3. **`alpha` always holds what ships first.** After each change lands on `beta`, `beta` is
   merged into `alpha`.
4. **`main` releases on the owner's word.** When the owner says a release is coming, `beta` is
   merged into `main` and released. `beta` then moves to `main`, and `main` is merged into
   `alpha`.
5. **A fix to a stable release lands on `main`.** It is merged into `beta` or `alpha`, where the
   next work carries it.
6. **A branch moves only by a merge or a fast-forward.** No branch is force-pushed, and a pushed
   branch is never rebased.
7. **A migration ships clean, with no config switch.** The owner ruled so on 24 November 2026.
   A clean install and an update from the previous release prove each release, as the section
   [Prove a release before the push](#prove-a-release-before-the-push) says.

## Merge one branch into another

Each branch keeps its own version in `package.json`. When a merge between two branches stops on
that file, keep the version of the branch that receives the merge. In `CHANGELOG.md`, keep the
lines of both sides. Make each merge by its own pull request, so CI runs the suite on the result.

## Move work from alpha to beta

The owner decides which work moves to `beta`, and when.

1. Branch from `beta` and merge `alpha` into that branch, keeping the version of `beta`.
2. Open a pull request into `beta`. From then on, the work is built and fixed on `beta`.

## Release a beta

1. Branch from `beta`. Move the entries under `## Unreleased` in `CHANGELOG.md` to a heading for
   the next `-beta.N` version, set `package.json` to that version, and commit
   `chore: release X.Y.Z-beta.N`.
2. Prove the release with the two installs of the next section.
3. Open a pull request into `beta` and merge it once CI passes. The push to `beta` publishes the
   beta.
4. Merge `beta` into `alpha` by its own pull request, keeping the version of `alpha`.

Raise the version on `alpha` when an alpha release is wanted: the push that carries it publishes
it.

## Release main

1. On the owner's word, branch from `beta`. Move the beta headings of `CHANGELOG.md` that the
   release collects under one heading for the stable version, set `package.json` to that
   version with no suffix, and commit `chore: release X.Y.Z`.
2. Prove the release with the two installs of the next section.
3. Open a pull request into `main` and merge it once CI passes. The push to `main` publishes the
   stable release.
4. Move `beta` to `main`: fast-forward `beta` to `main`, or merge `main` into `beta` when `beta`
   took a change after step 1. The version on `main` already has its tag, so this push publishes
   nothing.
5. Merge `main` into `alpha` by its own pull request, keeping the version of `alpha`.

The next beta release sets `package.json` on `beta` to the first `-beta.N` version of the next
release.

## Fix a stable release

1. Branch from `main`, fix the bug, and set `package.json` to the next patch version.
2. Prove the release with the two installs of the next section.
3. Open a pull request into `main` and merge it once CI passes. The push publishes the fix.
4. Merge `main` into `beta` or `alpha`, where the next work carries the fix, keeping the version
   of the branch that receives it.

## Prove a release before the push

Every beta and every stable release passes two installs in a throwaway home before the push that
publishes it: a clean install in an empty home, and an update from the previous release with that
release's own installer. Both must pass. An alpha release needs neither.

Set each variable from a literal path, never from `$HOME` in the same line. Build the release
files from the release branch first:

```bash
V=X.Y.Z-beta.N; R=/path/to/scratch/release
ruby bin/build-release --version "$V" --directory "$R"
```

### The clean install

The clean install runs every migration from nothing, as a new user's first install does. Install
the build in an empty home, then start Plastic in it:

```bash
S=/path/to/scratch/clean; mkdir -p "$S/boot" "$S/.claude"
tar -xzf "$R/plastic.tgz" -C "$S/boot" package/scripts package/lib
ruby --disable-gems "$S/boot/package/scripts/install-release" --directory "$R" --version "$V" \
  --home "$S/share" --bin "$S/bin" --plastic-home "$S/.plastic" --user-home "$S"
export HOME=$S PLASTIC_HOME=$S/.plastic
"$S/bin/plastic" init a
"$S/bin/plastic" version
"$S/bin/plastic" status
```

`plastic version` must name the new version, and each command must exit 0.

### The update from the previous release

`plastic update` runs the installer of the release already installed, not that of the new one.
So the update proof installs the previous release first and updates it with its own
`scripts/install-release`, the line that `plastic update` prints. Download the previous release,
install it as the clean install does, and give it some work:

```bash
P=/path/to/scratch/previous; U=/path/to/scratch/update; OLD=X.Y.Z-beta.M
gh release download "v$OLD" --dir "$P"
mkdir -p "$U/boot" "$U/.claude" "$U/demo"
tar -xzf "$P/plastic.tgz" -C "$U/boot" package/scripts package/lib
ruby --disable-gems "$U/boot/package/scripts/install-release" --directory "$P" --version "$OLD" \
  --home "$U/share" --bin "$U/bin" --plastic-home "$U/.plastic" --user-home "$U"
export HOME=$U PLASTIC_HOME=$U/.plastic
"$U/bin/plastic" init a
"$U/bin/plastic" project new demo "$U/demo"
"$U/bin/plastic" intent new "A first intent" --project demo
```

Then update it to the build with the installer of the previous release, and read the work back:

```bash
ruby --disable-gems -rrbconfig "$U/share/active/scripts/install-release" --directory "$R" \
  --version "$V" --home "$U/share" --bin "$U/bin" --plastic-home "$U/.plastic" --user-home "$U"
"$U/bin/plastic" version
"$U/bin/plastic" status --project demo
```

`plastic version` must name the new version, and `plastic status` must show the intent.

## Follow a pre-release channel

`install.sh` installs the stable release only. To follow a beta or an alpha release, install the
stable release, then name the channel:

```bash
plastic update --channel beta
plastic update --channel alpha
plastic update --channel stable   # Back to the stable channel
```

`plastic update` keeps the release it replaces, so `plastic rollback` can return to it. Without
`--channel`, an update stays on the channel of the active release. `plastic version` prints the
channel.

A store that a run of unreleased code has moved past every release is newer than the installed
code, and every command but `plastic update` refuses it with exit 3. `plastic update` and
`plastic update --dry-run` still run: they leave the store as it is, and an update installs the
newest release of the channel. When no release is newer, `plastic update` and its dry run exit 1
and say the store came from unreleased code; wait for a release that holds its migration.

## Stable-line guarantees

What a user on the `latest` channel can rely on:

1. `main` is always green and releasable. No pending revert awaiting re-land sits on `main`.
2. A stable release carries no pre-release suffix, releases on the `latest` channel, and the
   newest stable release always carries the GitHub "Latest" badge.
3. The release tag always matches the version in `package.json`. `bin/lib/release_guard.rb`
   checks it.
4. A stable release collects only work that a beta carried in real use, with the owner's
   sign-off.
5. The channels keep their meaning: `latest` is stable, `beta` is the line being tested,
   published but expected to move, and `alpha` holds new work that no beta carries yet.
