# ACTION_1: G9 backward shim for action files

Three steps, one commit per node, tests first in their own red commit before any code.
Read `spec.md` in this directory before starting; every decision D1 to D14 binds this action.
D8 to D14 came out of the adversarial plan review; they are the corrections, not the nice-to-haves.

Work in `/Users/zlatko/apps/personal/plastic/.claude/worktrees/342--backward-shim` on branch
`plastic/342--backward-shim`. Absolute paths only. Never switch the main checkout's branch.

## Files to touch

- `scripts/lib/action_graph_shim.rb` (NEW)
- `scripts/lib/work_graph_validator.rb` (one guarded branch, one private helper, one require)
- `scripts/lib/installer_core.rb` (ONE line, registering the new lib; see S2)
- `test/action_graph_shim_test.rb` (NEW, write FIRST)
- `test/work_graph_validator_test.rb` (additive cases only, never edit an existing assertion)
- `test/action_shim_live_store_test.rb` (NEW)
- `test/fixtures/legacy_intents/` (NEW, copied real intent directories)
- `CHANGELOG.md`, one line under Unreleased

Out of bounds, owned by leads running in parallel right now: `scripts/hook-capture`, `.github/`,
the releasing skill, `project.yml`, `scripts/node-transition`, the ready-set code, the packet
command, outcome generation, `scripts/lib/report_screen.rb`. `scripts/end-intent` is read, never
written.

### S1 - ActionGraphShim: an action directory presents as a node graph

New module `ActionGraphShim` in `scripts/lib/action_graph_shim.rb`, `module_function`, pure and
side-effect-free. It requires `graph_file`, `graph_edges`, `node_file` and `savepoint`. It
writes nothing, anywhere, ever (D1).

Public surface:

- `shape(intent_dir)` returns `:authored` when `graph.md` exists, `:actions` when it does not
  but `Savepoint.has_real_files_in?("actions", intent_dir)` is true, `:none` otherwise. Call
  that helper; do not reimplement it and do not call `Savepoint.stage_file_present?` on its own,
  which returns true for an empty file at `scripts/lib/savepoint.rb:84` (D7). A directory that
  does not exist returns `:none` and never raises.
- `view(intent_dir)` returns the seven-key hash `GraphFile.parse` returns: `ok:`, `goal:`,
  `decisions:`, `graph:`, `status:`, `verify:`, `errors:`. On `:authored` it delegates to
  `GraphFile.parse(File.join(intent_dir, "graph.md"))` and returns the result unmodified (D3).
  On `:actions` it builds the same hash, with `goal:` nil, `decisions:` nil, `status:` nil,
  `graph:` the `{nodes:, edges:, errors:}` hash `GraphEdges.parse` shape uses, and `verify:` set
  to `{reason: "backward shim: legacy actions/ carry no verify node"}` so the synthetic view is
  self-consistent if a caller routes it through a trivial-bar check. On `:none` it returns
  `GraphFile.failure` with the same not-found error `GraphFile` gives.
- `nodes(intent_dir)` returns node records for BOTH shapes (D8). On `:actions` they are
  synthesized from the action files. On `:authored` they are `NodeFile.parse` of each
  `nodes/*.md`, sorted by path, each with three fields added. On `:none` it returns `[]`. A
  record always carries every field `NodeFile.parse` returns (`ok:`, `node:`, `kind:`, `files:`,
  `budget:`, `body:`, `errors:`) plus `needs:`, `path:` and `proven_by:`. Identical key set for
  both shapes: that is what lets 338 and 339 read one call instead of branching.
- `needs(intent_dir, node_id)` returns the needs targets for a node under either shape, and `[]`
  for an id the graph does not declare or for a directory with no graph.

Synthetic node construction (D4, D9, D10, D11):

- Glob `actions/*.md`, any basename. 44 of the 58 distinct action basenames in the live store
  are not `ACTION_N.md`: `ACTION-1-bridge-ledger-api.md`, `ACTION_1_milestone_map.md` and
  `01-roadmap-queue-reader.md` are all live forms.
- Keep only real files: `File.file?`, `File.size > 0`, `Savepoint.stage_file_present?`.
- Sort by `[has_integer ? 0 : 1, first_integer_run_or_zero, basename]`. The key must be a total
  order over every basename in the glob; a nil in a sort key raises `ArgumentError` and takes
  the caller down. Use the FIRST integer run in the basename, so `ACTION_1_milestone_map` is 1
  and `01-roadmap-queue-reader` is 1.
- Position `i`, counting from 1, mints `n<i>`. Every id must satisfy `/\An[1-9][0-9]*\z/`, the
  work-kind rule `NodeFile` enforces.
- `kind:` is `"work"`. `budget:` is `nil`. `ok:` is true and `errors:` is `[]` for any file that
  reads; a file that raises on read yields a record with `ok: false` and the error, and the
  sweep continues.
- `needs:` is `["n<i-1>"]`, and `[]` for the first node, which is the root.
- `files:` reads the first heading whose first token is `Files`, case-insensitively, UNLESS the
  heading text carries a negation (`not`, `never`, `don't`, `avoid`), in which case that heading
  is not a files section and the search continues. Take the backticked spans from anywhere in
  that section's body, in order, de-duplicated. No qualifying heading gives `[]` with `ok: true`
  (D9): 573 of 709 live action files have no files heading at all.
- `body:` is the file's full text.
- `proven_by:` is the `S\d+` tokens of that file's headings, in heading order, taking a heading
  only when `NodeFile.table_rows` finds at least one data row under it (D5). Use
  `NodeFile.split_by_headings` and `WorkGraphValidator.heading_tokens` UNMODIFIED; that method's
  output is pinned equal to `ReportScreen.heading_tokens` by
  `test/work_graph_validator_test.rb:244`, so never adapt it for `S` extraction.

Edges: build the `{nodes:, edges:, errors:}` hash directly rather than rendering a `## Graph`
section and re-parsing it. `nodes` is the minted ids in order, `edges` maps each id to its needs
array, `errors` is `[]`.

| Operation | Failure mode | Test |
| --- | --- | --- |
| Resolve realness | `stage_file_present?` alone returns true for an empty file, so an empty `ACTION_2.md` mints a phantom node and the chain gains a link with no work in it | `action_graph_shim_test#test_empty_and_sentinel_action_files_are_not_nodes` |
| Resolve a missing directory | The shim raises on a path that does not exist, and the CLI that pins exit 1 for `no-such-dir` blows up instead | `action_graph_shim_test#test_shape_none_for_missing_dir` |
| Order action files | The sort key holds a nil for a basename with no integer, raising `ArgumentError` and killing the sweep; or lexical order puts `ACTION_10` before `ACTION_2` and wires the chain backwards | `action_graph_shim_test#test_action_files_order_numerically`, `action_graph_shim_test#test_sort_key_is_total_over_mixed_basenames` |
| Glob action files | The glob assumes `ACTION_N.md`, so the 44 other live basenames yield no nodes at all | `action_graph_shim_test#test_non_action_n_basenames_become_nodes` |
| Mint node ids | An id fails `NodeFile`'s work-kind rule, so a consumer written against Batch 1 rejects it | `action_graph_shim_test#test_minted_ids_satisfy_node_file_rules` |
| Chain edges | The first node needs a target that names no node, or the chain closes into a cycle | `action_graph_shim_test#test_chain_is_acyclic_with_one_root` at 1, 2, 7 and 14 files |
| Parse the files section | Only an exact `## Files` matches, so `## Files to touch` yields `[]` and a consumer believes the node touches nothing | `action_graph_shim_test#test_files_section_spellings_agree` |
| Parse a negated files section | `## Files in hooks/ you must NOT change` publishes the files the action forbids touching as the files the node writes, which is live in `235/actions/ACTION_2.md` | `action_graph_shim_test#test_negated_files_heading_is_not_a_files_section` |
| Extract paths from a files section | Only list items are read, so the 24 live sections that carry their paths in a table or a continuation line yield `[]` | `action_graph_shim_test#test_files_paths_come_from_tables_and_continuation_lines` |
| Emit a record with no declared files | The shim copies `NodeFile`'s absent-`files:` error, so 573 live action files read as broken | `action_graph_shim_test#test_missing_files_section_is_ok_with_empty_files` |
| Read Proven-by labels | A heading mentioning `S1` in prose with no table becomes a label, repeating 334's false-label defect | `action_graph_shim_test#test_proven_by_requires_an_owned_table` |
| Resolve the shape | An intent holding both `graph.md` and `actions/` gets a synthetic chain too, so two conflicting graphs exist; all six graph-era intents are this case | `action_graph_shim_test#test_authored_graph_wins_over_actions` |
| Ask for node records on an authored intent | The caller gets `[]`, concludes the intent has no nodes, and writes the shape branch the shim exists to remove | `action_graph_shim_test#test_nodes_returns_records_for_authored_shape` |
| Keep one record shape across both shapes | The two shapes return different key sets, so a consumer still branches | `action_graph_shim_test#test_record_key_set_identical_across_shapes` |
| Answer needs for an unknown id | The caller gets nil and crashes on `.any?` | `action_graph_shim_test#test_needs_returns_empty_for_unknown_id` |
| Read an unreadable action file | The shim raises and takes its caller down mid-sweep | `action_graph_shim_test#test_unreadable_action_file_does_not_raise` |

Commit the tests red first, then the module, then drive them green.

### S2 - The validator accepts both shapes

In `scripts/lib/work_graph_validator.rb`, at the point where `validate` returns early because
`parsed[:graph]` is nil, insert one guarded branch: when `graph.md` does not exist and
`ActionGraphShim.shape(intent_dir)` is `:actions`, validate the synthetic graph and return that
result. Otherwise the existing hard return runs unchanged, word for word (D6).

The branch must start a FRESH error list (D12). `validate` runs `errors.concat(parsed[:errors])`
at line 28, before the branch; on an actions-only intent that list already holds
`"graph file not found: ..."`, so reusing it returns `ok: false` for every legacy intent and the
whole change is a no-op you will not notice until the live-store test in S3.

Synthetic validation, in a new private helper in the same file, checks four things and nothing
else: at least one node; ids unique; every needs target names a declared node; acyclic via
`GraphEdges.cycle`. It never applies the kind-section rules, the failure-mode matrix bar or the
verify-attachment bar, because a legacy action file labels its headings `S1` or nothing at all
and would fail a bar it was never asked to meet.

Add `require_relative "action_graph_shim"` at the top with the other requires. Then add ONE line
to `scripts/lib/installer_core.rb`, beside `"scripts/lib/work_graph_validator.rb"` at line 487:

```ruby
"scripts/lib/action_graph_shim.rb" => "scripts/lib/action_graph_shim.rb",
```

Without it `test/install_sync_test.rb:64`, `test_every_lib_to_lib_require_is_distributed`, goes
red on contact: it walks every registered lib and asserts each `require_relative` target is
registered too (D13).

Keep the rest of the diff to the require, one branch, and one helper appended after the existing
private helpers, so 336's rebase on this file resolves by keeping both sides.

Strings this change must keep verbatim:

- `"graph.md ## Graph section"` at `work_graph_validator.rb:32`, asserted on the empty-dir path.
- `WorkGraphValidator.heading_tokens` output, pinned equal to `ReportScreen.heading_tokens`
  across six heading shapes by `test/work_graph_validator_test.rb:244`.
- The CLI contract: `OK: <dir>` on stdout at `scripts/validate-work-graph:32`, empty stdout plus
  non-empty stderr on failure, exits 0, 1 and 2.
- `setup` at `test/work_graph_validator_test.rb:99` creates `nodes/` and never `actions/`. Leave
  it alone, or existing authored cases start resolving through the shim.

Nothing but `scripts/validate-work-graph:29` and that test file calls
`WorkGraphValidator.validate` in the whole tree. Do not go hunting for callers to re-point.

| Operation | Failure mode | Test |
| --- | --- | --- |
| Validate an actions-only intent | The hard return on a missing `## Graph` fires first, so all 201 live actions-only intents read INVALID | `work_graph_validator_test#test_actions_only_intent_validates` |
| Build the synthetic verdict | The branch reuses the accumulated error list, which already holds the not-found error, so `ok:` is false and both `missing` and `errors` must be asserted empty to catch it | `work_graph_validator_test#test_actions_only_intent_returns_no_errors` |
| Validate an authored intent | The new branch changes an authored graph's verdict, silently loosening Batch 1 | `work_graph_validator_test#test_authored_invalid_graph_still_fails_unchanged` |
| Validate an empty intent directory | A directory with neither a graph nor a real action passes silently | `work_graph_validator_test#test_empty_intent_dir_still_missing_graph_section` |
| Apply the quality bars to the synthetic shape | The matrix bar runs against `n1..nN`, failing nearly every intent in the store | `work_graph_validator_test#test_synthetic_shape_skips_matrix_and_verify_bars` |
| Reach the shim when `graph.md` exists but is malformed | A typo'd or half-written `graph.md` falls through to a synthetic chain and hides the error | `work_graph_validator_test#test_malformed_graph_md_does_not_fall_through_to_actions` |
| Register the new library | `install_sync_test` goes red because the validator now requires an unregistered lib | `install_sync_test#test_every_lib_to_lib_require_is_distributed` |
| Hold the CLI contract | The actions path prints to the wrong stream or returns the wrong exit code | `work_graph_validator_test#test_cli_exits_zero_on_actions_only_dir` |

### S3 - Verification against the live store

Copy real intent directories into `test/fixtures/legacy_intents/`, never read the live store from
a test. Take seven from `~/.plastic/projects/plastic/store`:

| Fixture | Action files | Why it is in the set |
| --- | --- | --- |
| 193 | 1 | Single-file chain; on 334's hollow-close probe list |
| 195 | 2 | Two-node chain |
| 197 | 13 | The only live directory where `ACTION_10` sorts against `ACTION_2` |
| 211 | 5 | Mid-size chain |
| 235 | 7 | Carries the live negated files heading in `ACTION_2.md` |
| 331 | 1 | Most recent completed intent 334 probed |
| 82 | 5 | A Future intent, and the only fixture using the `ACTION-N.md` hyphen form |

Copy the record, `actions/`, `spec.md`, `plan.md` and `checklist.md`; drop `savepoint.md`,
`delivery.lock` and `resources/`.

`test/action_shim_live_store_test.rb` asserts each fixture resolves to `:actions`, that its node
count equals its real action-file count, that its chain is acyclic with a single root, that ids
run `n1..nN` in the order a human reading the filenames would expect, and that
`WorkGraphValidator.validate` returns `ok: true` with empty `missing` and empty `errors`.
For 235 it asserts `n2`'s `files:` is `[]`, not the five paths its negated heading forbids.
For 197 it asserts the node for `ACTION_2.md` is `n2` and the node for `ACTION_10.md` is `n10`.

Dogfood proof: a test reads a copy of this intent's own `actions/ACTION_1.md` through the shim
and asserts the record's KEY SET equals the key set of a `NodeFile.parse` of a copy of this
intent's authored `nodes/n1.md`, plus the three added fields, and that `node` is `"n1"` and
`kind` is `"work"`. Do not assert `files` equality: this action file's files section lists eight
paths and `nodes/n1.md` declares two, so a value comparison would be false, and `node` and `kind`
alone are a tautology under D4. The shape claim is the real claim; assert the shape.

Then, outside the suite, record two probes in `outcome.md`:

1. `hollow_report_reason` returns nil for intents 193, 195, 197, 211, 225, 235 and 331, the seven
   334 re-probed. This cannot fail by construction, since `scripts/end-intent:251` reads only
   `outcome.md` and heading tokens and never touches the validator or the shim. It is recorded as
   a regression sanity check, not as a matrix row.
2. `ruby scripts/validate-work-graph` exits 0 on at least twenty real actions-only directories in
   the live store, read-only, and 0 on this intent's own authored directory.

| Operation | Failure mode | Test |
| --- | --- | --- |
| Probe a real intent directory | The shim raises or reports `:none` on a real legacy intent, so the whole store stays invisible to Batch 2 | `action_shim_live_store_test#test_every_fixture_resolves_to_actions` |
| Order a real 13-file directory | Numeric ordering that passes on an invented three-file fixture still fails on the one live directory that has the collision | `action_shim_live_store_test#test_197_orders_action_10_after_action_2` |
| Read a real negated files heading | The 235 fixture publishes forbidden paths as the node's files | `action_shim_live_store_test#test_235_node_2_declares_no_files` |
| Read a real hyphen-form basename | The Future fixture's `ACTION-N.md` files yield no nodes | `action_shim_live_store_test#test_82_hyphen_form_becomes_a_chain` |
| Validate a real intent directory | A real action file trips a validation rule an invented fixture never exercises | `action_shim_live_store_test#test_every_fixture_validates_ok` |
| Prove the dogfood claim | The synthetic record and an authored node record differ in key set, so a consumer needs two code paths after all | `action_shim_live_store_test#test_dogfood_record_key_set_matches_authored_node` |
| Keep the suite green | A regression lands somewhere else in the tree | `ruby bin/test` reports zero failures on the branch and again on `alpha` after the merge |

## Hard rules

- Tests land in their own commit, red, before the code that turns them green. One commit per
  node after that: `n1`, then `n2`, then `v1`.
- Conventional Commits. No AI attribution of any kind. Hyphens, never em or en dashes, in every
  file you write.
- No version bump, no release, no PR. Merge into `alpha`, never `main`.
- Do not edit an existing assertion in `test/work_graph_validator_test.rb`. Add cases.
- Never write to `~/.plastic/projects/plastic/store`. Copy fixtures out of it, read-only.
- If `alpha` moved while you worked, rebase and rerun the full suite before merging.
