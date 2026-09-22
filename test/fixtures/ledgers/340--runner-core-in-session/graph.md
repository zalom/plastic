# Graph: G7 Runner core in the harness session

## Goal
One command drives a graph-era intent node by node. `runner step` sweeps, validates, absorbs the
returns of the last turn, and dispatches the next ready nodes at concurrency two, printing a
harness-neutral dispatch plan the session spawns from. `done` is written only on code-verified
evidence: a schema-valid return, clean core integrity, an in-scope diff, named tests that exist, a
clean merge into the intent branch, and a green suite the runner ran itself.

## Decisions
- D1 Three public verbs on `scripts/runner`: `step`, `status`, `answer`. `ready`, `sweep` and
  `rewind` work but stay out of the skill body.
- D2 Ruby does everything deterministic and prints a dispatch plan; the session spawns the agent.
  No Ruby process ever spawns one.
- D3 Concurrency two is a ceiling on `running` nodes checked in Ruby, not a thread pool.
- D4 The return is one closed-schema YAML document parsed by the runner, not by
  `node-transition`; unparsable is `failed_verification reason=return_unparsable`.
- D5 The packet is not extended. The return contract rides in the dispatch prompt after it.
- D6 Work nodes get a per-node worktree off the intent branch. Verify, research and decision
  nodes get none.
- D7 A node worktree is merged and removed at `done`, kept at `failed_verification` and
  `needs_decision`, removed at `superseded` and `abandoned`.
- D8 A merge conflict entirely inside `files:` is `failed_verification`; one touching a path
  outside `files:` is `needs_decision` naming the paths.
- D9 A verify or research node with any diff fails; a work node with a path outside `files:`
  fails.
- D10 The runner runs the project's tests itself at `done` and writes `suite=`.
- D11 Core integrity is re-hashed from the installed manifest after every return, before any
  transition; drift stops the step unless `--allow-core-drift` is given and recorded.
- D12 Kind policy sets model, worktree, retry cap and diff rule. Decision nodes are never
  dispatched.
- D13 An extension is a line in `packets/<node>--a<N>.extensions`, capped at two per attempt,
  because a second `running` line is refused by the transition layer.
- D14 The `MERGE_HEAD` abort runs first in every step; the reclaim pass runs after absorb and
  never touches a node named in a `--return` of the same step.
- D20 `gates=` is required on `done` and `failed_verification`: a plus-joined list of the checks
  that ran, from `integrity`, `schema`, `scope`, `named_tests`, `merge`, `suite`.
- D21 An empty ready set is completion only when every declared node is terminal; otherwise the
  step reports stalled with each unfinished node's blockers.
- D22 Two caps: the runner's soft retry cap parks a node at `needs_decision`, and
  `ReadySet::DEFAULT_CAPS` stays the transition layer's hard backstop. `runner answer` unparks a
  work node, by respin when the hard cap is reached; `rewind` respins too.
- D23 The runner injects a node-scoped `worktree_reader:` so the packet names the node worktree.
- D24 `NodeWorktree` owns its merge in the intent worktree; `Worktree.merge_branch` is not reused.
- D25 Each node registers its own libs in `InstallerCore.core_files`.
- D26 A runner-owned reaper sweeps `<repo>/.claude/worktrees/`; `WorktreeSweep` is left alone.
- D28 `graph.md` `## Status` re-renders after every transition the runner writes.
- D15 The runner mints proposed node ids; a proposed edge into a `running` node is refused.
- D16 Findings land as one capped Insight line per node per return under `### Findings`.
- D17 The full validator runs before the first dispatch; a cycle check runs before every one.
- D18 `done` is written only on code-verified evidence.

## Graph
Edges, `needs` only; the head needs the tail done. The literal target `nothing` declares a root.
- n1 needs nothing
- n2 needs n1
- n3 needs n1
- n4 needs n1 n3
- n5 needs n2 n3
- n6 needs n4 n5
- n7 needs n6
- n8 needs n7
- v1 needs n1 n2 n3 n4 n5 n6 n7 n8
- n9 needs v1
- n10 needs n9
- v2 needs n9 n10
- n11 needs v2
- v3 needs n11

## Status
| Node | State | Detail |
| --- | --- | --- |
| n1 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=b43b170 |
| n2 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=5a17238 |
| n3 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=2d2e4f9 |
| n4 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=0c60358 suite=3886/19751/0/0 |
| n5 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=96882ef suite=3921/19893/0/0 |
| n6 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=ba87504 suite=3950/20006/0/0 |
| n7 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=1d0b154 suite=3955/20025/0/0 |
| n8 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=e94175b suite=3962/20068/0/0 |
| v1 | done | holder=auto-6aa701e173 model=opus gates=integrity+schema+scope verdict=revise |
| n9 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=ce67e2a suite=3977/20115/0/0 |
| n10 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=25318b1 suite=3999/20213/0/0 |
| v2 | done | holder=auto-6aa701e173 model=opus gates=integrity+schema+scope verdict=revise |
| n11 | done | holder=auto-6aa701e173 model=sonnet gates=integrity+schema+scope+named_tests+merge+suite commit=ed5bcc3 suite=4017/20285/0/0 |
| v3 | done | holder=auto-6aa701e173 model=opus gates=integrity+schema+scope verdict=accept |
